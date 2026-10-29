-- =====================================================================
-- Segunda auditoría: mínimo privilegio y presupuesto
--  1. Nuevo permiso "create": guardar productos nuevos sin poder leer el
--     catálogo ni modificar lo que ya existe. "write" incluye a "create".
--  2. Presupuesto de fotos: MB por día y espacio total máximo por cuenta,
--     para que nadie (ni una página que manipule a ChatGPT) agote el plan.
-- =====================================================================

-- ---------- 1. Permisos ----------
alter table public.api_keys drop constraint if exists api_keys_scopes_check;
alter table public.api_keys add constraint api_keys_scopes_check
  check (scopes <@ array['read','create','write']::text[] and cardinality(scopes) > 0);

-- ---------- 2. Presupuesto ----------
alter table public.api_settings add column if not exists daily_image_mb int not null default 300 check (daily_image_mb between 0 and 5000);
alter table public.api_settings add column if not exists max_storage_mb int not null default 2048 check (max_storage_mb between 0 and 100000);

drop function if exists public.api_authenticate(text);
create function public.api_authenticate(p_key_hash text)
returns table (key_id uuid, owner_id uuid, scopes text[], enabled boolean, daily_create_limit int, daily_write_limit int,
               daily_image_limit int, daily_image_mb int, max_storage_mb int)
language plpgsql security definer set search_path = '' as $$
begin
  return query
  update public.api_keys k
     set last_used_at = now(), use_count = k.use_count + 1
   where k.key_hash = p_key_hash
     and k.revoked_at is null
     and (k.expires_at is null or k.expires_at > now())
  returning k.id, k.owner_id, k.scopes,
            coalesce((select s.enabled from public.api_settings s where s.owner_id = k.owner_id), true),
            coalesce((select s.daily_create_limit from public.api_settings s where s.owner_id = k.owner_id), 100),
            coalesce((select s.daily_write_limit from public.api_settings s where s.owner_id = k.owner_id), 400),
            coalesce((select s.daily_image_limit from public.api_settings s where s.owner_id = k.owner_id), 400),
            coalesce((select s.daily_image_mb from public.api_settings s where s.owner_id = k.owner_id), 300),
            coalesce((select s.max_storage_mb from public.api_settings s where s.owner_id = k.owner_id), 2048);
end $$;
revoke execute on function public.api_authenticate(text) from public, anon, authenticated;
grant execute on function public.api_authenticate(text) to service_role;

-- Espacio real ocupado en storage por una cuenta (bytes), incluidos archivos huérfanos.
create or replace function public.api_storage_used(p_owner uuid)
returns bigint language sql stable security definer set search_path = '' as $$
  select coalesce(sum(coalesce((o.metadata ->> 'size')::bigint, 0)), 0)::bigint
    from storage.objects o
   where o.bucket_id in ('product-images', 'brand-logos')
     and (storage.foldername(o.name))[1] = p_owner::text;
$$;
revoke execute on function public.api_storage_used(uuid) from public, anon, authenticated;
grant execute on function public.api_storage_used(uuid) to service_role;

-- ---------- 3. Claves siempre con caducidad (máx. 730 días) ----------
-- Si ya existían claves sin caducidad (o más largas de 730 días), se acortan antes de exigirlo.
update public.api_keys set expires_at = least(coalesce(expires_at, created_at + interval '730 days'), created_at + interval '730 days')
 where expires_at is null or expires_at > created_at + interval '731 days';
alter table public.api_keys drop constraint if exists api_keys_expiry_required;
alter table public.api_keys add constraint api_keys_expiry_required
  check (expires_at is not null and expires_at <= created_at + interval '731 days');

create or replace function public.create_api_key(p_label text default 'ChatGPT', p_scopes text[] default '{read,create}', p_days int default 180, p_owner uuid default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := auth.uid();
  owner uuid;
  raw text;
begin
  if caller is not null then
    if p_owner is not null and p_owner <> caller then raise exception 'No puedes crear claves para otro usuario'; end if;
    owner := caller;
  else
    owner := p_owner;
  end if;
  if owner is null or not exists (select 1 from auth.users u where u.id = owner) then
    raise exception 'Usuario no válido';
  end if;
  if p_days is null or p_days < 1 or p_days > 730 then raise exception 'La caducidad debe estar entre 1 y 730 días'; end if;
  if p_scopes is null or cardinality(p_scopes) = 0 then raise exception 'Indica los permisos de la clave'; end if;
  if (select count(*) from public.api_keys k where k.owner_id = owner and k.revoked_at is null and k.expires_at > now()) >= 5 then
    raise exception 'Máximo 5 claves activas; revoca alguna primero';
  end if;
  raw := 'mc_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.api_keys (owner_id, label, key_hash, key_prefix, scopes, expires_at)
  values (owner, coalesce(nullif(trim(left(p_label, 60)), ''), 'ChatGPT'), encode(extensions.digest(raw, 'sha256'), 'hex'),
          left(raw, 7), p_scopes, now() + make_interval(days => p_days));
  insert into public.api_settings (owner_id) values (owner) on conflict do nothing;
  return raw;
end $$;
revoke execute on function public.create_api_key(text, text[], int, uuid) from public, anon;
grant execute on function public.create_api_key(text, text[], int, uuid) to authenticated;

-- ---------- 4. El historial de versiones no se puede "empujar" fuera ----------
-- Antes: solo las 30 últimas versiones. 31 cambios desde la API borraban el original.
-- Ahora: se guarda todo lo de los últimos 30 días y, SIEMPRE, tu último cambio a mano y el
-- estado que dejaste (o el original si nunca editaste), por muchos cambios que haga la API.
create or replace function public.keep_product_version()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  src text := coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-catalog-source', 'app');
  keep_human bigint;
  keep_after bigint;
begin
  if to_jsonb(old) - 'updated_at' - 'search_text' = to_jsonb(new) - 'updated_at' - 'search_text' then
    return new;
  end if;
  insert into public.product_versions (product_id, owner_id, source, previous)
  values (old.id, old.owner_id, left(src, 20), to_jsonb(old) - 'search_text');
  select v.id into keep_human from public.product_versions v
   where v.product_id = old.id and v.source <> 'chatgpt' order by v.changed_at desc, v.id desc limit 1;
  -- La versión siguiente guarda el estado que dejaste tú (o el original, si nunca editaste a mano).
  select min(v.id) into keep_after from public.product_versions v
   where v.product_id = old.id and v.id > coalesce(keep_human, 0);
  delete from public.product_versions v
   where v.product_id = old.id
     and v.changed_at < now() - interval '30 days'
     and v.id is distinct from keep_human
     and v.id is distinct from keep_after
     and v.id not in (select v2.id from public.product_versions v2 where v2.product_id = old.id order by v2.changed_at desc, v2.id desc limit 30);
  return new;
end $$;
revoke execute on function public.keep_product_version() from public, anon, authenticated;

-- ---------- 5. Limpieza programada (si pg_cron está disponible) ----------
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('mi-catalogo-api-cleanup', '17 4 * * *', 'select public.api_cleanup()');
exception when others then
  raise notice 'pg_cron no disponible: programa "select public.api_cleanup()" a mano (%).', sqlerrm;
end $$;
