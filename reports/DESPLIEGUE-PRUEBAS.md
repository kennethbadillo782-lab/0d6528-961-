# Supabase remoto de pruebas

Proyecto autorizado por el usuario: `ddppztnamwmryhamezwy`, MiCatalogo-pruebas, organización MiCatalogo Pruebas, plan FREE. URL HTTPS: https://ddppztnamwmryhamezwy.supabase.co. Solo datos ficticios; nunca ejecutar estos tests contra proyectos distintos.

Antes de aplicar migraciones se verificaron cero tablas públicas, cero usuarios y cero objetos Storage. Copia de esquema inicial en `.local/remote-baseline/public-before.sql`, excluida de Git y del ZIP. Se aplicaron seis migraciones y se desplegó catalog-api. Registro público cerrado y contraseña mínima 12. RLS activo en las 13 tablas públicas. Claves solo en memoria o almacén de credenciales de la herramienta; ninguna clave de servicio en Swift.

Fallo remoto 1: permisos automáticos desactivados dejaban categorías sin SELECT para service_role. La sexta migración declara los permisos CRUD necesarios; conserva revocaciones por columna de api_keys, bloqueos de tablas internas y RLS. Evidencia: cloud-failure-01.json.

Fallo remoto 2: última entrada X-Forwarded-For no se comporta como el gateway local. Se configuró CLIENT_IP_HEADER=cf-connecting-ip. Se verificó igualdad de huellas ante X-Forwarded-For falsificado y rechazo HTTP 403 del proxy ante cf-connecting-ip falsificado. Evidencia anterior: cloud-failure-02.json. No se registran IPs en claro.

Suite HTTP remota: scripts/test-cloud.py captura claves desde la CLI en memoria y llama al test fijado exclusivamente a este proyecto. No incluye ataques SQL de carga ni pruebas contra producción. Resultados: reports/cloud-tests.json y cloud-console.log. La cuenta ficticia única es micatalogo-test@example.invalid; el test cambia solo su contraseña aleatoria, no envía correo. Limpia productos por borrado suave y revoca claves de pruebas.

Pendiente: integración de sesión/sincronización en la app Swift; pruebas API → iPhone; acceso ChatGPT; firma física. Appetize está autenticado pero su carga aún no se ha verificado. No presentar el backend como si la app ya estuviera conectada.

Resultado final: **49/49 pruebas HTTP remotas pasan**, incluidas las dos verificaciones del proxy. HTTPS, Auth, renovación/logout, registro cerrado, RLS, CRUD permitido, Storage privado, descarga con DNS, SSRF, pausa, scopes, caducidad, revocación y duplicados concurrentes. No equivale a probar comunicación desde Swift.
