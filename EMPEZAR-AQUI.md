# MiCatalogo: preparación para pruebas nativas

Estado al 29 de octubre de 2026: **todavía no existe una compilación iOS ni una sesión Appetize**. El código nativo sigue guardando localmente. La integración de autenticación y sincronización con Supabase no está implementada.

El backend completo de pruebas ya funciona localmente en Docker. Se prepararon herramientas, pruebas y workflows de compilación. No se modificó ningún Supabase remoto ni se creó ningún recurso de pago. El informe detallado está en `reports/INFORME.md`.

## Lo que ya se ejecutó en este PC

- Node 24.22.1: 15 pruebas de utilidades, 27 de flujo y 154 ataques de API; todas pasan. La API ejecuta su código real, con Supabase, DNS y descargas sustituidos por dobles de prueba.
- Dos pruebas adicionales verifican que el handler usa la sal de IP configurada o la derivada del secreto del servicio. Ambas pasan.
- PostgreSQL 16.15 independiente: cinco migraciones, 137 ataques, carrera de 60 conexiones con exactamente 20 aceptadas y actualización desde la versión anterior; todas pasan. Auth y Storage son esquemas de prueba en esta suite.
- Supabase completo con PostgreSQL 17.11: 48 comprobaciones HTTP sobre Auth, API, PostgREST y Storage, y los 137 ataques SQL originales adaptados a las columnas reales de Auth y ejecutados dentro de una transacción revertida; todos pasan.
- Se verificaron la retención de registros, el trabajo diario de `api_cleanup()` y una ejecución real programada de limpieza.
- Cinco comprobaciones del lanzador Docker verifican rechazo de puertos abiertos, publicación en loopback y transmisión exacta de entrada binaria y argumentos.
- Chromium: recorrido de 120 interacciones más 60 tras importar una copia maliciosa; cero XSS, enlaces peligrosos o errores JavaScript. Esta comprobación corresponde solo a la vista previa web.
- Validación de YAML, TOML, plist, XML y sintaxis de scripts. No equivale a ejecutar los servicios ni a compilar Swift.

Los resultados reproducibles están en `reports/`. No se certifica seguridad en producción ni funcionamiento de la app nativa.

## 1. Repetir las pruebas en Windows

En PowerShell 7, desde esta carpeta, con Node 24 y Python 3.11 o posterior:

```powershell
./scripts/Install-Tools.ps1
./scripts/Install-Postgres.ps1
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r scripts/requirements-checks.txt
./scripts/Test-All.ps1
```

Los instaladores descargan versiones fijadas y verifican SHA256. PostgreSQL es portable, no instala un servicio de Windows. Su base de regresión solo escucha en `127.0.0.1:55439`, usa contraseña aleatoria y se detiene tras las pruebas. Los archivos locales y contraseñas están en `.local/`, excluidos de Git y del ZIP de entrega. Las bases temporales de ataque y actualización se eliminan tras la ejecución. Los usuarios adicionales pertenecen exclusivamente a esas pruebas aisladas.

En este PC las herramientas ya están en `.tools/`; al extraer el ZIP en otro lugar, los dos instaladores las descargan de nuevo. No se incluyen los binarios de terceros en la entrega comprimida.

Solo pruebas de Node, sin instalar nada adicional:

```powershell
node scripts/test-all.mjs
```

## 2. Iniciar Supabase completo

Docker Desktop 4.97.0 y WSL ya están instalados; el usuario reinició Windows y el backend está funcionando. API: `http://127.0.0.1:54321`; panel administrativo de Supabase: `http://127.0.0.1:54323`. Ese panel no es la aplicación iPhone.

Para volver a arrancarlo tras apagar el PC, abre Docker Desktop en modo Linux. En otro PC: instala primero Docker Desktop y WSL2. `scripts/Enable-WSL.ps1` documenta ese paso administrativo; en Windows PowerShell con scripts restringidos se puede lanzar localmente mediante `powershell -ExecutionPolicy RemoteSigned -File ./scripts/Enable-WSL.ps1`, desde una consola de administrador. Ese parámetro solo afecta al proceso y no cambia la política del sistema.

Después:

```powershell
./scripts/Start-Backend.ps1
./scripts/Test-All.ps1 -Live
# Al terminar, conserva los datos locales:
./scripts/Stop-Backend.ps1
```

La red Docker tiene una dirección de publicación por defecto local, pero este Docker Desktop la ignoró. Por eso el arranque compila un lanzador pequeño desde `scripts/docker-loopback.cs`: únicamente añade `127.0.0.1` a los puertos de contenedores de `micatalogo-test`, sin cambiar Docker globalmente. `Start-Backend.ps1` inspecciona los puertos y detiene los servicios si alguno queda abierto en otra dirección. Los resultados están en `reports/port-bindings.json`.

Las credenciales de la CLI se capturan en memoria y no se imprimen en los diagnósticos. Las 48 pruebas HTTP ya se ejecutaron: cuenta ficticia única, login, renovación, registro cerrado, RLS, permisos separados, caducidad/revocación, pausa, duplicados simultáneos, DNS/imagen real y Storage privado. No se abre el registro público: `auth.enable_signup=false` lo cierra globalmente; `auth.email.enable_signup=true` mantiene activo el proveedor de login y la base de datos limita el catálogo a un usuario.

La CLI 2.122.0 rechazó `db.major_version=16`; el stack usa PostgreSQL 17.11, ya verificado con 137 ataques SQL. También se conserva la suite independiente en PostgreSQL 16.15. La quinta migración corrige una diferencia que el stub original ocultaba: `pg_trgm` se instalaba en `public` en un Supabase nuevo; ahora se mueve a `extensions` sin romper los índices.

Los contenedores siguen activos al cerrar la consola mientras Docker y el PC estén funcionando. No se ha instalado un servidor público permanente ni se depende de una ventana de terminal. Para funcionar con el PC apagado hace falta un proyecto de pruebas alojado. El entorno local usa HTTP en loopback; el futuro backend accesible desde Appetize debe usar HTTPS y requiere autorización separada.

## 3. Compilar la app nativa desde Windows

GitHub ya está conectado como `kennethbadillo782-lab`. Repositorio privado: https://github.com/kennethbadillo782-lab/MiCatalogo. No hace falta crear otra cuenta ni usar Codemagic para la compilación de simulador.

El workflow manual `.github/workflows/ios-simulator.yml` usa un runner estándar `macos-26`, limita la ejecución a 20 minutos y conserva artefactos un día. La cuenta tiene cuota incluida disponible y presupuesto de sobreconsumo de Actions en cero, bloqueado; no se ha aumentado ningún presupuesto. Debe ejecutarse y corregirse según sus diagnósticos antes de afirmar que existe una app compilada.

1. Abre Actions y ejecuta manualmente **iOS Simulator**.
2. Espera a que terminen compilación y XCTest.
3. Descarga el artefacto `MiCatalogo-simulator`, que contiene el ZIP de la app y los diagnósticos.

La configuración usa el Xcode disponible más reciente del proveedor. El proyecto declara iOS 17+ y Swift 5; el `.xcodeproj` original usa grupos sincronizados de Xcode 16+. El workflow regenera el proyecto con XcodeGen para incorporar las pruebas que faltaban en el proyecto original. No hay CocoaPods ni dependencias Swift externas en la versión local.

Una máquina Mac con Xcode compatible también puede ejecutar:

```bash
brew install xcodegen
bash scripts/build-simulator.sh
bash scripts/test-ios.sh
```

## 4. Abrir en Appetize

1. Crea tu cuenta Appetize y revisa cuota, acceso y privacidad en el panel.
2. Sube `MiCatalogo-simulator.zip` desde la compilación exitosa. Contiene una `.app` de simulador; una `.ipa` de dispositivo no sirve.
3. Configura el acceso desde tu panel antes de incorporar datos personales. No asumas que poseer un enlace garantiza acceso privado.
4. Abre la sesión y ejecuta la matriz de `reports/PRUEBAS-NATIVAS.md` con datos ficticios.
5. Para actualizar, sube el nuevo ZIP en esa misma app. Opcionalmente configura los secretos `APPETIZE_API_TOKEN` y `APPETIZE_APP_PUBLIC_KEY` en tu CI y ejecuta `python3 scripts/update-appetize.py build/MiCatalogo-simulator.zip`. El script solo actualiza una app existente y no imprime credenciales.

**Primera compilación: solo catálogo local.** No se puede comprobar login ni sincronización nativa antes de implementarlos. La app no contiene un cliente Supabase, servicio de sesión ni `SyncService`. No se colocaron ajustes de servidor que aparenten activarlos.

Appetize ejecuta el simulador en infraestructura externa: su `localhost` no es tu PC Windows. Para conectar la futura sincronización necesita un backend de pruebas accesible por HTTPS, preferiblemente un proyecto Supabase separado de producción. No se ha abierto un túnel hacia el PC.

Fotos, portapapeles, archivos importados/exportados y persistencia entre sesiones deben comprobarse según las capacidades del dispositivo y plan de Appetize. No se garantiza acceso a tu galería real ni conservación de datos tras destruir una sesión. Reserva cámara real, permisos de red local, biometría, rendimiento, firma e instalación para el iPhone físico.

## 5. Conectar la nube después de compilar

El siguiente bloque de desarrollo, aún pendiente, es la fase 3 de `AGENTS.md`: cliente Supabase, login para la única cuenta, almacenamiento seguro de sesión, sincronización incremental, cambios offline, conflictos y borrados suaves, subida de fotos y controles de acceso de ChatGPT. Es trabajo de implementación y pruebas, no solo introducir una URL.

Antes de tocar un Supabase existente: identificar proyecto y entorno, pedir autorización explícita para ese proyecto, hacer y verificar una copia de esquema/datos y una copia separada de los objetos Storage. No basta el dump SQL para respaldar las fotos. Usar un proyecto de pruebas nuevo y datos ficticios primero. Ningún script de esta entrega despliega automáticamente a remoto ni ejecuta `db reset` contra producción.

Mantener las claves de servicio en Supabase/CI; la app solo recibe URL y clave pública cuando exista el cliente. Nunca enviar claves de servicio al iPhone. No pegar secretos en el chat. HTTPS y DNS/cabecera IP fiables deben verificarse en el despliegue real; no se han verificado aquí.

## 6. Instalar luego en el iPhone 17 Pro Max

El workflow **ios-device** está preparado para firma ad hoc. Antes de ejecutarlo: registrar un bundle id propio, configurar el mismo valor en `IOS_BUNDLE_ID` y `ios_signing.bundle_identifier`, fijar `APPLE_TEAM_ID`, registrar el UDID del iPhone y cargar certificado y perfil compatibles en el gestor de firma de Codemagic. No se generaron certificados sin tu cuenta.

Con una cuenta Apple Developer apta para distribución, se podrá exportar una IPA ad hoc para el dispositivo registrado. Como alternativa, cambiar la distribución a App Store y preparar TestFlight; publicar requiere autorización aparte. Una cuenta personal gratuita con instalación desde Xcode necesita acceso a una Mac y tiene restricciones que deben revisarse en ese momento. No garantiza que el workflow de distribución en la nube funcione con una cuenta gratuita.

Prueba primero en el dispositivo real: permisos, modo desarrollador cuando corresponda, importación desde Archivos, galería, enlaces, cambio de conexión, reinicio y datos persistentes.

## Fuentes oficiales consultadas

- [Supabase: desarrollo local y Docker](https://supabase.com/docs/guides/local-development).
- [Supabase: límites del runtime nativo en Windows](https://supabase.com/docs/guides/local-development/docker-and-native-runtimes).
- [Codemagic: vista previa y compilación para simulador](https://docs.codemagic.io/yaml-distributing/app-preview/).
- [Codemagic: firma de iOS](https://docs.codemagic.io/yaml-code-signing/signing-ios/).
- [Appetize: formato iOS y arquitectura recomendada](https://docs.appetize.io/platform/app-management/uploading-apps/ios).
- [Apple: distribución a dispositivos registrados](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).
