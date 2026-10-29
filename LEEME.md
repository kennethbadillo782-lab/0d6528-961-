# Mi Catálogo de Moda — paquete completo

> Preparación actualizada para Windows y pruebas nativas: empieza por `EMPEZAR-AQUI.md`. Docker y WSL se instalaron; Windows requiere reinicio. Los scripts y workflows están preparados, pero no hay una compilación iOS, sesión Appetize ni sincronización nativa verificadas. Resultados de pruebas en `reports/INFORME.md`.

| Carpeta | Qué es | Estado |
|---|---|---|
| `ios/` | App de iPhone en SwiftUI + SwiftData (10 pantallas + Cuenta) | Hecha, guarda en el iPhone. Falta conectarla a la nube |
| `web-preview/` | Vista previa HTML para explorar la interfaz | Hecha |
| `backend/supabase/migrations/` | Base de datos: tablas, seguridad por usuario, fotos | Hecha y probada |
| `backend/supabase/functions/catalog-api/` | API que usa ChatGPT para guardar productos | Hecha, falta desplegar |
| `backend/gpt/` | Esquema para el GPT personalizado e instrucciones | Hecho |
| `AGENTS.md` | Encargo detallado para Codex (o Claude Code): desplegar, pasar la app al iPhone y conectarla | Listo |
| `SEGURIDAD.md` | Qué se atacó, qué se encontró y cómo se corrigió | Hecho |
| `docs/` | Tu especificación original y el diseño de referencia | — |

## Lo que tienes que hacer tú (≈15 minutos)

Son cosas que requieren tus cuentas, así que nadie más puede hacerlas por ti.

1. **Crear el proyecto en Supabase**
   Entra a supabase.com, crea una cuenta y un proyecto nuevo (región: East US). Guarda la contraseña de la base de datos.
2. **Crear tu usuario**
   En Supabase › Authentication › Users › *Add user*, crea tu usuario con tu correo. Copia su **User UID**. Será la única cuenta permitida: la base de datos rechaza cualquier registro más.
3. **Pasarle a Codex** (dile: "lee AGENTS.md y SEGURIDAD.md y empieza por la fase 0")
   - El "Project ref" (aparece en la URL del proyecto: `supabase.com/dashboard/project/ESTO`).
   - Tu User UID.
   - Que inicie sesión en la CLI con `supabase login` (te abrirá el navegador para autorizar).
4. **Crear tus GPTs en ChatGPT** (necesita ChatGPT Plus o superior). Codex te dará la URL de la API y **dos claves**: una de "guardar" y otra de "consultar".
   - **GPT "Mi Catálogo — Guardar"**:
     - ChatGPT › Explorar GPTs › **Crear** › *Configurar*.
     - Instrucciones: el bloque de `backend/gpt/instrucciones-guardar.md`.
     - Activa **Búsqueda en la web**.
     - *Crear nueva acción* › Autenticación: **Clave de API**, tipo **Personalizada**, encabezado `X-API-Key`, y pega la clave de **guardar**.
     - Esquema: `backend/gpt/openapi-guardar.yaml` (cambia `TU-PROYECTO` por tu project ref).
   - **GPT "Mi Catálogo — Consultar"** (opcional, para preguntar "¿qué carteras tengo?"):
     - Igual que el anterior, pero con `instrucciones-consultar.md`, `openapi-consultar.yaml` y la clave de **consultar**.
     - **Desactiva** Búsqueda en la web, imágenes y Code Interpreter.
   - Guarda ambos como **Solo yo**.
   - Por qué dos: el que lee no puede enviar nada fuera y el que busca en internet no puede leer tu catálogo. Una página trampa no tiene por dónde robarte nada.
5. **Probar**: escríbele "Busca 3 carteras crossbody negras y guárdalas en Carteras".

## Seguridad, en corto

- Cada fila de la base de datos pertenece a tu usuario y nadie más puede leerla (Row Level Security probado).
- ChatGPT entra con una clave propia: en el servidor solo se guarda su huella, caduca al año y se puede revocar al instante.
- Esa clave **no puede borrar** productos ni cambiar los enlaces de los que ya tienes guardados.
- Desde la app puedes **pausar el acceso de ChatGPT** con un interruptor, ver su historial y **deshacer** cualquier cambio (se guardan las 30 versiones anteriores de cada producto).
- Límites por minuto y por día, bloqueo de IPs que prueban claves, validación de todo lo que entra, fotos comprobadas por contenido y sin descargas hacia direcciones internas.
- Nadie más puede crearse una cuenta, aunque el registro quede abierto por error.
- Todo esto se atacó de verdad, la segunda vez con un auditor independiente que verificó cada corrección (ver `SEGURIDAD.md`): 137 ataques a la base de datos, 154 a la API y XSS a la vista previa, en 4 rondas. Se encontraron y corrigieron más de 40 fallos; hoy todos los ataques fallan.
- ChatGPT usa dos GPTs con claves separadas: uno que **solo guarda** (busca en internet pero no puede leer tu catálogo) y otro que **solo consulta** (lee pero no tiene internet). Así una página trampa no puede robarte datos.
- Activa la verificación en dos pasos en tu cuenta de Supabase y en tu Apple ID: son la llave maestra.
