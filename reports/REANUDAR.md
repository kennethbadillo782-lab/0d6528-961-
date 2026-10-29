# Retomar después del reinicio de Windows

El usuario autorizó preparar y probar la aplicación real, instalar las herramientas necesarias y trabajar con datos ficticios. Autorizó los avisos administrativos de Docker y WSL. No se autorizó ningún gasto ni modificar Supabase de producción. Todavía no tiene las cuentas GitHub/Codemagic necesarias para compilar en la nube.

Carpeta de trabajo actual: `C:\Users\KeNnoTh\Documents\Codex\2026-10-29\lee\outputs\MiCatalogo`.

1. Verificar `wsl --version` y que Docker Desktop haya completado su primer inicio en contenedores Linux. Comprobar `docker info`, sin imprimir credenciales.
2. Ejecutar `./scripts/Start-Backend.ps1`. El script usa la CLI portable fijada en `.tools/`, aplica configuración local con registro cerrado y comprueba red limitada a loopback. No conecta a un proyecto remoto.
3. Ejecutar `./scripts/Test-Live.ps1`. El test está preparado, **aún no fue ejecutado**. Validará el handler contra Auth, PostgREST y Storage locales reales. Corregir cualquier fallo y repetir. No confundirlo con las pruebas anteriores de handler con DB simulada.
4. Revisar disponibilidad de `Deno.resolveDns`, imágenes y cabeceras IP en el runtime. No debilitar SSRF para hacer pasar las pruebas.
5. Para iOS, crear/conectar repositorio privado y cuenta Codemagic; ejecutar `ios-simulator`. Aún no hay `.app` ni `.ipa`. El workflow debe compilar de verdad, ejecutar XCTest y corregirse según sus diagnósticos.
6. Solo después de la primera compilación, implementar y probar la fase de autenticación/sincronización de `AGENTS.md`. El Swift actual es exclusivamente local. No afirmar que basta poner la URL de Supabase.
7. Appetize requiere cuenta del usuario y el ZIP de la `.app` de simulador generada por Xcode. El archivo `MiCatalogo-preparado.zip` es **código fuente**, no es el binario para Appetize.

La base portable de regresión es distinta del stack Docker: PostgreSQL 16.15 en loopback, contraseña local dentro de `.local/` y cierre al terminar. Supabase CLI 2.122.0 requiere 17 para su stack; falta probar ese runtime completo.

Los diagnósticos no contienen secretos reales. `.tools/`, `.venv/` y `.local/` se excluyen del ZIP y de Git. Usar `scripts/package-source.py` para regenerar la entrega una vez actualizadas las evidencias.
