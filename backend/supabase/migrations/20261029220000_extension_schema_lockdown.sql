-- En Supabase nuevo, pg_trgm puede instalarse inicialmente en public.
-- El stub antiguo lo preinstalaba en extensions y ocultaba la diferencia.
-- Mantener las funciones auxiliares fuera del esquema expuesto por PostgREST.
-- ALTER EXTENSION conserva OIDs/dependencias de los índices existentes.
create schema if not exists extensions;
do $$
declare
  extension_name text;
begin
  foreach extension_name in array array['pg_trgm', 'pgcrypto'] loop
    if exists (
      select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
       where e.extname = extension_name and n.nspname = 'public'
    ) then
      execute format('alter extension %I set schema extensions', extension_name);
    end if;
  end loop;
end $$;
