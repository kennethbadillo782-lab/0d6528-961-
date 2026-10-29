// Pruebas HTTP contra Supabase COMPLETO local. No confundir con tests/e2e (doble).
import { randomBytes, createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const base = new URL(process.env.MC_TEST_URL || 'http://127.0.0.1:54321');
if (!['127.0.0.1', 'localhost'].includes(base.hostname) || base.username || base.password) throw Error('Solo se admite Supabase de pruebas en loopback.');
const service = process.env.MC_TEST_SERVICE_KEY;
const anon = process.env.MC_TEST_ANON_KEY;
if (!service || !anon) throw Error('Faltan credenciales de la instancia local; usa Test-Live.ps1.');
const results = [];
const trace = [];
const check = (c, name) => { results.push({ name, passed: !!c }); console.log(`${c ? 'PASS' : 'FAIL'} ${name}`); if (!c) throw Error(`Falló: ${name}`); };
async function http(path, { method = 'GET', token = service, apiKey = service, body, raw, headers = {} } = {}) {
  const response = await fetch(new URL(path, base), { method, signal: AbortSignal.timeout(60000), headers: { apikey: apiKey, authorization: `Bearer ${token}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }), ...headers }, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)) });
  let data; try { data = await response.json(); } catch { data = null; }
  const errorCode = data?.error_code ?? data?.code ?? data?.error;
  trace.push({ method, route: path.split('?')[0].replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/gi, '<id>'), status: response.status,
    ...(typeof errorCode === 'string' && /^[A-Za-z0-9_.-]{1,40}$/.test(errorCode) ? { errorCode } : {}) });
  return { status: response.status, data };
}
let access, owner, key, keyId, product;
const keyIds = [];
const productIds = new Set();
async function rest(path, options = {}) { return http('/rest/v1/' + path, { token: access, apiKey: anon, ...options }); }
async function api(path, options = {}) { return http('/functions/v1/catalog-api' + path, { token: anon, apiKey: anon, ...options, headers: { 'x-api-key': key, ...(options.headers || {}) } }); }
async function mint(scopes, label) {
  const result = await rest('rpc/create_api_key', { method: 'POST', body: { p_label: label, p_scopes: scopes, p_days: 1 } });
  check(result.status === 200 && /^mc_[0-9a-f]{48}$/.test(result.data), `Crear clave de prueba: ${label}`);
  const hash = createHash('sha256').update(result.data).digest('hex');
  const lookup = await rest(`api_keys?select=id&key_hash=eq.${hash}`);
  if (lookup.status !== 200 || lookup.data.length !== 1) throw Error('Falló: localizar clave temporal');
  keyIds.push(lookup.data[0].id);
  return { value: result.data, id: lookup.data[0].id };
}
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
  const signup = await http('/auth/v1/signup', { method: 'POST', apiKey: anon, token: anon, body: { email: 'blocked-signup@example.com', password } });
  check(signup.status >= 400 && signup.data?.error_code === 'signup_disabled', 'Registro público sigue cerrado con proveedor de email activo');
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
  keyIds.push(keyId);
  check((await api('/health')).status === 200, 'Health de Edge Function');
  check((await api('/products', { headers: { 'x-api-key': 'invalid' } })).status === 401, 'Clave inválida rechazada');
  check((await api('/categories')).status === 200, 'Categorías reales');
  const collection = await api('/collections', { method: 'POST', body: { name: 'Pruebas locales' } });
  check(collection.status === 201, 'Crear colección');
  check((await api('/collections')).status === 200, 'Consultar colecciones');
  const created = await api('/products', { method: 'POST', body: { name: `Prueba ${randomBytes(4).toString('hex')}`, category_key: 'otros', currency: 'USD', price_current: 12, collections: ['Pruebas locales'] } });
  check(created.status === 201 && !!created.data.product.id, 'Crear producto persistente');
  product = created.data.product.id;
  productIds.add(product);
  check((await api('/products')).status === 200, 'Listar productos');
  check((await api(`/products/${product}`)).status === 200, 'Consultar detalle');
  const search = await api('/products?q='+encodeURIComponent(created.data.product.name));
  check(search.status===200 && search.data.total===1 && search.data.products[0]?.id===product,'Búsqueda real conserva índices tras mover la extensión');
  check((await api(`/products/${product}`, { method: 'PATCH', body: { notes: 'ñ 中文 & < >' } })).status === 200, 'Editar caracteres especiales');
  check((await api(`/products/${product}/favorite`, { method: 'PUT', body: { is_favorite: true } })).status === 200, 'Marcar favorito');
  check((await api(`/products/${product}/collections`, { method: 'POST', body: { add: ['Lista principal'] } })).status === 200, 'Asociar colección');
  check((await api('/products/check-duplicate', { method: 'POST', body: { url: 'https://example.com/item?id=local' } })).status === 200, 'Consulta de duplicados');
  check((await api(`/products/${product}`, { method: 'PATCH', body: { original_url: 'https://example.com' } })).status === 403, 'API no cambia enlaces existentes');
  check((await api('/products', { method: 'POST', body: { name: 'invalid', price_current: -1 } })).status === 400, 'Datos inválidos rechazados');
  check((await api('/products', { method: 'DELETE' })).status === 405, 'No existe borrado por la API de ChatGPT');
  check((await api('/products', { method: 'POST', raw: 'name=test', headers: { 'content-type': 'application/x-www-form-urlencoded' } })).status === 415, 'Formulario web rechazado');
  const blockedImage = await api(`/products/${product}/images`, { method: 'POST', body: { images: ['http://169.254.169.254/x.jpg'] } });
  check(blockedImage.status === 200 && blockedImage.data.images_saved === 0, 'SSRF bloqueado en runtime real');
  const remoteImage = await api(`/products/${product}/images`, { method: 'POST', body: { images: ['https://cdn.shopify.com/static/shopify-favicon.png'] } });
  if (remoteImage.data?.images_saved !== 1) console.error('La foto pública permitida no se descargó; revisar DNS y registro de Edge Function.');
  check(remoteImage.status === 200 && remoteImage.data.images_saved === 1, 'Descarga real con DNS y dominio permitido');
  const image = await readFile(new URL('ios/FashionCatalog/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png', root));
  const objectPath = `${owner}/${product}/local-regression.png`;
  const upload = await http(`/storage/v1/object/product-images/${objectPath}`, { method: 'POST', token: access, apiKey: anon, raw: image, headers: { 'content-type': 'image/png' } });
  check([200,201].includes(upload.status), 'Storage privado acepta foto del dueño');
  check((await http(`/storage/v1/object/product-images/${objectPath}`, { token: anon, apiKey: anon })).status !== 200, 'Storage privado rechaza acceso anónimo');
  await http('/storage/v1/object/product-images', { method: 'DELETE', token: access, apiKey: anon, body: { prefixes: [objectPath] } });
  const fromDb = await rest(`products?id=eq.${product}&select=id,notes,is_favorite`);
  check(fromDb.status === 200 && fromDb.data[0]?.notes === 'ñ 中文 & < >' && fromDb.data[0]?.is_favorite, 'Otra conexión confirma persistencia real');
  await rest(`api_settings?owner_id=eq.${owner}`, { method:'PATCH', body:{enabled:false} });
  check((await api('/categories')).status === 403,'Pausa real bloquea acceso de la API');
  await rest(`api_settings?owner_id=eq.${owner}`, { method:'PATCH', body:{enabled:true} });
  check((await api('/categories')).status === 200,'Reactivación real restablece acceso');
  const createOnly = await mint(['create'],'solo guardar');
  const readOnly = await mint(['read'],'solo consultar');
  const expired = await mint(['read'],'caducidad');
  check((await api('/products',{headers:{'x-api-key':createOnly.value}})).status === 403,'Clave solo guardar no puede leer');
  const quietURL = `https://example.com/local-quiet?id=${randomBytes(6).toString('hex')}`;
  const quietBody = {name:'Prueba sin lectura',original_url:quietURL};
  const q1 = await api('/products',{method:'POST',headers:{'x-api-key':createOnly.value},body:quietBody});
  const q2 = await api('/products',{method:'POST',headers:{'x-api-key':createOnly.value},body:quietBody});
  check(q1.status === 202 && q2.status === 202 && JSON.stringify(q1.data) === JSON.stringify(q2.data),'Solo guardar responde igual ante creación y duplicado');
  const quietRows = await rest(`products?select=id&deleted_at=is.null&original_url=eq.${encodeURIComponent(quietURL)}`);
  for(const row of quietRows.data ?? []) productIds.add(row.id);
  check(quietRows.status === 200 && quietRows.data.length === 1,'Duplicado opaco no crea dos filas');
  check((await api('/products',{method:'POST',headers:{'x-api-key':readOnly.value},body:{name:'No debe crearse'}})).status === 403,'Clave solo consultar no escribe');
  check((await api('/products',{headers:{'x-api-key':readOnly.value}})).status === 200,'Clave solo consultar sí lee');
  const expiredUpdate = await http(`/rest/v1/api_keys?id=eq.${expired.id}`,{method:'PATCH',body:{expires_at:new Date(Date.now()-60000).toISOString()}});
  check(expiredUpdate.status === 204 && (await api('/categories',{headers:{'x-api-key':expired.value}})).status === 401,'Clave caducada rechazada en servidor real');
  const raceURL = `https://example.com/local-race?id=${randomBytes(6).toString('hex')}`;
  const race = await Promise.all(Array.from({length:6},()=>api('/products',{method:'POST',body:{name:'Prueba concurrente',original_url:raceURL}})));
  const raceRows = await rest(`products?select=id&deleted_at=is.null&original_url=eq.${encodeURIComponent(raceURL)}`);
  for(const row of raceRows.data ?? []) productIds.add(row.id);
  check(race.filter(r=>r.status===201).length === 1 && race.filter(r=>r.status===409).length === 5 && raceRows.data.length === 1,'Seis solicitudes simultáneas conservan un único producto');
  const spoofIds=[];
  for(const value of ['1.2.3.4','8.8.8.8']) {
    const spoof=await api('/products',{method:'POST',headers:{'x-forwarded-for':value},body:{name:'Prueba proxy local'}});
    check(spoof.status === 201,'Solicitud de diagnóstico de proxy recibida');
    spoofIds.push(spoof.data.product.id); productIds.add(spoof.data.product.id);
  }
  const hashes=await rest(`api_audit_log?select=ip_hash&operation=eq.create_product&product_id=in.(${spoofIds.join(',')})`);
  check(hashes.status===200 && hashes.data.length===2 && hashes.data[0].ip_hash===hashes.data[1].ip_hash,'Gateway local neutraliza la primera IP reenviada por el cliente');
  const removed = await rest(`products?id=eq.${product}`, { method: 'PATCH', body: { deleted_at: new Date().toISOString() } });
  check(removed.status === 204 && (await api(`/products/${product}`)).status === 404, 'Borrado suave desde sesión de app');
  const revoke = await rest(`api_keys?id=eq.${keyId}`, { method: 'PATCH', body: { revoked_at: new Date().toISOString() } });
  check(revoke.status === 204 && (await api('/products')).status === 401, 'Revocación inmediata real');
  check((await http('/auth/v1/logout', { method: 'POST', token: access, apiKey: anon })).status===204,'Cerrar sesión en Auth real');
  const loggedOutRefresh=await http('/auth/v1/token?grant_type=refresh_token',{method:'POST',apiKey:anon,token:anon,body:{refresh_token:refresh.data.refresh_token}});
  check(loggedOutRefresh.status>=400 && !loggedOutRefresh.data?.access_token,'Refresh de sesión cerrada rechazado');
} catch (e) {
  // No imprimir respuestas, cabeceras ni excepciones de red que puedan incluir datos.
  console.error(e.message?.startsWith('Falló:') ? e.message : 'No se completaron las pruebas reales. Revisa la instancia local.');
  process.exitCode = 1;
} finally {
  if (access && productIds.size) await rest(`products?id=in.(${[...productIds].join(',')})`, { method: 'PATCH', body: { deleted_at: new Date().toISOString() } }).catch(() => {});
  if (access && keyIds.length) await rest(`api_keys?id=in.(${keyIds.join(',')})`, { method: 'PATCH', body: { revoked_at: new Date().toISOString() } }).catch(() => {});
  await mkdir(new URL('reports/',root), { recursive: true });
  await writeFile(new URL('reports/live-tests.json',root), JSON.stringify({ at: new Date().toISOString(), environment: 'Supabase local real', results, trace, nativeAppTested: false },null,2));
}
