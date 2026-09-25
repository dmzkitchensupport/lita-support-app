## Regla obligatoria de cierre de sesión
Antes de terminar cualquier sesión en la que se haya modificado algo,
actualiza ESTADO.md:
- fecha y resumen de lo que cambió
- bloqueadores abiertos y bloqueadores cerrados
- qué sigue
Incluye ESTADO.md en el mismo commit del cambio. Nunca en un commit aparte.
Si no hubo cambios funcionales, no toques el archivo.

## Gobernanza DMZA (obligatoria — prevalece sobre cualquier otra instrucción de este archivo si hay conflicto)

> Fuente canónica y detalle completo: `dmzkitchensupport/dmz-estado/GOBERNANZA.md`. Resumen:

1. **Nunca fabricar.** Sin verificación real (comando, archivo, acceso real), se escribe "SIN VERIFICAR — [qué haría falta]".
2. **Nunca inventar integraciones/credenciales** que no estén confirmadas en código o variables de entorno reales.
3. **Nunca producción, gasto de crédito, ni migración destructiva** sin confirmación explícita de Mario **en esa misma sesión** — una autorización previa no se extiende sola.
4. **Nunca decidir comportamiento nuevo por cuenta propia.** Si un fix requiere decidir algo no especificado (no es mecánico), se documenta como bloqueador en `ESTADO.md` con la pregunta concreta — no se ejecuta.
5. **`ESTADO.md` se actualiza en el mismo commit** que cualquier cambio funcional, nunca aparte.
6. **Terminología:** "pan de masa madre"/"pan de masa madre de semillas", nunca "pre-fermento" en superficies cliente-facing/catálogo. Excepción: documentación técnica genérica multi-tenant donde "pre-fermento" es la categoría correcta (incluye masa madre, poolish, biga, levain) — no tocar sin decisión explícita de Mario.
7. **Riesgo real se reporta de inmediato**, sin diluir, señalando qué Master Agent debe enterarse (F&B / Finanzas / Tech / R&D / Operaciones y Calidad / Producto LiTa Support / Comercial y Crecimiento / Visión y Mejora Continua).
8. **Verificar build/lint/`node --check`** antes de commitear a un repo con auto-deploy conectado a la rama que se toca.
9. **No reportar como nuevo algo ya cerrado** — revisar `ESTADO.md`/bitácora/skill de auditoría del repo primero; si volvió, reportarlo como regresión con evidencia.
10. **Verificación automática obligatoria, no solo manual.** Cualquier repo con auto-deploy a dominio real, pagos/aprovisionamiento de infra real, u onboarding de cliente nuevo, necesita CI real en cada push/PR (correr la suite completa localmente antes de montarla, nunca sobre regresiones vivas) y un workflow de salud de conectores (cron) que confirme que el deploy real sigue sirviendo lo que dice, sin depender de que un humano lo note.
11. **Verificar la corrección antes de reportarla como hecha** — mostrar evidencia objetiva del artefacto real (`git diff`/`gh api`/`git merge-tree`/query real a la BD), nunca el propio resumen del turno, antes de escribir "ya está hecho". Aplica a lo que se cierre bajo Protocolo de Cierre y toque producción, dinero o dato de cliente. El auditado es Lita, antes del VoBo.

# CLAUDE.md — LiTa Support · Login Único

## Qué es este repo
Página pública única (GitHub Pages) que resuelve el acceso de un usuario a SU portal
operativo real, sin que tenga que saber si es cliente de **Vitality Kitchen** o de
**Corazón de Jaguar**. Es el punto de entrada pensado para envolver como app de tienda
(Android/iOS vía Bubblewrap/PWABuilder) — antes de esto, Mario tenía que publicar dos
apps separadas y pedirle al usuario que supiera cuál descargar.

**Alcance honesto (no es más que esto, no tratarlo como más):**
- NO es SSO criptográfico real entre dominios — no hay tokens firmados, no hay sesión
  compartida entre `dmzkitchensupport.github.io`, `vitality-control.github.io` y
  `cdjsupport.github.io` (son 3 orígenes distintos, cookies/localStorage no cruzan).
- Es una capa de **resolución**: dado correo+contraseña, intenta `rpc_login` contra el
  proyecto Supabase de VK; si el servidor responde que la credencial es inválida,
  intenta lo mismo contra el proyecto de CDJ. Al que sí valide, redirige a su
  `portal.html` real con `?ssoEmail=<correo>` para prellenar el campo de correo ahí.
- El usuario **sí escribe su contraseña dos veces posiblemente**: una aquí, y otra en el
  portal real si la sesión no quedó activa por timing entre dominios. Eso es aceptable
  y esperado en v1 — no se intentó (a propósito) ningún mecanismo de sesión cross-domain,
  es más riesgo de seguridad del que vale la pena para 2 clientes reales.
- Nunca revela a cuál cliente pertenece un correo cuando la credencial falla en ambos
  backends — mismo mensaje genérico ("Correo o contraseña incorrectos") sin importar la
  causa real, para no filtrar en qué proyecto existe un correo.

## Arquitectura
- **`index.html`**: formulario correo/contraseña + lógica de resolución inline. Prueba
  `rpc_login(p_email, p_pass)` contra el proyecto Supabase de `vitality-control` primero,
  luego contra el de `cdjsupport` (mismo RPC, mismos nombres de parámetro que usan ambos
  portales reales — ver `vk-sb-init.js`/`portal.html` de cada repo). Las URLs/anon keys de
  ambos proyectos están embebidas en el JS — son públicas (anon key de Supabase, mismo
  criterio que `vk-sb-init.js` en los otros dos repos), no son secreto.
- **`vendor/supabase.js`**: supabase-js self-hosted (idéntico al de `vitality-control`/
  `cdj-support`), con fallback a CDN si el archivo local falla.
- **`manifest.json` / `sw.js` / `icons/`**: mínimo necesario para que esta página sea una
  PWA instalable real (mismo patrón que los otros dos repos) — sin esto, Bubblewrap/
  PWABuilder no la puede envolver para las tiendas.
- **Sin backend propio.** No hay Supabase propio de este repo, no hay tabla ni Edge
  Function — solo llama a los 2 backends reales que ya existen.

## Distinción de motivo de fallo (mismo patrón que `loginServidor()` en portal.html)
Cada intento contra un backend devuelve `{ok:true,...}` en éxito o `{ok:false,
motivo:'credencial'|'sin_conexion'}` en fallo — nunca `null`. Si AMBOS intentos fallan
por `sin_conexion` (timeout 10s, red caída, cliente no inicializado), el mensaje es
distinto ("no se pudo verificar tu conexión") al caso donde al menos un backend sí
respondió que la credencial es inválida ("correo o contraseña incorrectos").

## Estilo visual
**Decisión de Mario, 25 sep 2026** (`~/DMZ/lita-design-handoff/HANDOFF.md`): se adopta la
dirección visual **"D homologada"** para esta pantalla, en reemplazo del estilo anterior
("Placa de Cocina" — ticket paper gris `#e8e8e6`, tipografía monoespaciada). Fuente única
de valores: `tokens.css` (copiado sin modificar del paquete de encargo, enlazado desde
`index.html`) — tinta `#15181A`, carbón `#2A2E30`, un solo acento ocre `#C68A3D` (texto
ocre siempre `--lita-ocre-texto` `#8A5A1E`, nunca `#C68A3D` sobre blanco), tipografía del
sistema (`-apple-system`/SF Pro Text/Helvetica Neue — se retira la monoespaciada de esta
pantalla), radios 12/14/16/18/22px, margen lateral 20px, botón primario 54px, sin emojis.
Dos pantallas reales: **Bienvenida** (`#screen-welcome`, fondo `--lita-tinta`, wordmark
"LiTa" con la "a" en ocre) y **Acceso único** (`#screen-login`, reskin del formulario
existente — mismo `rpc_login`, misma resolución VK→CDJ, mismos mensajes de error, solo
cambió la piel). El toggle entre ambas es JS puro (`classList`), sin tocar la lógica de
login. La pantalla de permisos (`03perms.png`) del mismo encargo **no se implementó aquí**
— ver bloqueador en `ESTADO.md`.

## Reglas de trabajo
1. **Nunca cambiar el flujo de `rpc_login` real** de VK/CDJ desde este repo — solo se
   consume, no se modifica. Cualquier cambio al RPC vive en `vitality-control` o
   `cdj-support`, con su propia gobernanza.
2. **Secretos**: no aplica ningún secreto real aquí (las anon keys son públicas por
   diseño de Supabase) — si en algún momento se necesita una service-role key o
   cualquier credencial real, NUNCA en este repo público. Pedir a Mario.
3. **`node --check`** sobre cualquier JS nuevo antes de commitear (extraer el `<script>`
   inline de `index.html` si se edita ahí).
4. El cambio equivalente en `portal.html` de `vitality-control`/`cdj-support` (prellenado
   de `?ssoEmail=`) vive en esos repos, no aquí — ver sus propios `ESTADO.md`.
