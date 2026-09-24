# ESTADO — lita-support-app (Login Único LiTa Support)

## 2026-09-24 — construcción inicial

**Qué se construyó**: primera versión real (no mockup) del login único de LiTa Support.
Una sola página pública (`index.html`, PWA con `manifest.json`/`sw.js`/`icons/`) donde el
usuario mete correo+contraseña una vez; el JS prueba `rpc_login` contra el proyecto
Supabase de `vitality-control` primero y, si la credencial no valida ahí, contra el de
`cdjsupport` — al que sí valide, redirige a `<portal-real>/portal.html?ssoEmail=<correo>`.
Si ninguno valida, mensaje genérico ("Correo o contraseña incorrectos") sin revelar a
cuál cliente pertenece el correo.

**Alcance honesto (repetido aquí y en CLAUDE.md a propósito, para que nadie lo lea como
más de lo que es)**: NO es SSO criptográfico — no hay token de sesión compartido entre
los 3 orígenes distintos (`dmzkitchensupport.github.io`, `vitality-control.github.io`,
`cdjsupport.github.io`). Es resolución + prellenado de correo vía query param. El usuario
puede tener que volver a escribir su contraseña en el portal real si la sesión no quedó
activa por timing — aceptado a propósito, no se intentó nada más ambicioso.

**Cambio complementario (mismo alcance, repos separados)**: `portal.html` de
`vitality-control` y `cdj-support` ahora prellenan `#login-email` y enfocan `#login-pass`
si la URL trae `?ssoEmail=`. Sin ese parámetro, el login de cada portal funciona
exactamente igual que antes (mismo `rpc_login`, sin cambio de flujo) — ver ESTADO.md de
cada uno de esos 2 repos para el detalle y la verificación de no-regresión.

## Verificación real end-to-end (24 sep 2026)

**Despliegue**: repo público `dmzkitchensupport/lita-support-app`, GitHub Pages
(branch `main`, raíz) — `https://dmzkitchensupport.github.io/lita-support-app/`.
Confirmado con `curl` real: `index.html`/`manifest.json`/`sw.js`/`vendor/supabase.js`/
`icons/icon-192.png` sirven HTTP 200.

**Prueba real contra VK** (`scripts/verificar-sso.js` + `.github/workflows/
verificar-sso.yml` en `vitality-control`, corrido vía `workflow_dispatch`, run
`36019543183`, cuenta qa-bot real de ese repo — `LOGIN_EMAIL`/`LOGIN_PASSWORD`):
Puppeteer real entró a esta página, metió correo+contraseña de la cuenta qa-bot de VK,
y el log del job (evidencia objetiva, no resumen propio) confirma:
```
PASS: login único resolvió correctamente -> vitality-control.github.io/portal.html?ssoEmail=*** -- #login-email prellenado OK, 0 pageerrors.
```
(el correo real queda enmascarado `***` en el log porque GitHub Actions enmascara
automáticamente cualquier valor que coincida con un secret registrado — el script en sí
sí lo comparó contra el valor real antes de imprimir PASS).

**Prueba real contra CDJ** (mismo script/workflow en `cdj-support`, run `36019558440`,
cuenta qa-bot real de ese repo):
```
PASS: login único resolvió correctamente -> cdjsupport.github.io/portal.html?ssoEmail=*** -- #login-email prellenado OK, 0 pageerrors.
```

**No regresión del login normal**: `agente-qa.yml` (login real + apertura/cierre de
turno + 44-45 módulos, SIN `ssoEmail`) corrió automáticamente en el push que agregó el
prellenado, en ambos repos, y quedó en verde (`success`) — el flujo de login normal de
cada portal sigue exactamente igual cuando el parámetro no viene.

**Ninguna credencial de cliente real se usó** — ambas pruebas corrieron con las cuentas
qa-bot ya existentes como GitHub Secrets en cada repo, mismas que usa `agente-qa.yml`/
`smoke-login.yml` desde hace semanas.

**Bloqueadores**:
- Ninguno técnico. Pendiente de Mario: decidir si esta URL (o un dominio propio) es la
  que se envuelve con Bubblewrap/PWABuilder para las tiendas — este repo solo resuelve
  el bloqueador de "una sola app para descargar", no genera el paquete de la tienda.
