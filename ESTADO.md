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

**Verificación real**: ver sección "Verificación real end-to-end" más abajo.

**Bloqueadores**:
- Ninguno técnico. Pendiente de Mario: decidir si esta URL (o un dominio propio) es la
  que se envuelve con Bubblewrap/PWABuilder para las tiendas — este repo solo resuelve
  el bloqueador de "una sola app para descargar", no genera el paquete de la tienda.
