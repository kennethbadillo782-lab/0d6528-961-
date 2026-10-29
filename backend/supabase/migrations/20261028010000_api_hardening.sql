-- =====================================================================
-- Refuerzo de seguridad de la API de ChatGPT
--  * Claves guardadas solo como huella SHA-256, con permisos (read/write),
--    caducidad, revocación y registro de último uso.
--  * Interruptor para pausar el acceso de ChatGPT desde la app.
--  * Límites de uso persistentes (por minuto y por día).
--  * Historial de versiones de cada producto para deshacer cambios.
-- =====================================================================

-- ---------- Claves de API ----------
create table if not exists public.api_keys (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users(id) on delete cascade,
  label        text not null default 'ChatGPT' check (char_length(label) between 1 and 60),
  key_hash     text not null unique check (key_hash ~ '^[0-9a-f]{64}$'),
  key_prefix   text not null,
  scopes       text[] not null default '{read,write}' check (scopes <@ array['read','write']::text[] and cardinality(scopes) > 0),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz,
  revoked_at   timestamptz,
  last_used_at timestamptz,
  use_count    bigint not null default 0
);
create index if not exists api_keys_owner_idx on public.api_keys (owner_id);
alter table public.api_keys enable row level security;
drop policy if exists "owner_read_keys" on public.api_keys;
create policy "owner_read_keys" on public.api_keys for select to authenticated using ((select auth.uid()) = owner_id);
-- La app solo puede revocar (no ver la clave ni cambiar su huella).
revoke all on public.api_keys from anon, authenticated;
grant select on public.api_keys to authenticated;
grant update (revoked_at, label) on public.api_keys to authenticated;
drop policy if exists "owner_revoke_keys" on public.api_keys;
create policy "owner_revoke_keys" on public.api_keys for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);

-- ---------- Ajustes de acceso ----------
create table if not exists public.api_settings (
  owner_id           uuid primary key references auth.users(id) on delete cascade,
  enabled            boolean not null default true,
  daily_create_limit int not null default 100 check (daily_create_limit between 0 and 1000),
  daily_write_limit  int not null default 400 check (daily_write_limit between 0 and 5000),
  daily_image_limit  int not null default 400 check (daily_image_limit between 0 and 5000),
  updated_at         timestamptz not null default now()
);
create trigger api_settings_updated_at before update on public.api_settings
  for each row execute function public.set_updated_at();
alter table public.api_settings enable row level security;
drop policy if exists "owner_select" on public.api_settings;
drop policy if exists "owner_update" on public.api_settings;
drop policy if exists "owner_insert" on public.api_settings;
create policy "owner_select" on public.api_settings for select to authenticated using ((select auth.uid()) = owner_id);
create policy "owner_insert" on public.api_settings for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy "owner_update" on public.api_settings for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);

-- ---------- Contadores de uso ----------
create table if not exists public.api_usage (
  owner_id     uuid not null references auth.users(id) on delete cascade,
  bucket       text not null,
  window_start timestamptz not null,
  count        int not null default 0,
  primary key (owner_id, bucket, window_start)
);
alter table public.api_usage enable row level security;  -- sin políticas: solo el servidor

create table if not exists public.api_auth_failures (
  ip_hash      text not null,
  window_start timestamptz not null,
  count        int not null default 0,
  primary key (ip_hash, window_start)
);
alter table public.api_auth_failures enable row level security;  -- sin políticas: solo el servidor

-- Más detalle en el historial
alter table public.api_audit_log add column if not exists key_id uuid;
alter table public.api_audit_log add column if not exists ip_hash text;

-- ---------- Funciones (solo las ejecuta el servidor) ----------

-- Valida una clave por su huella y devuelve dueño, permisos y si el acceso está activo.
create or replace function public.api_authenticate(p_key_hash text)
returns table (key_id uuid, owner_id uuid, scopes text[], enabled boolean, daily_create_limit int, daily_write_limit int, daily_image_limit int)
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
            coalesce((select s.daily_image_limit from public.api_settings s where s.owner_id = k.owner_id), 400);
end $$;

-- Suma uso de forma atómica y dice si sigue dentro del límite.
create or replace function public.api_consume(p_owner uuid, p_bucket text, p_window_seconds int, p_max int, p_amount int default 1)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  w timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  c int;
begin
  insert into public.api_usage (owner_id, bucket, window_start, count)
  values (p_owner, p_bucket, w, p_amount)
  on conflict (owner_id, bucket, window_start) do update set count = public.api_usage.count + p_amount
  returning count into c;
  return c <= p_max;
end $$;

-- Cuenta intentos fallidos por IP (en ventanas de 10 minutos) y devuelve el total.
create or replace function public.api_note_auth_failure(p_ip_hash text)
returns int language plpgsql security definer set search_path = '' as $$
declare
  w timestamptz := to_timestamp(floor(extract(epoch from now()) / 600) * 600);
  c int;
begin
  insert into public.api_auth_failures (ip_hash, window_start, count) values (p_ip_hash, w, 1)
  on conflict (ip_hash, window_start) do update set count = public.api_auth_failures.count + 1
  returning count into c;
  return c;
end $$;

create or replace function public.api_auth_failures_recent(p_ip_hash text)
returns int language sql security definer set search_path = '' as $$
  select coalesce(sum(count), 0)::int from public.api_auth_failures
  where ip_hash = p_ip_hash and window_start > now() - interval '30 minutes';
$$;

-- Limpieza de contadores viejos (se puede programar con pg_cron).
create or replace function public.api_cleanup()
returns void language sql security definer set search_path = '' as $$
  delete from public.api_usage where window_start < now() - interval '3 days';
  delete from public.api_auth_failures where window_start < now() - interval '1 day';
$$;

-- Crea una clave nueva. Devuelve la clave en claro UNA sola vez.
-- Desde la app (usuario con sesión) o desde el SQL Editor indicando p_owner.
create or replace function public.create_api_key(p_label text default 'ChatGPT', p_scopes text[] default '{read,write}', p_days int default 365, p_owner uuid default null)
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
  if p_days is not null and (p_days < 1 or p_days > 730) then raise exception 'La caducidad debe estar entre 1 y 730 días'; end if;
  if (select count(*) from public.api_keys k where k.owner_id = owner and k.revoked_at is null) >= 5 then
    raise exception 'Máximo 5 claves activas; revoca alguna primero';
  end if;
  raw := 'mc_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.api_keys (owner_id, label, key_hash, key_prefix, scopes, expires_at)
  values (owner, coalesce(nullif(trim(p_label), ''), 'ChatGPT'), encode(extensions.digest(raw, 'sha256'), 'hex'),
          left(raw, 7), p_scopes, case when p_days is null then null else now() + make_interval(days => p_days) end);
  insert into public.api_settings (owner_id) values (owner) on conflict do nothing;
  return raw;
end $$;

revoke execute on function public.api_authenticate(text) from public, anon, authenticated;
revoke execute on function public.api_consume(uuid, text, int, int, int) from public, anon, authenticated;
revoke execute on function public.api_note_auth_failure(text) from public, anon, authenticated;
revoke execute on function public.api_auth_failures_recent(text) from public, anon, authenticated;
revoke execute on function public.api_cleanup() from public, anon, authenticated;
revoke execute on function public.create_api_key(text, text[], int, uuid) from public, anon;
grant execute on function public.create_api_key(text, text[], int, uuid) to authenticated;
grant execute on function public.api_authenticate(text) to service_role;
grant execute on function public.api_consume(uuid, text, int, int, int) to service_role;
grant execute on function public.api_note_auth_failure(text) to service_role;
grant execute on function public.api_auth_failures_recent(text) to service_role;
grant execute on function public.api_cleanup() to service_role;

-- ---------- Historial de versiones de productos (para deshacer) ----------
create table if not exists public.product_versions (
  id          bigint generated always as identity primary key,
  product_id  uuid not null references public.products(id) on delete cascade,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  source      text not null default 'app',
  previous    jsonb not null,
  changed_at  timestamptz not null default now()
);
create index if not exists product_versions_product_idx on public.product_versions (product_id, changed_at desc);
alter table public.product_versions enable row level security;
drop policy if exists "owner_read_versions" on public.product_versions;
create policy "owner_read_versions" on public.product_versions for select to authenticated using ((select auth.uid()) = owner_id);

create or replace function public.keep_product_version()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  src text := coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-catalog-source', 'app');
begin
  if to_jsonb(old) - 'updated_at' - 'search_text' = to_jsonb(new) - 'updated_at' - 'search_text' then
    return new;
  end if;
  insert into public.product_versions (product_id, owner_id, source, previous)
  values (old.id, old.owner_id, left(src, 20), to_jsonb(old) - 'search_text');
  -- Conserva las 30 versiones más recientes por producto.
  delete from public.product_versions v
   where v.product_id = old.id
     and v.id not in (select v2.id from public.product_versions v2 where v2.product_id = old.id order by v2.changed_at desc, v2.id desc limit 30);
  return new;
end $$;
drop trigger if exists products_keep_version on public.products;
create trigger products_keep_version before update on public.products
  for each row execute function public.keep_product_version();

-- Restaura una versión anterior (lo usa la app; respeta RLS porque es "invoker").
create or replace function public.restore_product_version(p_version_id bigint)
returns void language plpgsql security invoker set search_path = '' as $$
declare v jsonb;
begin
  select previous into v from public.product_versions where id = p_version_id;
  if v is null then raise exception 'Versión no encontrada'; end if;
  update public.products p set
    name = v->>'name', brand = v->>'brand', category_key = v->>'category_key', subcategory = v->>'subcategory',
    description = v->>'description', price_current = (v->>'price_current')::numeric, price_previous = (v->>'price_previous')::numeric,
    currency = v->>'currency', shipping_estimate_usd = (v->>'shipping_estimate_usd')::numeric,
    original_url = v->>'original_url', normalized_url = v->>'normalized_url', platform = v->>'platform',
    agent_links = v->'agent_links', seller_name = v->>'seller_name', seller_rating = (v->>'seller_rating')::numeric,
    seller_rating_count = v->>'seller_rating_count', seller_rating_source = v->>'seller_rating_source',
    color = v->>'color', size = v->>'size', material = v->>'material', attributes = v->'attributes',
    declared_quality = v->>'declared_quality', verified_quality = v->>'verified_quality', included_accessories = v->>'included_accessories',
    notes = v->>'notes', is_favorite = (v->>'is_favorite')::boolean, priority = (v->>'priority')::smallint,
    status = (v->>'status')::public.purchase_status, deleted_at = (v->>'deleted_at')::timestamptz
  where p.id = (v->>'id')::uuid;
end $$;
revoke execute on function public.restore_product_version(bigint) from public, anon;
grant execute on function public.restore_product_version(bigint) to authenticated;

-- Al crear la cuenta también se crean sus ajustes de API.
create or replace function public.seed_api_settings()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.api_settings (owner_id) values (new.id) on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created_api on auth.users;
create trigger on_auth_user_created_api after insert on auth.users
  for each row execute function public.seed_api_settings();
