-- =====================================================================
-- Mi Catálogo de Moda — esquema inicial
-- Cada fila pertenece a un usuario (owner_id) y Row Level Security
-- impide que nadie más la lea o modifique. Los borrados son "suaves"
-- (deleted_at) para que la sincronización con el iPhone pueda propagarlos.
-- =====================================================================

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

-- ---------- Tipos ----------
do $$ begin
  create type public.purchase_status as enum ('researching','favorite','pending','ready','purchased','discarded');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.image_kind as enum ('official','qc','buyer','worn','manual');
exception when duplicate_object then null; end $$;

-- ---------- Utilidades ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------- Categorías ----------
create table if not exists public.categories (
  owner_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  key           text not null check (key ~ '^[a-z0-9-]{1,40}$'),
  name          text not null check (char_length(name) between 1 and 60),
  symbol        text not null default 'tag',
  group_key     text not null default 'accessories' check (group_key in ('clothing','shoes','bags','accessories')),
  subcategories text[] not null default '{}',
  sort_order    int  not null default 0,
  show_on_home  boolean not null default true,
  is_builtin    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  primary key (owner_id, key)
);
create trigger categories_updated_at before update on public.categories
  for each row execute function public.set_updated_at();

-- ---------- Productos ----------
create table if not exists public.products (
  id                   uuid primary key default gen_random_uuid(),
  owner_id             uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name                 text not null default '' check (char_length(name) <= 300),
  brand                text not null default '' check (char_length(brand) <= 120),
  category_key         text not null default 'otros' check (char_length(category_key) <= 40),
  subcategory          text not null default '' check (char_length(subcategory) <= 60),
  description          text not null default '' check (char_length(description) <= 5000),
  price_current        numeric(12,2) check (price_current is null or price_current >= 0),
  price_previous       numeric(12,2) check (price_previous is null or price_previous >= 0),
  currency             char(3) not null default 'CNY' check (currency ~ '^[A-Z]{3}$'),
  shipping_estimate_usd numeric(10,2) check (shipping_estimate_usd is null or shipping_estimate_usd >= 0),
  original_url         text not null default '' check (char_length(original_url) <= 2048),
  normalized_url       text not null default '' check (char_length(normalized_url) <= 2048),
  platform             text not null default '' check (char_length(platform) <= 60),
  agent_links          jsonb not null default '[]'::jsonb check (jsonb_typeof(agent_links) = 'array'),
  seller_name          text not null default '' check (char_length(seller_name) <= 120),
  seller_rating        numeric(3,2) check (seller_rating is null or seller_rating between 0 and 5),
  seller_rating_count  text not null default '' check (char_length(seller_rating_count) <= 20),
  seller_rating_source text not null default '' check (char_length(seller_rating_source) <= 120),
  color                text not null default '' check (char_length(color) <= 60),
  size                 text not null default '' check (char_length(size) <= 60),
  material             text not null default '' check (char_length(material) <= 120),
  attributes           jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),
  declared_quality     text not null default '' check (char_length(declared_quality) <= 120),
  verified_quality     text not null default '' check (char_length(verified_quality) <= 120),
  included_accessories text not null default '' check (char_length(included_accessories) <= 200),
  notes                text not null default '' check (char_length(notes) <= 5000),
  is_favorite          boolean not null default false,
  priority             smallint not null default 0 check (priority between 0 and 3),
  status               public.purchase_status not null default 'researching',
  source               text not null default 'app' check (source in ('app','chatgpt','import')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);
create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

create index if not exists products_owner_created_idx  on public.products (owner_id, created_at desc) where deleted_at is null;
create index if not exists products_owner_updated_idx  on public.products (owner_id, updated_at);
create index if not exists products_owner_category_idx on public.products (owner_id, category_key) where deleted_at is null;
create index if not exists products_owner_url_idx      on public.products (owner_id, normalized_url) where normalized_url <> '' and deleted_at is null;
alter table public.products add column if not exists search_text text
  generated always as (lower(name || ' ' || brand || ' ' || subcategory || ' ' || seller_name || ' ' || platform || ' ' || color || ' ' || notes)) stored;
create index if not exists products_search_idx on public.products using gin (search_text gin_trgm_ops);

-- ---------- Imágenes ----------
create table if not exists public.product_images (
  id           uuid primary key default gen_random_uuid(),
  product_id   uuid not null references public.products(id) on delete cascade,
  owner_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  storage_path text not null check (char_length(storage_path) <= 400),
  source_url   text not null default '' check (char_length(source_url) <= 2048),
  kind         public.image_kind not null default 'official',
  position     int not null default 0,
  content_type text not null default 'image/jpeg',
  bytes        int,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create trigger product_images_updated_at before update on public.product_images
  for each row execute function public.set_updated_at();
create index if not exists product_images_product_idx on public.product_images (product_id, position) where deleted_at is null;
create index if not exists product_images_owner_updated_idx on public.product_images (owner_id, updated_at);

-- ---------- Colecciones ----------
create table if not exists public.collections (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 80),
  cover_path  text,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create trigger collections_updated_at before update on public.collections
  for each row execute function public.set_updated_at();
create index if not exists collections_owner_updated_idx on public.collections (owner_id, updated_at);
create unique index if not exists collections_owner_name_uidx on public.collections (owner_id, lower(name)) where deleted_at is null;

create table if not exists public.product_collections (
  owner_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  product_id    uuid not null references public.products(id) on delete cascade,
  collection_id uuid not null references public.collections(id) on delete cascade,
  added_at      timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  primary key (product_id, collection_id)
);
create trigger product_collections_updated_at before update on public.product_collections
  for each row execute function public.set_updated_at();
create index if not exists product_collections_owner_updated_idx on public.product_collections (owner_id, updated_at);
create index if not exists product_collections_collection_idx on public.product_collections (collection_id) where deleted_at is null;

-- ---------- Imagen de marca (la sube el propio usuario) ----------
create table if not exists public.brand_logos (
  owner_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  brand_key    text not null check (char_length(brand_key) between 1 and 120),
  brand_name   text not null,
  storage_path text not null,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  primary key (owner_id, brand_key)
);
create trigger brand_logos_updated_at before update on public.brand_logos
  for each row execute function public.set_updated_at();

-- ---------- Ajustes del usuario (moneda, tasas, visualización) ----------
create table if not exists public.user_settings (
  owner_id   uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  settings   jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create trigger user_settings_updated_at before update on public.user_settings
  for each row execute function public.set_updated_at();

-- ---------- Registro de lo que hace la API (ChatGPT) ----------
create table if not exists public.api_audit_log (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  operation   text not null,
  product_id  uuid,
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists api_audit_log_owner_idx on public.api_audit_log (owner_id, created_at desc);

-- ---------- Integridad: las filas hijas deben ser del mismo dueño ----------
create or replace function public.check_image_owner()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.products p where p.id = new.product_id and p.owner_id = new.owner_id) then
    raise exception 'El producto no pertenece a este usuario';
  end if;
  return new;
end $$;

create or replace function public.check_membership_owner()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.products p where p.id = new.product_id and p.owner_id = new.owner_id) then
    raise exception 'El producto no pertenece a este usuario';
  end if;
  if not exists (select 1 from public.collections c where c.id = new.collection_id and c.owner_id = new.owner_id) then
    raise exception 'La colección no pertenece a este usuario';
  end if;
  return new;
end $$;

create trigger product_images_same_owner before insert or update on public.product_images
  for each row execute function public.check_image_owner();
create trigger product_collections_same_owner before insert or update on public.product_collections
  for each row execute function public.check_membership_owner();

-- =====================================================================
-- Row Level Security: cada usuario solo ve y toca lo suyo
-- =====================================================================
alter table public.categories          enable row level security;
alter table public.products            enable row level security;
alter table public.product_images      enable row level security;
alter table public.collections         enable row level security;
alter table public.product_collections enable row level security;
alter table public.brand_logos         enable row level security;
alter table public.user_settings       enable row level security;
alter table public.api_audit_log       enable row level security;

do $$
declare t text;
begin
  foreach t in array array['categories','products','product_images','collections','product_collections','brand_logos','user_settings']
  loop
    execute format('drop policy if exists "owner_select" on public.%I', t);
    execute format('drop policy if exists "owner_insert" on public.%I', t);
    execute format('drop policy if exists "owner_update" on public.%I', t);
    execute format('drop policy if exists "owner_delete" on public.%I', t);
    execute format('create policy "owner_select" on public.%I for select to authenticated using ((select auth.uid()) = owner_id)', t);
    execute format('create policy "owner_insert" on public.%I for insert to authenticated with check ((select auth.uid()) = owner_id)', t);
    execute format('create policy "owner_update" on public.%I for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id)', t);
    execute format('create policy "owner_delete" on public.%I for delete to authenticated using ((select auth.uid()) = owner_id)', t);
  end loop;
end $$;

-- El historial de la API solo se puede leer desde la app (lo escribe el servidor).
drop policy if exists "owner_read_audit" on public.api_audit_log;
create policy "owner_read_audit" on public.api_audit_log for select to authenticated using ((select auth.uid()) = owner_id);

-- Nadie anónimo tiene acceso.
revoke all on all tables in schema public from anon;

-- =====================================================================
-- Almacenamiento de fotos (privado). Ruta: <owner_id>/<product_id>/<archivo>
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('product-images', 'product-images', false, 12582912, array['image/jpeg','image/png','image/webp','image/heic','image/gif']),
  ('brand-logos',    'brand-logos',    false, 2097152,  array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

do $$
declare b text;
begin
  foreach b in array array['product-images','brand-logos']
  loop
    execute format('drop policy if exists "%s_owner_select" on storage.objects', b);
    execute format('drop policy if exists "%s_owner_insert" on storage.objects', b);
    execute format('drop policy if exists "%s_owner_update" on storage.objects', b);
    execute format('drop policy if exists "%s_owner_delete" on storage.objects', b);
    execute format($p$create policy "%s_owner_select" on storage.objects for select to authenticated using (bucket_id = %L and (storage.foldername(name))[1] = (select auth.uid())::text)$p$, b, b);
    execute format($p$create policy "%s_owner_insert" on storage.objects for insert to authenticated with check (bucket_id = %L and (storage.foldername(name))[1] = (select auth.uid())::text)$p$, b, b);
    execute format($p$create policy "%s_owner_update" on storage.objects for update to authenticated using (bucket_id = %L and (storage.foldername(name))[1] = (select auth.uid())::text)$p$, b, b);
    execute format($p$create policy "%s_owner_delete" on storage.objects for delete to authenticated using (bucket_id = %L and (storage.foldername(name))[1] = (select auth.uid())::text)$p$, b, b);
  end loop;
end $$;

-- =====================================================================
-- Al crear la cuenta: categorías iniciales y "Lista principal"
-- =====================================================================
create or replace function public.seed_user(uid uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.categories (owner_id, key, name, symbol, group_key, subcategories, sort_order, is_builtin) values
    (uid, 'camisas',    'Camisas',    'tshirt',          'clothing',    array['T-Shirts','Polo','Mangas Largas','Manga corta','Botones','Oversize'], 0, true),
    (uid, 'pantalones', 'Pantalones', 'figure.walk',     'clothing',    array['Jeans','Cargo','Shorts','Jogger','Chinos','Formales','Deportivos','Técnicos'], 1, true),
    (uid, 'carteras',   'Carteras',   'handbag',         'bags',        array['Crossbody','Backpack','Billetera','Tote','Shoulder Bag','Messenger','Camera Bag'], 2, true),
    (uid, 'zapatos',    'Zapatos',    'shoe.2',          'shoes',       array['Sneakers','Botas','Sandalias','Formales'], 3, true),
    (uid, 'pantallas',  'Pantallas',  'sparkle',         'accessories', array['Redondas','Cuadradas','Halo','Cluster','Solitarias','Iced Out'], 4, true),
    (uid, 'gorras',     'Gorras',     'baseball',        'accessories', array['Baseball','Trucker','Fitted','Snapback'], 5, true),
    (uid, 'relojes',    'Relojes',    'clock',           'accessories', array['Deportivos','Clásicos','Digitales'], 6, true),
    (uid, 'abrigos',    'Abrigos',    'wind',            'clothing',    array['Hoodies','Chaquetas','Suéteres','Rompevientos'], 7, true),
    (uid, 'joyeria',    'Joyería',    'sparkles',        'accessories', array['Cadenas','Collares','Pulseras','Anillos'], 8, true),
    (uid, 'gafas',      'Gafas',      'eyeglasses',      'accessories', array['Sol','Ópticas','Deportivas'], 9, true),
    (uid, 'otros',      'Otros',      'square.grid.2x2', 'accessories', array['Correas','Accesorios','Personalizados'], 10, true)
  on conflict do nothing;
  insert into public.collections (owner_id, name, sort_order) values (uid, 'Lista principal', 0)
  on conflict do nothing;
  insert into public.user_settings (owner_id, settings) values (uid, '{"primaryCurrency":"USD","showUSDEquivalent":true}')
  on conflict do nothing;
end $$;

revoke execute on function public.seed_user(uuid) from public, anon, authenticated;

create or replace function public.seed_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.seed_user(new.id);
  return new;
end $$;

drop trigger if exists on_auth_user_created_seed on auth.users;
create trigger on_auth_user_created_seed after insert on auth.users
  for each row execute function public.seed_new_user();
