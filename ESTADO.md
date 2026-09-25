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

## 2026-09-24 — empaquetado para tiendas (en curso)

**Hallazgo real antes de envolver nada**: `dmzkitchensupport.github.io` (el dominio raíz
que servía este repo) ya lo usa `dmzkitchensupport/dmzkitchensupport.github.io`, un
producto interno distinto ("Mystery Shopper Audit Platform") — Digital Asset Links de
Android (`assetlinks.json`) SIEMPRE se verifica contra la raíz del dominio, así que no se
puede envolver esta app sin invadir ese otro repo. Además la URL exponía literalmente
"dmzkitchensupport" — viola la regla de nunca mostrar DMZ en superficie cliente-facing.

**Corregido con dominio propio**: `app.litasupport.com` (subdominio de un dominio que
Mario ya posee y controla, mismo usado para correo vía Zoho). Agregado `CNAME` al repo.
**Bloqueador real, de Mario**: falta crear el registro DNS real —
`CNAME app.litasupport.com -> dmzkitchensupport.github.io` — en el panel de Zoho DNS de
litasupport.com. Sin este registro, `app.litasupport.com` no resuelve y el build de
Bubblewrap (que valida contra la URL real) va a fallar.

**Keystore real generado** (`lita-app-upload-key-2026`, RSA 2048, validez 10000 días),
respaldado en `~/Backups/lita-support/keystores/lita-support-app-upload.keystore`
(nunca en git), huella SHA-256 real extraída con `keytool` (Java instalado vía Homebrew
en esta sesión, no estaba disponible antes) y reflejada en `twa-manifest.json`/
`.well-known/assetlinks.json`. Secrets `ANDROID_KEYSTORE_BASE64`/
`ANDROID_KEYSTORE_PASSWORD`/`ANDROID_KEY_ALIAS` ya cargados en GitHub. Workflow
`build-android-twa.yml` copiado y adaptado del mismo patrón ya probado en
`vitality-control`/`cdj-support`.

## 2026-09-24 (tarde) — DNS resuelto + build Android real

**Nota de proceso**: esta sección la escribió una sesión paralela trabajando el mismo
repo al mismo tiempo (Mario corre varias ventanas de Claude Code a la vez) — reconciliado
aquí sin perder ninguna de las dos bitácoras.

**Bloqueador 🔴 de DNS: RESUELTO.** El DNS de litasupport.com NO está en el panel de Zoho
DNS sino en el del registrador (OpenSRS/Tucows, manage.opensrs.net — liga desde Consola
Zoho Mail > Dominios > litasupport.com). Ahí se creó CNAME app -> dmzkitchensupport.github.io.
Registros existentes sin cambios (A raíz 76.76.21.21 y www -> Vercel; mail -> Zoho).
Verificado: app.litasupport.com resuelve a las IPs de GitHub Pages; en Settings > Pages
quedó "DNS check successful" y se activó Enforce HTTPS.

**Hallazgo y corrección**: .well-known/assetlinks.json daba 404 porque Jekyll ignora
carpetas que empiezan con punto. Se agregó .nojekyll en la raíz (commit 78ee4f0);
verificado que https://app.litasupport.com/.well-known/assetlinks.json ya sirve el JSON.

**Build Android #2**: build-android-twa.yml corrido vía workflow_dispatch, run #2
(36059700304) en success (2m 23s), artefacto lita-support-android (1.54 MB). El run #1
falló antes de existir el DNS.

## 2026-09-25 — Android real, build #3 (sesión distinta, mismo resultado)

Corrido en paralelo a lo de arriba, sin saber todavía de ese trabajo — mismo resultado,
sin conflicto real: run `36083772268` en success, GitHub Release **`android-v3`** con
`app-release-signed.apk` (946KB) y `app-release-bundle.aab` (1.04MB) reales, firmados
con el keystore `lita-app-upload-key-2026`.

**Bloqueadores que quedan (consolidado de ambas sesiones)**:
- Google Play Console: sin confirmar si Mario ya la pagó — sin eso no hay dónde subir
  el `.aab` (el `.apk` sí se puede instalar directo/sideload ya mismo).
- iOS: sigue pendiente generar el proyecto Xcode vía PWABuilder — la URL real ya existe
  y funciona, así que esto ya se puede intentar. Requiere después la sesión/Apple ID de
  Mario en Xcode (firma, Team, Archive, subida a App Store Connect) — no se puede
  automatizar del todo sin su participación directa.
- Nombre legal exacto de la entidad del Apple Developer Organization — sin confirmar.
- `soporte@litasupport.com` — bandeja específica sin confirmar que exista en Zoho Mail.
- Warnings no bloqueantes del workflow: actions en Node 20 y setup-java@v4 deprecado.

## 2026-09-24 — Enlaces a aviso de privacidad y eliminación de cuenta

**Qué cambió**: el pie del ticket de `index.html` ahora enlaza a
`https://litasupport.com/privacidad` y `https://litasupport.com/eliminar-cuenta`
(bloqueantes de Google Play: política enlazada dentro de la app y ruta de
eliminación de cuenta). Solo marcado y CSS; el flujo de `rpc_login` no se tocó.
`node --check` del script inline en verde; captura headless a 1280 y 400 px sin
desborde.

**Depende de**: PR de `proyecto-lita-support` que publica esas dos rutas (antes 404).

**Bloqueadores abiertos**:
- Correo de privacidad sin buzón verificado en Zoho (las páginas llevan placeholder
  visible `[CORREO DE PRIVACIDAD]`); el canal que funciona hoy es el escrito al domicilio.
- La eliminación es un proceso manual; no hay RPC de borrado real ni botón dentro de la app.

## 2026-09-25 — Fase 1 del encargo de diseño "D homologada" (reskin visual, login único)

**Fuente**: `~/DMZ/lita-design-handoff/HANDOFF.md`, decisión de Mario 25 sep 2026. Fase 0
(mapeo) ya hecha en `vitality-control`/`cdj-support`; esta Fase 1 es solo este repo
(login único), cambio chico y aislado, no depende de las 7 decisiones de producto que
bloquean la Fase 2 de los portales (esas siguen sin tocar).

**Qué se construyó**:
1. **Pantalla de Bienvenida** (`#screen-welcome`, nueva) — fondo `--lita-tinta`, anillos
   concéntricos, ícono de marca (cuadrado carbón con 2 cuadros blancos + 1 punto ocre),
   wordmark "LiTa" (la "a" en ocre) + "SUPPORT" en tracking amplio, tarjeta blanca con el
   titular ("Todo lo que pasa en tu turno, **queda escrito**." — resaltado en
   `--lita-ocre-texto`, nunca ocre puro sobre blanco) y botón "Entrar a mi operación".
2. **Acceso único** (`#screen-login`, reskin del formulario existente) — header con
   flecha atrás + "PASO 1 DE 2" en ocre, título y subtítulo iguales a los que ya existían,
   campos con fondo `--lita-superficie-2`/radio `--lita-r-md`, botón "Entrar" de
   `--lita-boton` (54px). **La lógica NO se tocó**: mismo `rpc_login`, misma resolución
   VK→CDJ en el mismo orden, mismos mensajes de error genéricos — el único archivo con
   lógica (`<script>` inline) se dejó carácter por carácter igual, solo se agregó al
   final un listener nuevo que alterna `classList` entre las dos pantallas (no toca
   `probarLogin`/`CLIENTES`/el `submit` del formulario).
3. Los enlaces "Aviso de privacidad"/"Eliminar mi cuenta" se conservaron con las mismas
   URLs de la sección anterior (`https://litasupport.com/privacidad` /
   `.../eliminar-cuenta`, `target="_blank" rel="noopener"`) — verificadas contra el
   `index.html` real antes de tocar nada (se hizo `git pull` primero: el checkout local
   estaba 2 commits atrás de origin/main, que ya traía estos enlaces de un PR de una
   sesión paralela).
4. `tokens.css` del paquete de encargo se copió sin modificar a este repo y se enlaza
   desde `index.html` — es la única fuente de valores de color/tipografía/radios/medidas.
5. `CLAUDE.md` actualizado (sección "Estilo visual") con la decisión real y la cita de
   la fuente.

**🔴 Bloqueador — Pantalla de Permisos (`03perms.png`) NO SE CONSTRUYÓ**: este repo (login
único) no pide permisos de cámara/ubicación/micrófono hoy, ni tiene un punto natural
donde pedirlos — eso ocurre en el portal real de VK/CDJ, no aquí. Pregunta para Mario:
**¿la pantalla de permisos aplica en otro punto del flujo (ej. justo antes de redirigir
al portal real) o se retira del alcance de este repo?** No se implementó sin esa
respuesta (regla 4 de Gobernanza DMZA).

**Efecto colateral necesario, fuera de este repo pero documentado aquí**: el login único
ahora requiere un clic en "Entrar a mi operación" antes de que `#sso-email`/`#sso-btn`
sean interactuables por un usuario real — el script `scripts/verificar-sso.js` de
`vitality-control` y `cdj-support` (vive en esos repos porque ahí están los secrets
`LOGIN_EMAIL`/`LOGIN_PASSWORD` de las cuentas qa-bot) hacía `page.click('#sso-btn')`
directo tras `page.goto()`, lo que habría fallado con la pantalla de bienvenida encima
(el botón no tiene bounding box mientras su pantalla no esté activa). Se agregó un paso
mecánico de 4 líneas en ambos scripts (`if (welcomeCta) await welcomeCta.click();`,
gracioso si no existe) — no se tocó nada más de esos 2 repos, ni `portal.html`, ni
ninguna de las 7 decisiones bloqueadas de Fase 2.

**Verificación real**:
- `node --check` sobre el `<script>` inline extraído de `index.html`: verde.
- `node --check` sobre los 2 `verificar-sso.js` editados (en `vitality-control`/
  `cdj-support`): verde.
- Deploy real confirmado en `app.litasupport.com` (GitHub Pages build de este repo,
  commit `ba13aa7`) antes de correr las pruebas.
- `verificar-sso.yml` corrido vía `workflow_dispatch` contra la producción ya desplegada
  con la piel nueva:
  - VK, run `36199521600`: `PASS: login único resolvió correctamente ->
    vitality-control.github.io/portal.html?ssoEmail=*** -- #login-email prellenado OK,
    0 pageerrors.`
  - CDJ, run `36199523586`: `PASS: login único resolvió correctamente ->
    cdjsupport.github.io/portal.html?ssoEmail=*** -- #login-email prellenado OK,
    0 pageerrors.`
- Captura real de `app.litasupport.com` a 390×844 (Puppeteer + Chrome real, no mockup):
  0 `pageerror`, sin scroll horizontal en ninguna de las 2 pantallas, layout equivalente
  a `01welcome.png`/`02login.png` (anillos concéntricos, tarjeta blanca con CTA ocre,
  header con flecha+"PASO 1 DE 2", campos y botón anclados al fondo de la pantalla).

**Qué sigue**: esperar la respuesta de Mario sobre el bloqueador de Permisos; Fase 2
(portales VK/CDJ) sigue sin VoBo, no se toca.
