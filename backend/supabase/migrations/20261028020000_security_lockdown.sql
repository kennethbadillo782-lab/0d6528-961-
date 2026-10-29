-- =====================================================================
-- Cierre de seguridad (resultado de las pruebas de ataque)
--  1. Nadie más puede crear cuentas: solo se admite el número de usuarios
--     configurado (1 por defecto, tú). Aunque el registro público quede
--     activado por error en Supabase, la base de datos lo rechaza.
--  2. Una clave revocada no se puede "des-revocar" y la revocación es inmediata.
--  3. Defensa en profundidad: el rol anónimo no tiene permisos sobre ninguna
--     tabla ni función del esquema público.
--  4. Limpieza automática del historial viejo de la API.
-- =====================================================================

-- ---------- 1. Bloqueo de registros ----------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.app_config (
  id        boolean primary key default true check (id),
  max_users int not null default 1 check (max_users between 1 and 20)
);
insert into private.app_config (id) values (true) on conflict do nothing;
revoke all on private.app_config from public, anon, authenticated;

create or replace function private.limit_signups()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  allowed int;
  existing int;
begin
  perform pg_advisory_xact_lock(hashtext('mi-catalogo-signup'));
  select c.max_users into allowed from private.app_config c where c.id;
  select count(*) into existing from auth.users;
  if existing >= coalesce(allowed, 1) then
    raise exception 'Registro cerrado: este catálogo es privado' using errcode = '42501';
  end if;
  return new;
end $$;
revoke execute on function private.limit_signups() from public, anon, authenticated;

drop trigger if exists limit_signups on auth.users;
create trigger limit_signups before insert on auth.users
  for each row execute function private.limit_signups();

-- ---------- 2. Revocación definitiva ----------
create or replace function public.api_keys_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.revoked_at is not null then
    new.revoked_at := old.revoked_at;           -- no se puede reactivar
  elsif new.revoked_at is not null then
    new.revoked_at := now();                    -- ni programar una revocación futura
  end if;
  return new;
end $$;
drop trigger if exists api_keys_guard on public.api_keys;
create trigger api_keys_guard before update on public.api_keys
  for each row execute function public.api_keys_guard();

-- ---------- 3. Sin permisos para anónimos ----------
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon;

-- Las funciones de disparador no se llaman directamente.
revoke execute on function public.set_updated_at() from public, anon, authenticated;
revoke execute on function public.check_image_owner() from public, anon, authenticated;
revoke execute on function public.check_membership_owner() from public, anon, authenticated;
revoke execute on function public.keep_product_version() from public, anon, authenticated;
revoke execute on function public.seed_new_user() from public, anon, authenticated;
revoke execute on function public.seed_api_settings() from public, anon, authenticated;
revoke execute on function public.api_keys_guard() from public, anon, authenticated;

-- Tablas que solo escribe el servidor: la app solo puede leer lo suyo.
revoke insert, update, delete, truncate on public.api_audit_log from authenticated;
revoke insert, update, delete, truncate on public.product_versions from authenticated;
revoke all on public.api_usage from authenticated;
revoke all on public.api_auth_failures from authenticated;
revoke truncate, references, trigger on all tables in schema public from authenticated;

-- ---------- 4. Limpieza ----------
create or replace function public.api_cleanup()
returns void language sql security definer set search_path = '' as $$
  delete from public.api_usage where window_start < now() - interval '3 days';
  delete from public.api_auth_failures where window_start < now() - interval '1 day';
  delete from public.api_audit_log where created_at < now() - interval '365 days';
$$;
revoke execute on function public.api_cleanup() from public, anon, authenticated;
grant execute on function public.api_cleanup() to service_role;
