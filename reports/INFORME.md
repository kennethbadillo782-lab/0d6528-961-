# Informe de preparación y verificación — 29/10/2026

## Resultado y límites

El backend Supabase completo de pruebas funciona en Docker local, limitado a `127.0.0.1`. Pasaron 48 comprobaciones HTTP, 137 ataques SQL sobre el stack real y la ejecución programada de limpieza. **El criterio final de éxito del usuario todavía no se ha alcanzado**: no hay `.app`, `.ipa`, sesión Appetize ni comunicación de la app nativa con Supabase. GitHub está conectado y la primera compilación macOS está en ejecución mediante Actions; sigue pendiente la implementación de autenticación/sincronización nativas. No se ejecutaron operaciones contra producción ni servicios con coste.

## Evidencia ejecutada

| Comprobación | Resultado | Evidencia | Alcance |
|---|---|---|---|
| Utilidades TypeScript | 15/15 | `utilities.log`, `node-tests.json` | Node 24.22.1 |
| Sal de IP | 2/2 | `ip-salt-derived.log`, `ip-salt-custom.log` | Handler real con DB simulada |
| Flujo de API | 27/27 | `api-flow-mocked-db.log` | Handler real, DB/red/DNS simulados |
| Ataques de API | 154/154 | `api-security-mocked-db.log` | Handler real, DB/red/DNS simulados |
| Migraciones y ataque SQL | 137/137 | `database.log`, `database.json` | PostgreSQL 16.15 real, Auth/Storage de prueba |
| Concurrencia SQL | 20/60 aceptadas, esperado 20 | `database.json` | 60 conexiones reales |
| Migración desde versión anterior | pasa | `database.json` | Se verifica caducidad de una clave antigua |
| Limpieza/retención | pasa | `database.json`: `cleanupRetention` | Ejecutada en PostgreSQL real; conserva recientes y borra antiguos |
| XSS web | 0 XSS, 0 URLs peligrosas, 0 errores JS | `web-xss.log` | Chromium; 120 pasos + 60 tras importación maliciosa; 20 acciones distintas |
| Esquemas y configuración | pasan | `config-checks.log` | YAML/TOML/plist/XML estáticos |
| Scripts | sintaxis válida; ejecución local verificada | ver comandos y logs | PowerShell, Python y Node ejecutados; Bash de iOS solo validado estáticamente |
| Comando único Windows | `Test-All.ps1 -Live` | `test-all-console.log` | Suite independiente más pruebas HTTP y del lanzador; iOS y XSS tienen comandos propios |
| Docker/WSL | instalados y funcionando tras reinicio | `windows-runtime.json` | Diez contenedores del stack local |
| Puertos publicados | cuatro puertos exclusivamente en 127.0.0.1 | `port-bindings.json` | API, PostgreSQL, Studio y correo local |
| Lanzador de puertos | 5/5 | `docker-loopback-tests.json` | Prueba real, incluidos stdin binario y comillas |
| Supabase HTTP real | 48/48 | `live-tests.json`, `live-console.log` | Auth, Edge Function, PostgREST y Storage reales |
| SQL sobre Supabase real | 137/137 | `stack-sql.json`, `stack-sql.log` | PostgreSQL 17.11; fixtures revertidos con ROLLBACK |
| Cron real | trabajo diario activo y ejecución comprobada | `runtime-state.json` | Job efímero de prueba ejecutó api_cleanup y se eliminó |
| Compilación / XCTest / UI iOS | no ejecutados | no hay artefacto binario | GitHub Actions macos-26 en ejecución |

No sumar pruebas SQL con los tests de API para presentarlas como validación de un servicio desplegado. Los ataques con otra identidad son fixtures de regresión en DB descartables; no se añadió soporte multiusuario a la aplicación.

## Errores encontrados y correcciones

| ID | Evidencia y causa | Corrección | Verificación |
|---|---|---|---|
| T01 | Dos checks en `run.mjs` terminaban en `|| true`; nunca podían fallar. El doble no calculaba `search_text`. | Aserción exacta de resultado y código HTTP, y columna de búsqueda equivalente en el doble. | Las 27 pruebas pasan con las aserciones activas; búsqueda encuentra exactamente el producto creado. |
| T02 | Descripciones YAML con comas sin comillas creaban propiedades nulas accidentales: 7 en consultar, 6 en guardar, 7 en esquema general. El nuevo validador falló con `campo nulo accidental`. | Se reconstruyeron textos y se serializó YAML válido sin esos campos. | `check-configs.py` pasa en los tres archivos; 4, 2 y 11 operaciones respectivamente. Validación estática, pendiente importar en el editor GPT. |
| T03 | El esquema Guardar anunciaba 409 aunque el modo sin lectura siempre responde 202. | Se corrigió la descripción para reflejar la respuesta opaca de la API. | Validación del esquema 202 y ataques de simetría originales pasan. |
| T04 | `config.toml` original era solo un fragmento para la función. | Configuración local completa, registro cerrado, puertos y límites explícitos. | La CLI lo parsea. Falta arrancar el stack. |
| T05 | CLI 2.122.0 devolvió `Invalid db.major_version: 16`. | Stack local configurado para 17; SQL independiente conservado en 16. | PostgreSQL 17.11 pasó los 137 ataques SQL y las pruebas HTTP reales. |
| T06 | `.xcodeproj` original no incluía target de pruebas, aunque sí había archivos XCTest. | Workflows regeneran desde `project.yml`, que incluye ese target y esquema compartido. | YAML y scripts válidos; generación y compilación pendientes en Mac. |
| T07 | `pg_ctl` en Windows dejaba heredados handles de pipe y el runner esperaba indefinidamente pese a tener el servidor listo. | Redirección a archivo para control de PostgreSQL, timeouts y cierre del cluster. | Se completó toda la regresión SQL y el servidor se detuvo. |
| T08 | Playwright estaba instalado sin navegador descargado. | Se descargó headless Chromium en el workspace y se admitió ruta de ejecutable por entorno. | Recorrido XSS terminó con código 0. |
| T09 | Login HTTP 422 `email_provider_disabled`; Docker confirmó proveedor email desactivado aunque el registro global también estaba cerrado. | Activar solo el proveedor email y conservar registro global desactivado y límite SQL de un usuario. | Login/refresh funcionan y un intento de registro válido recibe `signup_disabled`. Evidencia previa: `live-failure-02.json`. |
| T10 | Docker publicaba en `0.0.0.0` y `::`, ignorando la opción de dirección de la red; una prueba mínima reprodujo el problema. | Lanzador local que publica explícitamente en 127.0.0.1 solo los contenedores del proyecto; control posterior detiene todo si no se cumple. | API, DB, Studio y correo confirmados en loopback; cinco pruebas reales del lanzador pasan. |
| T11 | El stack real falló tres pruebas de privilegios: `pg_trgm` en public y 31 funciones auxiliares accesibles. El stub preinstalaba la extensión en extensions y ocultaba la diferencia. | Quinta migración mueve pg_trgm/pgcrypto desde public a extensions cuando corresponde; el stub deja de anticipar la instalación de pg_trgm. | 137/137 ataques pasan tanto en PostgreSQL 16 como en el stack real 17. Búsqueda HTTP sigue funcionando. Evidencia previa: `stack-sql-failure-01.log`. |
| T12 | La prueba de foto de test-api.sh usaba Wikimedia, fuera de la lista por defecto de una clave con lectura. | Fixture PNG de 593 bytes en cdn.shopify.com, ya permitido, sin relajar la lista. | Descarga real y almacenamiento confirmados por la API. |

No se modificaron la apariencia ni la implementación Swift. No se afirma que sus errores potenciales estén corregidos sin compilarla. Las operaciones que usan `try? context.save()` merecen comprobar fallos de almacenamiento en el dispositivo; el análisis estático no demuestra su comportamiento ante disco lleno.

## Las 18 correcciones iniciales de seguridad

Se conserva el informe anterior como antecedente. Esta es la evidencia nueva; “pasa” siempre se limita al entorno indicado.

| # | Corrección | Evidencia nueva / pendiente |
|---|---|---|
| 1 | IPv6 mapeada y SSRF | Utilidades y ataques API pasan; resolución DNS de prueba |
| 2 | Nombres internos y puertos | Ataques API pasan |
| 3 | DNS falla cerrado | Casos adversos con dobles pasan; descarga permitida con DNS funciona en Deno local real |
| 4 | XSS en importación web | Recorrido Chromium e importación maliciosa pasan |
| 5 | IP/fuerza bruta | 154 ataques y contadores SQL pasan; gateway local neutraliza la IP reenviada por el cliente. Proxy remoto pendiente |
| 6 | Registro cerrado | SQL real y Auth HTTP rechazan cuentas extra; existe una sola cuenta ficticia |
| 7 | Revocación definitiva | SQL real impide reactivar; siguiente petición HTTP tras revocar devuelve 401 |
| 8 | Cuerpo limitado por streaming | Ataques de cuerpo gigante/infinito pasan |
| 9 | Plazo de descarga | Stream lento simulado se corta a unos 10 segundos |
| 10 | Estado y comodines | Filtros maliciosos de API pasan |
| 11 | Seguridad de red iOS | Revisada en código; XCTest, DNS/redirecciones y dispositivo pendientes |
| 12 | Unicode/control | Utilidades y ataques API pasan |
| 13 | Credenciales embebidas en URL | Validación API pasa |
| 14 | Errores sin detalles internos | Ataques API pasan |
| 15 | Privilegios anónimos e historial | 137 ataques sobre el stack real pasan tras corregir ubicación de pg_trgm |
| 16 | SVG en logos | SQL confirma MIME no permitido; Storage HTTP pendiente |
| 17 | Sal de IPs | Dos tests del handler verifican sal configurada y fallback ligado al secreto; secreto/proxy del despliegue pendientes |
| 18 | Limpieza de historial | Retención verificada; trabajo diario de cron activo y ejecución real programada comprobada |

También pasan los ataques adicionales de mínimo privilegio, presupuestos, separación de permisos, simetría de respuestas, concurrencia e historial incluidos en la entrega original. Esto no elimina los riesgos residuales de DNS rebinding descritos en `SEGURIDAD.md` ni demuestra protección absoluta contra prompt injection.

## Pendiente para satisfacer el objetivo completo

1. Repositorio privado creado en kennethbadillo782-lab/MiCatalogo. Verificar compilación manual Actions 40960250796; acceso a Appetize pendiente de inicio de sesión.
2. Compilar realmente; corregir errores de Xcode y ejecutar XCTest.
3. Abrir el ZIP nativo en Appetize y ejecutar la matriz de UI.
4. Para Appetize y la futura sincronización, autorizar un Supabase de pruebas accesible por HTTPS. El stack local ya está probado; el localhost del simulador externo no es este PC.
5. Implementar login y sincronización nativos conforme a `AGENTS.md`, después de la primera compilación; probar offline, conflictos, fotos y borrados. Actualmente no existen en la app.
6. Repetir auditoría de las 18 correcciones en el entorno real, verificar Security Advisor y cron.
7. Configurar certificados/UDID/perfil Apple para la IPA y probar en iPhone físico.

La guía `EMPEZAR-AQUI.md` explica los comandos, límites y fuentes oficiales. Ningún secreto real se incluye en el ZIP, en el código ni en los informes.
