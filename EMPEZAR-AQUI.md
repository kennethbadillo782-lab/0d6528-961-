# MiCatalogo: preparación para pruebas nativas

Estado al 29 de octubre de 2026: **todavía no existe una compilación iOS ni una sesión Appetize**. El código nativo sigue guardando localmente. La integración de autenticación y sincronización con Supabase no está implementada.

Se prepararon las herramientas, pruebas, configuración local y workflows de compilación. No se modificó ningún Supabase remoto ni se creó ningún recurso de pago. El informe detallado está en `reports/INFORME.md`.

## Lo que ya se ejecutó en este PC

- Node 24.22.1: 15 pruebas de utilidades, 27 de flujo y 154 ataques de API; todas pasan. La API ejecuta su código real, con Supabase, DNS y descargas sustituidos por dobles de prueba.
- PostgreSQL 16.15 real: cuatro migraciones, 137 ataques, carrera de 60 conexiones con exactamente 20 aceptadas y actualización desde la versión anterior; todas pasan. Auth y Storage son esquemas de prueba, no sus servicios HTTP.
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

Este PC no tiene Docker Desktop ni WSL instalado. El comando de estado de Supabase confirmó ese bloqueo. Para habilitar el stack Windows hace falta instalar Docker Desktop con WSL2, contenedores Linux y completar los pasos administrativos o reinicio que Windows pida. No se han cambiado esas características del sistema.

Después:

```powershell
./scripts/Start-Backend.ps1
./scripts/Test-All.ps1 -Live
# Al terminar, conserva los datos locales:
./scripts/Stop-Backend.ps1
```

La red Docker se crea limitada a loopback. API local: `http://127.0.0.1:54321`; Studio: `http://127.0.0.1:54323`. Las credenciales que devuelve la CLI se capturan en memoria y no se imprimen en los diagnósticos. El test HTTP prepara una sola cuenta ficticia con contraseña efímera, autentica, renueva sesión, prueba API/RLS/Storage y revoca su clave al finalizar. **Ese test HTTP todavía no se ha ejecutado**. No se abre el registro público.

La CLI 2.122.0 rechazó `db.major_version=16`; el stack se configuró para PostgreSQL 17, que sí acepta. La regresión SQL de esta entrega se ejecutó con PostgreSQL 16.15. Falta confirmar las migraciones en el stack 17 completo.

Los contenedores siguen activos al cerrar la consola mientras Docker y el PC estén funcionando. No se ha instalado arranque automático de Windows ni un servidor público permanente. Para funcionar con el PC apagado hace falta un proyecto de pruebas alojado.

## 3. Compilar la app nativa desde Windows

Hace falta crear una cuenta GitHub y un repositorio **privado**, y una cuenta Codemagic. El usuario confirmó que aún no tiene esas cuentas. No se creó ni publicó un repositorio en su nombre.

1. Sube el contenido de esta carpeta al repositorio privado, respetando `.gitignore`.
2. Conecta ese repositorio a Codemagic y selecciona `codemagic.yaml`.
3. Revisa la cuota/precio de la cuenta antes de iniciar una máquina macOS. No se autorizó ningún gasto.
4. Ejecuta manualmente el workflow **ios-simulator**.
5. Este genera el proyecto desde `ios/project.yml`, incluyendo el target XCTest, compila una app ARM64 de simulador y ejecuta las pruebas en un iPhone disponible. Intenta elegir iPhone 17 Pro Max; cualquier alternativa queda registrada.
6. Descarga `build/MiCatalogo-simulator.zip` y los resultados XCTest. Si la compilación falla, sus errores deben corregirse y el workflow debe repetirse antes de afirmar que la app funciona.

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
