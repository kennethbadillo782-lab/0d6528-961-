-- =====================================================================
-- Pruebas de ataque contra la base de datos (Row Level Security, funciones,
-- storage y bloqueo de registros). Se ejecuta con scripts/run-db-tests.sh.
--   A = tú (dueño), B = otra cuenta (atacante con sesión), anon = sin sesión
-- Cada prueba imprime PASS/FAIL; al final falla si hubo algún FAIL.
-- =====================================================================
\set ON_ERROR_STOP 1
set client_min_messages = notice;

create schema t;
create table t.results (label text, ok boolean, info text);
grant usage on schema t to anon, authenticated, service_role;
grant insert, select on t.results to anon, authenticated, service_role;

-- Debe fallar (cualquier error cuenta como bloqueo).
create function t.must_fail(label text, q text) returns void language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    insert into t.results values (label, true, sqlerrm);
    raise notice 'PASS  %  (%)', label, left(sqlerrm, 70);
    return;
  end;
  insert into t.results values (label, false, 'se ejecutó');
  raise notice 'FAIL  %  (se ejecutó sin error)', label;
end $$;

-- Debe devolver exactamente n filas (o fallar si n = 0 y no hay permiso).
create function t.rows(label text, q text, n int) returns void language plpgsql as $$
declare c int;
begin
  begin
    execute format('select count(*) from (%s) s', q) into c;
  exception when others then
    if n = 0 then
      insert into t.results values (label, true, sqlerrm);
      raise notice 'PASS  %  (bloqueado: %)', label, left(sqlerrm, 60);
    else
      insert into t.results values (label, false, sqlerrm);
      raise notice 'FAIL  %  (%)', label, sqlerrm;
    end if;
    return;
  end;
  insert into t.results values (label, c = n, c::text);
  raise notice '%  %  (% filas, se esperaban %)', case when c = n then 'PASS' else 'FAIL' end, label, c, n;
end $$;

-- "Cambios" que no deben afectar ninguna fila (RLS los ignora en silencio).
create function t.affects(label text, q text, n int) returns void language plpgsql as $$
declare c int;
begin
  begin
    execute format('with x as (%s returning 1) select count(*) from x', q) into c;
  exception when others then
    insert into t.results values (label, n = 0, sqlerrm);
    raise notice '%  %  (bloqueado: %)', case when n = 0 then 'PASS' else 'FAIL' end, label, left(sqlerrm, 60);
    return;
  end;
  insert into t.results values (label, c = n, c::text);
  raise notice '%  %  (% filas cambiadas, se esperaban %)', case when c = n then 'PASS' else 'FAIL' end, label, c, n;
end $$;

grant execute on all functions in schema t to anon, authenticated, service_role;

-- ---------- Datos ----------
update private.app_config set max_users = 3;
insert into auth.users values ('aaaaaaaa-0000-4000-8000-000000000001', 'yo@ejemplo.com');
insert into auth.users values ('bbbbbbbb-0000-4000-8000-000000000002', 'atacante@ejemplo.com');
insert into public.products (id, owner_id, name, original_url, normalized_url)
values ('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'Polo secreto de A', 'https://item.taobao.com/item.htm?id=1', 'item.taobao.com/item.htm?id=1');
insert into public.products (id, owner_id, name)
values ('22222222-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002', 'Producto de B');
insert into public.product_images (product_id, owner_id, storage_path) values ('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001/1/x.jpg');
update public.products set name = 'Polo secreto de A v2' where id = '11111111-0000-4000-8000-000000000001';
insert into storage.objects (bucket_id, name) values ('product-images', 'aaaaaaaa-0000-4000-8000-000000000001/11111111/foto.jpg');
insert into public.api_audit_log (owner_id, operation) values ('aaaaaaaa-0000-4000-8000-000000000001', 'create_product');
select public.create_api_key('ChatGPT', '{read,write}', 365, 'aaaaaaaa-0000-4000-8000-000000000001') is not null as key_a;
select public.create_api_key('B', '{read}', 30, 'bbbbbbbb-0000-4000-8000-000000000002') is not null as key_b;
select public.api_note_auth_failure('ipatacante');
create table t.vars (k text primary key, v text);
grant select on t.vars to anon, authenticated, service_role;
insert into t.vars select 'a_col', id::text from public.collections where owner_id = 'aaaaaaaa-0000-4000-8000-000000000001' limit 1;
insert into t.vars select 'a_version', max(id)::text from public.product_versions;

-- =====================================================================
\echo '--- 1. Sin sesión (anon) ---'
set role anon;
select t.rows('anon no lee productos', 'select * from public.products', 0);
select t.rows('anon no lee fotos', 'select * from public.product_images', 0);
select t.rows('anon no lee colecciones', 'select * from public.collections', 0);
select t.rows('anon no lee categorías', 'select * from public.categories', 0);
select t.rows('anon no lee claves', 'select * from public.api_keys', 0);
select t.rows('anon no lee ajustes API', 'select * from public.api_settings', 0);
select t.rows('anon no lee historial API', 'select * from public.api_audit_log', 0);
select t.rows('anon no lee versiones', 'select * from public.product_versions', 0);
select t.rows('anon no lee contadores', 'select * from public.api_usage', 0);
select t.rows('anon no lee storage', 'select * from storage.objects', 0);
select t.must_fail('anon no crea productos', $q$insert into public.products (owner_id, name) values ('aaaaaaaa-0000-4000-8000-000000000001', 'x')$q$);
select t.must_fail('anon no sube fotos', $q$insert into storage.objects (bucket_id, name) values ('product-images', 'aaaaaaaa-0000-4000-8000-000000000001/x/y.jpg')$q$);
select t.must_fail('anon no crea claves', $q$select public.create_api_key('x', '{read,write}', 30, 'aaaaaaaa-0000-4000-8000-000000000001')$q$);
select t.must_fail('anon no valida claves', $q$select * from public.api_authenticate(repeat('a', 64))$q$);
select t.must_fail('anon no toca límites', $q$select public.api_consume('aaaaaaaa-0000-4000-8000-000000000001', 'minute', 60, 999999, -1000)$q$);
select t.must_fail('anon no siembra datos', $q$select public.seed_user('aaaaaaaa-0000-4000-8000-000000000001')$q$);
select t.must_fail('anon no restaura versiones', $q$select public.restore_product_version(1)$q$);
select t.must_fail('anon no crea usuarios', $q$insert into auth.users values (gen_random_uuid(), 'x@x.com')$q$);
reset role;

-- =====================================================================
\echo '--- 2. Otra cuenta con sesión (B) contra los datos de A ---'
set role authenticated;
set request.jwt.claim.sub = 'bbbbbbbb-0000-4000-8000-000000000002';
select t.rows('B solo ve sus productos', 'select * from public.products', 1);
select t.rows('B no ve el producto de A', $q$select * from public.products where id = '11111111-0000-4000-8000-000000000001'$q$, 0);
select t.rows('B no ve fotos de A', 'select * from public.product_images', 0);
select t.rows('B no ve versiones de A', 'select * from public.product_versions', 0);
select t.rows('B no ve historial de A', 'select * from public.api_audit_log', 0);
select t.rows('B solo ve su clave', 'select * from public.api_keys', 1);
select t.rows('B no ve el storage de A', 'select * from storage.objects', 0);
select t.rows('B no ve categorías de A', $q$select * from public.categories where owner_id = 'aaaaaaaa-0000-4000-8000-000000000001'$q$, 0);
select t.affects('B no edita productos de A', $q$update public.products set name = 'hackeado' where id = '11111111-0000-4000-8000-000000000001'$q$, 0);
select t.affects('B no borra productos de A', $q$delete from public.products where id = '11111111-0000-4000-8000-000000000001'$q$, 0);
select t.affects('B no borra categorías de A', $q$delete from public.categories where owner_id = 'aaaaaaaa-0000-4000-8000-000000000001'$q$, 0);
select t.must_fail('B no crea productos a nombre de A', $q$insert into public.products (owner_id, name) values ('aaaaaaaa-0000-4000-8000-000000000001', 'spam')$q$);
select t.must_fail('B no regala su producto a A (cambio de dueño)', $q$update public.products set owner_id = 'aaaaaaaa-0000-4000-8000-000000000001' where id = '22222222-0000-4000-8000-000000000002'$q$);
select t.must_fail('B no cuelga fotos en el producto de A', $q$insert into public.product_images (product_id, owner_id, storage_path) values ('11111111-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002', 'b/x.jpg')$q$);
select t.must_fail('B no mete su producto en colección de A', $q$insert into public.product_collections (owner_id, product_id, collection_id) values ('bbbbbbbb-0000-4000-8000-000000000002', '22222222-0000-4000-8000-000000000002', (select v::uuid from t.vars where k = 'a_col'))$q$);
select t.must_fail('B no mete el producto de A en una colección de A', $q$insert into public.product_collections (owner_id, product_id, collection_id) values ('aaaaaaaa-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001', (select v::uuid from t.vars where k = 'a_col'))$q$);
select t.affects('B no revoca la clave de A', $q$update public.api_keys set revoked_at = now() where owner_id = 'aaaaaaaa-0000-4000-8000-000000000001'$q$, 0);
select t.affects('B no pausa la API de A', $q$update public.api_settings set enabled = false where owner_id = 'aaaaaaaa-0000-4000-8000-000000000001'$q$, 0);
select t.must_fail('B no crea ajustes para A', $q$insert into public.api_settings (owner_id) values ('aaaaaaaa-0000-4000-8000-000000000001')$q$);
select t.must_fail('B no crea claves para A', $q$select public.create_api_key('x', '{read,write}', 30, 'aaaaaaaa-0000-4000-8000-000000000001')$q$);
select t.must_fail('B no cambia la huella de su clave', $q$update public.api_keys set key_hash = repeat('0', 64)$q$);
select t.must_fail('B no se da más permisos', $q$update public.api_keys set scopes = '{read,write}'$q$);
select t.must_fail('B no alarga la caducidad', $q$update public.api_keys set expires_at = now() + interval '100 years'$q$);
select t.must_fail('B no inserta claves a mano', $q$insert into public.api_keys (owner_id, key_hash, key_prefix) values ('bbbbbbbb-0000-4000-8000-000000000002', repeat('1', 64), 'mc_1111')$q$);
select t.must_fail('B no lee contadores', 'select * from public.api_usage');
select t.must_fail('B no borra bloqueos por IP', 'delete from public.api_auth_failures');
select t.must_fail('B no reinicia límites', 'delete from public.api_usage');
select t.must_fail('B no falsifica historial API', $q$insert into public.api_audit_log (owner_id, operation) values ('bbbbbbbb-0000-4000-8000-000000000002', 'falso')$q$);
select t.must_fail('B no borra historial API', 'delete from public.api_audit_log');
select t.must_fail('B no fabrica versiones', $q$insert into public.product_versions (product_id, owner_id, previous) values ('22222222-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002', '{}')$q$);
select t.must_fail('B no restaura versiones de A', $q$select public.restore_product_version((select v::bigint from t.vars where k = 'a_version'))$q$);
select t.must_fail('B no llama api_authenticate', $q$select * from public.api_authenticate(repeat('a', 64))$q$);
select t.must_fail('B no llama api_consume', $q$select public.api_consume('bbbbbbbb-0000-4000-8000-000000000002', 'minute', 60, 999, -999)$q$);
select t.must_fail('B no llama api_note_auth_failure', $q$select public.api_note_auth_failure('x')$q$);
select t.must_fail('B no llama api_cleanup', 'select public.api_cleanup()');
select t.must_fail('B no llama seed_user', $q$select public.seed_user('bbbbbbbb-0000-4000-8000-000000000002')$q$);
select t.must_fail('B no llama funciones de disparador', 'select public.keep_product_version()');
select t.must_fail('B no lee la configuración privada', 'select * from private.app_config');
select t.must_fail('B no abre el registro', 'update private.app_config set max_users = 20');
select t.must_fail('B no sube fotos a la carpeta de A', $q$insert into storage.objects (bucket_id, name) values ('product-images', 'aaaaaaaa-0000-4000-8000-000000000001/x/evil.jpg')$q$);
select t.must_fail('B no sube a la raíz del bucket', $q$insert into storage.objects (bucket_id, name) values ('product-images', 'evil.jpg')$q$);
select t.affects('B no borra fotos de A', $q$delete from storage.objects where name like 'aaaaaaaa%'$q$, 0);
insert into storage.objects (bucket_id, name) values ('product-images', 'bbbbbbbb-0000-4000-8000-000000000002/p/mia.jpg');
select t.must_fail('B no mueve su foto a la carpeta de A', $q$update storage.objects set name = 'aaaaaaaa-0000-4000-8000-000000000001/p/mia.jpg' where name like 'bbbbbbbb%'$q$);
select t.must_fail('B no usa ../ para salir de su carpeta', $q$insert into storage.objects (bucket_id, name) values ('product-images', '../aaaaaaaa-0000-4000-8000-000000000001/x.jpg')$q$);
select t.must_fail('B no crea usuarios', $q$insert into auth.users values (gen_random_uuid(), 'x@x.com')$q$);
-- Cobertura completa: cada tabla del usuario, leer / cambiar / borrar lo de A
select t.rows('B no lee ' || tb || ' de A', format('select * from public.%I where owner_id = %L', tb, 'aaaaaaaa-0000-4000-8000-000000000001'), 0)
  from unnest(array['categories','products','product_images','collections','product_collections','brand_logos','user_settings','api_keys','api_settings','api_audit_log','product_versions']) tb;
select t.affects('B no modifica ' || tb || ' de A', format('update public.%I set owner_id = owner_id where owner_id = %L', tb, 'aaaaaaaa-0000-4000-8000-000000000001'), 0)
  from unnest(array['categories','products','product_images','collections','product_collections','brand_logos','user_settings','api_settings']) tb;
select t.affects('B no borra ' || tb || ' de A', format('delete from public.%I where owner_id = %L', tb, 'aaaaaaaa-0000-4000-8000-000000000001'), 0)
  from unnest(array['categories','products','product_images','collections','product_collections','brand_logos','user_settings']) tb;
select t.must_fail('B no crea ' || tb || ' a nombre de A', format('insert into public.%I (owner_id) values (%L)', tb, 'aaaaaaaa-0000-4000-8000-000000000001'))
  from unnest(array['collections','brand_logos','user_settings']) tb;
reset request.jwt.claim.sub;
reset role;

-- =====================================================================
\echo '--- 3. Tu propia cuenta (A): lo que sí debe funcionar y lo que no ---'
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-0000-4000-8000-000000000001';
select t.rows('A ve su producto', 'select * from public.products', 1);
select t.rows('A ve su versión anterior', 'select * from public.product_versions', 1);
select t.rows('A ve su historial API', 'select * from public.api_audit_log', 1);
select t.rows('A ve su foto', 'select * from storage.objects', 1);
select t.affects('A revoca su clave', 'update public.api_keys set revoked_at = now()', 1);
select t.affects('A no puede reactivar una clave revocada (queda revocada)', 'update public.api_keys set revoked_at = null', 1);
select t.rows('...la clave sigue revocada', 'select * from public.api_keys where revoked_at is null', 0);
select t.must_fail('A no crea claves con permisos inventados', $q$select public.create_api_key('x', '{read,write,admin}', 30)$q$);
select t.must_fail('A no crea claves eternas', $q$select public.create_api_key('x', '{read,write}', 100000)$q$);
select t.must_fail('A no crea claves sin permisos', $q$select public.create_api_key('x', '{}', 30)$q$);
select t.rows('A crea una clave nueva de solo guardar', $q$select public.create_api_key('Nueva', '{write}', 30) as k$q$, 1);
select public.restore_product_version((select max(id) from public.product_versions));
select t.rows('...el nombre volvió', $q$select * from public.products where name = 'Polo secreto de A'$q$, 1);
select t.must_fail('A no puede poner límites absurdos', 'update public.api_settings set daily_create_limit = 1000000');
reset request.jwt.claim.sub;
reset role;

-- =====================================================================
\echo '--- 4. Registro cerrado ---'
insert into auth.users values ('cccccccc-0000-4000-8000-000000000003', 'tercero@ejemplo.com');  -- 3 de 3 permitidos (prueba)
select t.must_fail('no se admite un usuario más del máximo', $q$insert into auth.users values (gen_random_uuid(), 'intruso@ejemplo.com')$q$);
update private.app_config set max_users = 1;
select t.must_fail('con max_users = 1 nadie más se registra', $q$insert into auth.users values (gen_random_uuid(), 'otro@ejemplo.com')$q$);

-- =====================================================================
\echo '--- 5. Claves y límites (como el servidor) ---'
set role service_role;
select t.rows('una clave inventada no entra', $q$select * from public.api_authenticate(repeat('f', 64))$q$, 0);
select t.rows('la clave revocada de A ya no entra', $q$select * from public.api_authenticate((select key_hash from public.api_keys where owner_id = 'aaaaaaaa-0000-4000-8000-000000000001' and revoked_at is not null limit 1))$q$, 0);
reset role;
update public.api_keys set expires_at = now() - interval '1 day' where owner_id = 'bbbbbbbb-0000-4000-8000-000000000002';
set role service_role;
select t.rows('una clave caducada no entra', $q$select * from public.api_authenticate((select key_hash from public.api_keys where owner_id = 'bbbbbbbb-0000-4000-8000-000000000002'))$q$, 0);
reset role;

-- =====================================================================
\echo '--- 6. Integridad ---'
select t.rows('el producto de A sigue intacto', $q$select * from public.products where id = '11111111-0000-4000-8000-000000000001' and owner_id = 'aaaaaaaa-0000-4000-8000-000000000001' and deleted_at is null$q$, 1);
select t.rows('nadie dejó fotos en la carpeta de A', $q$select * from storage.objects where name like 'aaaaaaaa%'$q$, 1);
select t.rows('el logo SVG no está permitido', $q$select * from storage.buckets where 'image/svg+xml' = any(allowed_mime_types)$q$, 0);
select t.rows('anon sin permisos en ninguna tabla pública', $q$select * from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'public'$q$, 0);
select t.rows('anon sin permisos en ninguna función pública', $q$select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')$q$, 0);
select t.rows('toda tabla pública tiene RLS', $q$select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity$q$, 0);
select t.rows('funciones privilegiadas con search_path fijo', $q$select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','private') and p.prosecdef and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')$q$, 0);

\echo '--- 7. Inventario estilo Security Advisor ---'
select t.rows('no hay vistas (podrían saltarse RLS)', $q$select * from pg_views where schemaname in ('public','private')$q$, 0);
select t.rows('no hay vistas materializadas', $q$select * from pg_matviews where schemaname in ('public','private')$q$, 0);
select t.rows('ninguna extensión instalada en public', $q$select e.extname from pg_extension e join pg_namespace n on n.oid = e.extnamespace where n.nspname = 'public'$q$, 0);
select t.rows('la app solo puede llamar a create_api_key y restore_product_version', $q$select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','private') and has_function_privilege('authenticated', p.oid, 'execute') and p.proname not in ('create_api_key','restore_product_version')$q$, 0);
select t.rows('las funciones del servidor solo las ejecuta service_role', $q$select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'api\_%' and not has_function_privilege('service_role', p.oid, 'execute')$q$, 0);
select t.rows('todos los buckets son privados', $q$select * from storage.buckets where public$q$, 0);
select t.rows('todas las políticas son solo para usuarios con sesión', $q$select * from pg_policies where schemaname in ('public','storage') and roles <> '{authenticated}'$q$, 0);
select t.rows('la app solo escribe en sus propias tablas', $q$select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and (has_table_privilege('authenticated', c.oid, 'insert') or has_table_privilege('authenticated', c.oid, 'delete')) and c.relname not in ('categories','products','product_images','collections','product_collections','brand_logos','user_settings','api_settings')$q$, 0);
select t.rows('tablas con RLS pero sin políticas = solo servidor (esperadas)', $q$select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) and c.relname not in ('api_usage','api_auth_failures')$q$, 0);
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-0000-4000-8000-000000000001';
select t.must_fail('la app no puede consultar el espacio usado de nadie', $q$select public.api_storage_used('aaaaaaaa-0000-4000-8000-000000000001')$q$);
select t.must_fail('ni crear claves con permisos mezclados inventados', $q$select public.create_api_key('x', '{create,delete}', 30)$q$);
reset request.jwt.claim.sub;
reset role;
select t.rows('la clave mínima "solo guardar" se puede crear', $q$select public.create_api_key('Solo guardar', '{create}', 30, 'aaaaaaaa-0000-4000-8000-000000000001')$q$, 1);
insert into storage.objects (bucket_id, name, metadata) values ('product-images', 'aaaaaaaa-0000-4000-8000-000000000001/p/big.jpg', '{"size": 5000000}');
select t.rows('el espacio usado cuenta lo que hay de verdad en storage', $q$select 1 where public.api_storage_used('aaaaaaaa-0000-4000-8000-000000000001') = 5000000$q$, 1);
select t.rows('y no mezcla cuentas', $q$select 1 where public.api_storage_used('bbbbbbbb-0000-4000-8000-000000000002') = 0$q$, 1);

\echo '--- 9. Hallazgos del auditor independiente ---'
select t.must_fail('no se crean claves sin caducidad', $q$select public.create_api_key('eterna', '{read}', null, 'aaaaaaaa-0000-4000-8000-000000000001')$q$);
select t.must_fail('ni insertando una clave eterna directamente', $q$insert into public.api_keys (owner_id, key_hash, key_prefix) values ('aaaaaaaa-0000-4000-8000-000000000001', repeat('9', 64), 'mc_9999')$q$);
-- La API (origen chatgpt) intenta sepultar el original con 40 cambios seguidos
insert into public.products (id, owner_id, name, notes) values ('33333333-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', 'Original', 'nota buena');
update public.products set notes = 'editado por mí' where id = '33333333-0000-4000-8000-000000000003';
set request.headers = '{"x-catalog-source":"chatgpt"}';
do $$ begin for i in 1..40 loop update public.products set name = 'basura ' || i, notes = '' where id = '33333333-0000-4000-8000-000000000003'; end loop; end $$;
reset request.headers;
select t.rows('tras 40 cambios de la API sigue existiendo tu versión original', $q$select * from public.product_versions where product_id = '33333333-0000-4000-8000-000000000003' and previous->>'name' = 'Original'$q$, 2);
update public.product_versions set changed_at = now() - interval '60 days' where product_id = '33333333-0000-4000-8000-000000000003';
set request.headers = '{"x-catalog-source":"chatgpt"}';
update public.products set name = 'más basura' where id = '33333333-0000-4000-8000-000000000003';
reset request.headers;
select t.rows('pasados 30 días se conserva el estado que dejaste tú', $q$select * from public.product_versions where product_id = '33333333-0000-4000-8000-000000000003' and previous->>'notes' = 'editado por mí' and previous->>'name' = 'Original'$q$, 1);
select t.rows('...y la versión anterior a tu cambio', $q$select * from public.product_versions where product_id = '33333333-0000-4000-8000-000000000003' and previous->>'notes' = 'nota buena'$q$, 1);
select t.rows('...pero lo viejo intermedio sí se limpia (no crece sin fin)', $q$select 1 where (select count(*) from public.product_versions where product_id = '33333333-0000-4000-8000-000000000003') <= 33$q$, 1);

\echo '--- Resumen ---'
select count(*) filter (where ok) as pasan, count(*) filter (where not ok) as fallan from t.results;
select label, info from t.results where not ok;
do $$ begin
  if exists (select 1 from t.results where not ok) then raise exception 'HAY PRUEBAS FALLIDAS'; end if;
end $$;
