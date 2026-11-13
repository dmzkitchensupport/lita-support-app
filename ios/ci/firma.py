"""Firma efímera para CI de LiTa Support (iOS).

  python3 firma.py crear   -> genera llave+CSR, crea certificado DISTRIBUTION y perfil
                              IOS_APP_STORE por la API de App Store Connect, deja
                              dist.p12 / lita.mobileprovision en $RUNNER_TEMP y guarda
                              los IDs en $RUNNER_TEMP/firma.json
  python3 firma.py revocar -> borra el perfil y revoca el certificado creados en 'crear'

Solo necesita ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_P8 (contenido del .p8) en el entorno.
Así ninguna llave privada de firma vive fuera de la corrida.
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.request

import jwt

BUNDLE = "support.lita.app"
TMP = os.environ.get("RUNNER_TEMP", ".")
ESTADO = os.path.join(TMP, "firma.json")


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"], algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def api(method, path, body=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, (json.loads(raw) if raw else {})


def ok(status, data, que):
    if status >= 300:
        print(f"ERROR {que}: {status} {json.dumps(data)[:1500]}")
        sys.exit(1)
    return data


def crear():
    run = lambda *a: subprocess.run(a, check=True, cwd=TMP)
    p12_pass = base64.b16encode(os.urandom(16)).decode()
    run("openssl", "genrsa", "-out", "dist.key", "2048")
    run("openssl", "req", "-new", "-key", "dist.key", "-out", "dist.csr",
        "-subj", "/CN=LiTa CI/C=MX")
    csr = "".join(l for l in open(os.path.join(TMP, "dist.csr")).read().splitlines() if "-----" not in l)

    s, d = api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}")
    bundles = [b for b in ok(s, d, "bundleId")["data"] if b["attributes"]["identifier"] == BUNDLE]
    if not bundles:
        print("ERROR: no existe el bundle ID " + BUNDLE)
        sys.exit(1)
    bundle_id = bundles[0]["id"]

    s, d = api("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION", "csrContent": csr}}})
    cert = ok(s, d, "certificado")["data"]
    open(os.path.join(TMP, "dist.cer"), "wb").write(base64.b64decode(cert["attributes"]["certificateContent"]))
    run("openssl", "x509", "-inform", "der", "-in", "dist.cer", "-out", "dist.pem")
    run("openssl", "pkcs12", "-export", "-legacy", "-inkey", "dist.key", "-in", "dist.pem",
        "-out", "dist.p12", "-passout", "pass:" + p12_pass, "-name", "Apple Distribution")
    os.remove(os.path.join(TMP, "dist.key"))

    nombre = f"LiTa CI {os.environ.get('GITHUB_RUN_NUMBER', int(time.time()))}"
    s, d = api("POST", "/v1/profiles", {"data": {"type": "profiles",
        "attributes": {"name": nombre, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
            "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})
    prof = ok(s, d, "perfil")["data"]
    open(os.path.join(TMP, "lita.mobileprovision"), "wb").write(
        base64.b64decode(prof["attributes"]["profileContent"]))

    json.dump({"cert": cert["id"], "perfil": prof["id"], "perfil_nombre": nombre,
               "perfil_uuid": prof["attributes"]["uuid"], "p12_pass": p12_pass}, open(ESTADO, "w"))
    gh = os.environ.get("GITHUB_ENV")
    if gh:
        with open(gh, "a") as f:
            f.write(f"P12_PASS={p12_pass}\nPERFIL_NOMBRE={nombre}\nPERFIL_UUID={prof['attributes']['uuid']}\n")
    print(f"Certificado {cert['id']} y perfil '{nombre}' creados.")


def revocar():
    if not os.path.exists(ESTADO):
        print("Nada que revocar.")
        return
    e = json.load(open(ESTADO))
    s, _ = api("DELETE", f"/v1/profiles/{e['perfil']}")
    print("perfil borrado:", s)
    s, _ = api("DELETE", f"/v1/certificates/{e['cert']}")
    print("certificado revocado:", s)


if __name__ == "__main__":
    {"crear": crear, "revocar": revocar}[sys.argv[1]]()
