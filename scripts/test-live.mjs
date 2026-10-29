// Pruebas HTTP contra Supabase COMPLETO local. No confundir con tests/e2e (doble).
import { randomBytes } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const base = new URL(process.env.MC_TEST_URL || 'http://127.0.0.1:54321');
if (!['127.0.0.1', 'localhost'].includes(base.hostname) || base.username || base.password) throw Error('Solo se admite Supabase de pruebas en loopback.');
const service = process.env.MC_TEST_SERVICE_KEY;
const anon = process.env.MC_TEST_ANON_KEY;
if (!service || !anon) throw Error('Faltan credenciales de la instancia local; usa Test-Live.ps1.');
const results = [];
const check = (c, name) => { results.push({ name, passed: !!c }); console.log(`${c ? 'PASS' : 'FAIL'} ${name}`); if (!c) throw Error(`Falló: ${name}`); };
async function http(path, { method = 'GET', token = service, apiKey = service, body, raw, headers = {} } = {}) {
  const response = await fetch(new URL(path, base), { method, signal: AbortSignal.timeout(60000), headers: { apikey: apiKey, authorization: `Bearer ${token}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }), ...headers }, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)) });
  let data; try { data = await response.json(); } catch { data = null; }
  return { status: response.status, data };
}
let access, owner, key, keyId, product;
async function rest(path, options = {}) { return http('/rest/v1/' + path, { token: access, apiKey: anon, ...options }); }
async function api(path, options = {}) { return http('/functions/v1/catalog-api' + path, { token: anon, apiKey: anon, ...options, headers: { 'x-api-key': key, ...(options.headers || {}) } }); }
try {
  const email = 'micatalogo-test@example.invalid';
  const password = randomBytes(32).toString('hex');
  const users = await http('/auth/v1/admin/users');
  check(users.status === 200, 'Auth admin local responde');
  const existing = users.data.users.find(u => u.email === email);
  // La única cuenta local es ficticia. Nunca se toca una cuenta real.
  const user = await http(existing ? `/auth/v1/admin/users/${existing.id}` : '/auth/v1/admin/users', { method: existing ? 'PUT' : 'POST', body: { email, password, email_confirm: true } });
  check([200, 201].includes(user.status), 'Cuenta ficticia única preparada');
  owner = user.data.id;
  const login = await http('/auth/v1/token?grant_type=password', { method: 'POST', apiKey: anon, token: anon, body: { email, password } });
  check(login.status === 200 && !!login.data.access_token, 'Login real emite sesión');
  access = login.data.access_token;
  const refresh = await http('/auth/v1/token?grant_type=refresh_token', { method: 'POST', apiKey: anon, token: anon, body: { refresh_token: login.data.refresh_token } });
  check(refresh.status === 200, 'Renovación real de sesión');
  access = refresh.data.access_token;
  const noSession = await rest('products?select=id', { token: anon });
  check([401,403].includes(noSession.status), 'RLS rechaza lectura sin sesión');
  const createdKey = await rest('rpc/create_api_key', { method: 'POST', body: { p_label: 'Local regression', p_scopes: ['read','write'], p_days: 1 } });
  check(createdKey.status === 200 && /^mc_[0-9a-f]{48}$/.test(createdKey.data), 'RPC crea clave con caducidad');
  key = createdKey.data;
  const keys = await rest('api_keys?select=id,key_prefix&revoked_at=is.null');
  keyId = keys.data.find(k => key.startsWith(k.key_prefix)).id;
  check((await api('/health')).status === 200, 'Health de Edge Function');
  check((await api('/products', { headers: { 'x-api-key': 'invalid' } })).status === 401, 'Clave inválida rechazada');
  check((await api('/categories')).status === 200, 'Categorías reales');
  const collection = await api('/collections', { method: 'POST', body: { name: 'Pruebas locales' } });
  check(collection.status === 201, 'Crear colección');
  check((await api('/collections')).status === 200, 'Consultar colecciones');
  const created = await api('/products', { method: 'POST', body: { name: `Prueba ${randomBytes(4).toString('hex')}`, category_key: 'otros', currency: 'USD', price_current: 12, collections: ['Pruebas locales'] } });
  check(created.status === 201 && !!created.data.product.id, 'Crear producto persistente');
  product = created.data.product.id;
  check((await api('/products')).status === 200, 'Listar productos');
  check((await api(`/products/${product}`)).status === 200, 'Consultar detalle');
  check((await api(`/products/${product}`, { method: 'PATCH', body: { notes: 'ñ 中文 & < >' } })).status === 200, 'Editar caracteres especiales');
  check((await api(`/products/${product}/favorite`, { method: 'PUT', body: { is_favorite: true } })).status === 200, 'Marcar favorito');
  check((await api(`/products/${product}/collections`, { method: 'POST', body: { add: ['Lista principal'] } })).status === 200, 'Asociar colección');
  check((await api('/products/check-duplicate', { method: 'POST', body: { url: 'https://example.com/item?id=local' } })).status === 200, 'Consulta de duplicados');
  check((await api(`/products/${product}`, { method: 'PATCH', body: { original_url: 'https://example.com' } })).status === 403, 'API no cambia enlaces existentes');
  check((await api('/products', { method: 'POST', body: { name: 'invalid', price_current: -1 } })).status === 400, 'Datos inválidos rechazados');
  const blockedImage = await api(`/products/${product}/images`, { method: 'POST', body: { images: ['http://169.254.169.254/x.jpg'] } });
  check(blockedImage.status === 200 && blockedImage.data.images_saved === 0, 'SSRF bloqueado en runtime real');
  const image = await readFile(new URL('ios/FashionCatalog/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png', root));
  const objectPath = `${owner}/${product}/local-regression.png`;
  const upload = await http(`/storage/v1/object/product-images/${objectPath}`, { method: 'POST', token: access, apiKey: anon, raw: image, headers: { 'content-type': 'image/png' } });
  check([200,201].includes(upload.status), 'Storage privado acepta foto del dueño');
  check((await http(`/storage/v1/object/product-images/${objectPath}`, { token: anon, apiKey: anon })).status !== 200, 'Storage privado rechaza acceso anónimo');
  await http('/storage/v1/object/product-images', { method: 'DELETE', token: access, apiKey: anon, body: { prefixes: [objectPath] } });
  const fromDb = await rest(`products?id=eq.${product}&select=id,notes,is_favorite`);
  check(fromDb.status === 200 && fromDb.data[0]?.notes === 'ñ 中文 & < >' && fromDb.data[0]?.is_favorite, 'Otra conexión confirma persistencia real');
  const removed = await rest(`products?id=eq.${product}`, { method: 'PATCH', body: { deleted_at: new Date().toISOString() } });
  check(removed.status === 204 && (await api(`/products/${product}`)).status === 404, 'Borrado suave desde sesión de app');
  const revoke = await rest(`api_keys?id=eq.${keyId}`, { method: 'PATCH', body: { revoked_at: new Date().toISOString() } });
  check(revoke.status === 204 && (await api('/products')).status === 401, 'Revocación inmediata real');
  await http('/auth/v1/logout', { method: 'POST', token: access, apiKey: anon });
} catch (e) {
  // No imprimir respuestas, cabeceras ni excepciones de red que puedan incluir datos.
  console.error(e.message?.startsWith('Falló:') ? e.message : 'No se completaron las pruebas reales. Revisa la instancia local.');
  process.exitCode = 1;
} finally {
  if (access && product) await rest(`products?id=eq.${product}`, { method: 'PATCH', body: { deleted_at: new Date().toISOString() } }).catch(() => {});
  if (access && keyId) await rest(`api_keys?id=eq.${keyId}`, { method: 'PATCH', body: { revoked_at: new Date().toISOString() } }).catch(() => {});
  await mkdir(new URL('reports/',root), { recursive: true });
  await writeFile(new URL('reports/live-tests.json',root), JSON.stringify({ at: new Date().toISOString(), environment: 'Supabase local real', results, nativeAppTested: false },null,2));
}
