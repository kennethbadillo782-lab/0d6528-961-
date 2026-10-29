#!/usr/bin/env bash
# Las claves ahora se crean dentro de la base de datos (se guarda solo su huella).
# Ejecuta esta consulta en Supabase › SQL Editor cambiando el UID por el tuyo.
# Devuelve la clave UNA sola vez: cópiala directo a ChatGPT y no la guardes en archivos.
cat <<'SQL'
-- RECOMENDADO: dos GPTs, dos claves (ver LEEME.md paso 4). Válidas 180 días.
-- 1) GPT "Guardar" (busca en internet, NO puede leer tu catálogo):
select public.create_api_key('ChatGPT guardar', '{create}', 180, 'TU-USER-UID');
-- 2) GPT "Consultar" (lee tu catálogo, SIN internet ni herramientas en el GPT):
select public.create_api_key('ChatGPT consultar', '{read}', 180, 'TU-USER-UID');

-- Alternativa: un solo GPT que lee y guarda (fotos limitadas a sitios conocidos):
-- select public.create_api_key('ChatGPT', '{read,create}', 180, 'TU-USER-UID');

-- Solo para scripts/test-api.sh (revócala al terminar):
-- select public.create_api_key('Pruebas', '{read,write}', 1, 'TU-USER-UID');

-- Revocar una clave (por su prefijo, p. ej. mc_1a2b):
-- update public.api_keys set revoked_at = now() where key_prefix = 'mc_1a2b';

-- Pausar todo el acceso de ChatGPT al instante:
-- update public.api_settings set enabled = false where owner_id = 'TU-USER-UID';
SQL
