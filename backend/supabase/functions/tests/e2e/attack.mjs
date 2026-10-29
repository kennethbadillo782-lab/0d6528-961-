// =====================================================================
// Ataques contra la API real (catalog-api/index.ts) con una base de datos
// en memoria. Cada línea "ok" es un ataque que la API resistió.
// Ejecutar: node --experimental-strip-types --no-warnings --import ./register.mjs attack.mjs
// =====================================================================
import { DB, STORAGE, USAGE, sha } from './fake-supabase.mjs';

let handler;
// Todo lo que el servidor escriba en sus logs se guarda para comprobar que nunca contiene claves.
const LOGS = [];
for (const lvl of ['log', 'error', 'warn', 'info']) { const orig = console[lvl].bind(console); console[lvl] = (...a) => { LOGS.push(a.map(String).join(' ')); if (lvl !== 'error' && lvl !== 'warn') orig(...a); }; }
const OWNER = '11111111-1111-1111-1111-111111111111', OTHER = '22222222-2222-2222-2222-222222222222', THIRD = '33333333-3333-3333-3333-333333333333';
const KEY = 'mc_' + 'a'.repeat(48), OKEY = 'mc_' + 'c'.repeat(48), TKEY = 'mc_' + 'd'.repeat(48), REVOKED = 'mc_' + 'e'.repeat(48);
const CKEY = 'mc_' + '1'.repeat(48), WKEY = 'mc_' + '2'.repeat(48), XKEY = 'mc_' + '3'.repeat(48), EKEY = 'mc_' + '4'.repeat(48), BKEY = 'mc_' + '5'.repeat(48);
const FOURTH = '44444444-4444-4444-4444-444444444444';

// DNS falso: qué IP "tiene" cada host
const DNS = {
  'cdn.x.com': ['93.184.216.34'], 'img.alicdn.com': ['47.246.1.1'],
  'rebind.evil.com': ['127.0.0.1'], 'meta.evil.com': ['169.254.169.254'], 'mixed.evil.com': ['93.184.216.34', '10.0.0.5'],
  'v6.evil.com': ['::ffff:127.0.0.1'], 'nat64.evil.com': ['64:ff9b::a9fe:a9fe'],
};
// '*' = sin lista de sitios para la mayoría de pruebas; la lista por defecto se prueba aparte (sección 11b).
const ENV = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'srv', IMAGE_HOST_ALLOWLIST: '*' };
globalThis.Deno = {
  env: { get: (k) => ENV[k] },
  serve: (h) => { handler = h; },
  resolveDns: async (h, t) => (DNS[h] ?? []).filter((ip) => (t === 'A') === !ip.includes(':')),
};

// Servidor de imágenes falso. Registra cada host al que el servidor intenta conectarse.
const FETCHED = [];
const png = (n = 300) => new Uint8Array([0x89, 0x50, 0x4e, 0x47, ...Array(n).fill(1)]);
globalThis.fetch = async (u, opts = {}) => {
  const url = new URL(String(u));
  FETCHED.push(url.hostname);
  const p = url.pathname;
  if (p === '/fake.png' || p === '/a.jpg') return new Response(png(), { status: 200, headers: { 'content-type': 'image/png' } });
  if (p === '/to-meta') return new Response(null, { status: 302, headers: { location: 'http://169.254.169.254/latest/meta-data/' } });
  if (p === '/to-v6') return new Response(null, { status: 301, headers: { location: 'http://[::ffff:7f00:1]/x.png' } });
  if (p === '/to-file') return new Response(null, { status: 302, headers: { location: 'file:///etc/passwd' } });
  if (p === '/to-rebind') return new Response(null, { status: 302, headers: { location: 'https://rebind.evil.com/x.png' } });
  if (p === '/loop') return new Response(null, { status: 302, headers: { location: '/loop' } });
  if (p === '/svg') return new Response('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script>' + ' '.repeat(300) + '</svg>', { status: 200, headers: { 'content-type': 'image/svg+xml' } });
  if (p === '/html-as-png') return new Response('<html><script>alert(1)</script>' + 'x'.repeat(300), { status: 200, headers: { 'content-type': 'image/png' } });
  if (p === '/huge') return new Response(new ReadableStream({ pull(c) { c.enqueue(png(1024 * 1024)); } }), { status: 200, headers: { 'content-type': 'image/png' } });
  if (p === '/huge-declared') return new Response(png(), { status: 200, headers: { 'content-type': 'image/png', 'content-length': String(50 * 1024 * 1024) } });
  if (p === '/slow') return new Response(new ReadableStream({ start(c) { c.enqueue(png(10)); opts.signal?.addEventListener('abort', () => c.error(new Error('aborted'))); } }), { status: 200, headers: { 'content-type': 'image/png' } });
  return new Response('no', { status: 404 });
};

DB.api_keys.push(
  { id: 'k1', owner_id: OWNER, key_hash: sha(KEY), scopes: ['read', 'write'] },
  { id: 'k3', owner_id: OTHER, key_hash: sha(OKEY), scopes: ['read', 'write'] },
  { id: 'k4', owner_id: THIRD, key_hash: sha(TKEY), scopes: ['read', 'write'] },
  { id: 'k5', owner_id: OWNER, key_hash: sha(REVOKED), scopes: ['read', 'write'], revoked_at: '2026-01-01' },
  { id: 'k6', owner_id: OWNER, key_hash: sha(CKEY), scopes: ['create'] },
  { id: 'k7', owner_id: OWNER, key_hash: sha(WKEY), scopes: ['write'] },
  { id: 'k8', owner_id: OWNER, key_hash: sha(XKEY), scopes: ['read', 'write'] },
  { id: 'k9', owner_id: OWNER, key_hash: sha(EKEY), scopes: ['read', 'write'], expires_at: '2026-01-01T00:00:00Z' },
  { id: 'k10', owner_id: FOURTH, key_hash: sha(BKEY), scopes: ['read', 'write'] },
);
for (const o of [OWNER, OTHER, THIRD, FOURTH]) for (const k of ['camisas', 'carteras', 'otros']) DB.categories.push({ owner_id: o, key: k, deleted_at: null, sort_order: 0 });
DB.collections.push({ id: '0c0c0c0c-0000-4000-8000-000000000001', owner_id: OWNER, name: 'Lista principal', deleted_at: null });
DB.collections.push({ id: '0c0c0c0c-0000-4000-8000-000000000002', owner_id: OWNER, name: 'Regalos secretos', deleted_at: null });

await import('../../catalog-api/index.ts');
const base = 'https://p.supabase.co/functions/v1/catalog-api';
async function call(method, path, { key = KEY, body, ip = '1.2.3.4', ct = 'application/json', headers = {}, raw } = {}) {
  const h = { 'x-forwarded-for': ip, ...headers };
  if (key) h['x-api-key'] = key;
  if (body !== undefined || raw !== undefined) h['content-type'] = ct;
  const payload = raw !== undefined ? raw : body !== undefined ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined;
  const r = await handler(new Request(base + path, { method, headers: h, body: payload, duplex: 'half' }));
  const text = await r.text();
  let j; try { j = JSON.parse(text); } catch { j = { _raw: text }; }
  return { s: r.status, j, h: r.headers, text };
}
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else fail++; console.log((c ? 'ok  ' : 'FAIL') + ' - ' + m); };
const section = (t) => console.log('\n--- ' + t + ' ---');

// ---------------------------------------------------------------------
section('1. Autenticación');
ok((await call('GET', '/categories', { key: null })).s === 401, 'sin clave');
ok((await call('GET', '/categories', { key: '' })).s === 401, 'clave vacía');
ok((await call('GET', '/categories', { key: "mc_' or '1'='1" })).s === 401, 'inyección SQL en la clave');
ok((await call('GET', '/categories', { key: 'MC_' + 'A'.repeat(48) })).s === 401, 'clave en mayúsculas no es la misma');
ok((await call('GET', '/categories', { key: KEY.slice(0, -1) })).s === 401, 'clave recortada');
ok((await call('GET', '/categories', { key: KEY + '0' })).s === 401, 'clave alargada');
ok((await call('GET', '/categories', { key: REVOKED })).s === 401, 'clave revocada');
ok((await call('GET', '/categories?api_key=' + KEY, { key: null })).s === 401, 'clave en la URL no se acepta (no queda en logs)');
ok((await call('GET', '/categories', { key: null, headers: { authorization: 'Bearer eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x' } })).s === 401, 'JWT falsificado de "service_role" no sirve');
ok((await call('GET', '/categories', { key: null, headers: { authorization: 'Bearer ' + KEY } })).s === 200, 'tu clave también vale como Bearer');
ok((await call('GET', '/categories', { key: null, headers: { cookie: 'sb-access-token=abc' } })).s === 401, 'cookies ignoradas');

section('2. Fuerza bruta y bloqueo');
for (let i = 0; i < 26; i++) await call('GET', '/categories', { key: 'mc_' + String(i).padStart(48, '0'), ip: `${i}.${i}.${i}.${i}, 7.7.7.7` });
ok((await call('GET', '/categories', { key: 'mc_' + 'f'.repeat(48), ip: '200.1.1.1, 7.7.7.7' })).s === 429, 'cambiar la IP falsa del principio de x-forwarded-for no evita el bloqueo');
ok((await call('GET', '/categories', { ip: '200.1.1.1, 7.7.7.7' })).s === 200, 'tu clave sigue entrando desde esa IP');
let blockedGlobal = false;
for (let i = 0; i < 320 && !blockedGlobal; i++) {
  const r = await call('GET', '/categories', { key: 'mc_' + String(1000 + i).padStart(48, '0'), ip: `10.${i >> 8}.${i & 255}.9` });
  if (r.s === 429) blockedGlobal = true;
}
ok(blockedGlobal, 'atacante que rota IPs reales: freno global tras 300 fallos');
ok((await call('GET', '/categories', { ip: '55.55.55.55' })).s === 200, 'con el freno global activo, tu clave sigue funcionando');

section('3. Métodos y rutas');
for (const m of ['DELETE', 'OPTIONS', 'HEAD', 'TRACE', 'CONNECT'].filter((m) => m !== 'TRACE' && m !== 'CONNECT')) ok((await call(m, '/products')).s === 405, `${m} no permitido`);
ok((await call('GET', '/products/1%20or%201=1')).s === 400, 'id con inyección');
ok((await call('GET', "/products/11111111-1111-1111-1111-111111111111'--")).s === 400, 'id con comilla');
ok((await call('GET', '/products/%2e%2e%2f%2e%2e%2fapi_keys')).s === 400, 'recorrido de rutas codificado');
ok([400, 404].includes((await call('GET', '/api_keys')).s), 'no hay ruta a tablas internas');
ok((await call('GET', '/products?x=' + 'a'.repeat(5000))).s === 414, 'URL gigante');
const r500 = await call('GET', '/rpc/api_authenticate');
ok(r500.s === 404, 'no se puede llamar a funciones internas');

section('4. Cuerpos maliciosos');
ok((await call('POST', '/products', { body: [1, 2] })).s === 400, 'lista en vez de objeto');
ok((await call('POST', '/products', { raw: 'null' })).s === 400, 'null');
ok((await call('POST', '/products', { raw: '"texto"' })).s === 400, 'texto suelto');
ok((await call('POST', '/products', { raw: '{"name":"x"' })).s === 400, 'JSON cortado');
ok((await call('POST', '/products', { raw: new Uint8Array([0x7b, 0x22, 0x6e, 0x22, 0x3a, 0x22, 0xff, 0xfe, 0x22, 0x7d]) })).s === 400, 'bytes que no son UTF-8');
ok((await call('POST', '/products', { raw: 'x'.repeat(150_000) })).s === 413, 'cuerpo gigante');
ok((await call('POST', '/products', { raw: new ReadableStream({ pull(c) { c.enqueue(new Uint8Array(64 * 1024).fill(32)); } }) })).s === 413, 'cuerpo infinito (sin content-length) se corta');
ok((await call('POST', '/products', { body: { name: 'x' }, ct: 'text/plain' })).s === 415, 'content-type incorrecto (evita envíos desde formularios web)');
ok((await call('POST', '/products', { body: { name: 'x' }, ct: 'application/x-www-form-urlencoded' })).s === 415, 'formulario web');
const deep = '{"name":"x","attributes":' + '['.repeat(30000) + ']'.repeat(30000) + '}';
const rd = await call('POST', '/products', { raw: deep });
ok(rd.s === 400 || rd.s === 413, 'JSON anidado 30.000 niveles no tumba el servidor (' + rd.s + ')');
const pol = await call('POST', '/products', { raw: '{"name":"Proto","__proto__":{"isAdmin":true,"owner_id":"' + OTHER + '"},"constructor":{"prototype":{"polluted":true}},"attributes":{"__proto__":{"x":"1"},"constructor":"y","talla":"M"}}' });
ok(pol.s === 201, 'producto con __proto__ se crea sin efectos');
ok(({}).isAdmin === undefined && ({}).polluted === undefined && Object.prototype.owner_id === undefined, 'sin contaminación de prototipos');
const polP = DB.products.find((p) => p.name === 'Proto');
ok(polP && polP.owner_id === OWNER && JSON.stringify(polP.attributes) === '{"talla":"M"}', 'el dueño no cambia y los atributos peligrosos se descartan');
const sneaky = await call('POST', '/products', { body: { name: 'Campos internos', id: '99999999-9999-4999-8999-999999999999', owner_id: OTHER, source: 'app', created_at: '1999-01-01', deleted_at: '2020-01-01', normalized_url: 'x', search_text: 'x', is_builtin: true } });
const sp = DB.products.find((p) => p.name === 'Campos internos');
ok(sneaky.s === 201 && sp.id !== '99999999-9999-4999-8999-999999999999' && sp.owner_id === OWNER && sp.source === 'chatgpt' && sp.deleted_at === null, 'id, dueño, origen, fechas y borrado no se pueden fijar');

section('5. Validación de campos');
const bad = [
  [{ name: { $gt: '' } }, 'objeto como nombre (inyección NoSQL)'],
  [{ name: ['a', 'b'] }, 'lista como nombre'],
  [{ name: 'x', price_current: '1e400' }, 'precio infinito'],
  [{ name: 'x', price_current: 'NaN' }, 'precio NaN'],
  [{ name: 'x', price_current: -1 }, 'precio negativo'],
  [{ name: 'x', price_current: 1e12 }, 'precio absurdo'],
  [{ name: 'x', priority: 1.5 }, 'prioridad decimal'],
  [{ name: 'x', is_favorite: 'true' }, 'favorito como texto'],
  [{ name: 'x', status: 'admin' }, 'estado inventado'],
  [{ name: 'x', currency: 'BTC' }, 'moneda inventada'],
  [{ name: 'x', seller_rating: 99 }, 'valoración fuera de 0–5'],
  [{ name: 'x', category_key: "otros' or 1=1--" }, 'categoría con inyección'],
  [{ name: 'x', category_key: '../../etc' }, 'categoría con ruta'],
  [{ name: 'x'.repeat(301) }, 'nombre de más de 300'],
  [{ original_url: 'javascript:alert(document.cookie)' }, 'enlace javascript:'],
  [{ original_url: 'data:text/html,<script>alert(1)</script>' }, 'enlace data:'],
  [{ original_url: 'file:///etc/passwd' }, 'enlace file:'],
  [{ original_url: 'https://item.taobao.com@evil.com/login' }, 'enlace que finge ser Taobao (usuario@host)'],
  [{ original_url: 'https://evil .com/' }, 'enlace con espacios'],
  [{ name: 'x', agent_links: [{ name: 'Hipobuy', url: 'javascript:alert(1)' }] }, 'agente con javascript:'],
  [{ name: 'x', images: ['data:image/png;base64,AAAA'] }, 'foto data:'],
  [{ name: 'x', images: [{ url: 'https://cdn.x.com/fake.png', kind: 'admin' }] }, 'tipo de foto inventado'],
  [{ name: 'x', attributes: 'texto' }, 'atributos como texto'],
  [{ name: 'x', collections: 'Lista' }, 'colecciones como texto'],
  [{}, 'producto vacío'],
];
for (const [b, m] of bad) { const r = await call('POST', '/products', { body: b }); ok(r.s === 400, m + ' → 400'); }
const uni = await call('POST', '/products', { body: { name: 'Polo‮gpj.exe​\u0000 \uD800Moncler', notes: 'a b﻿' } });
const up = DB.products.find((p) => p.name?.startsWith('Polo'));
ok(uni.s === 201 && up.name === 'Pologpj.exe Moncler' && up.notes === 'ab', 'quita caracteres invisibles, de dirección, nulos y sustitutos sueltos: "' + up?.name + '"');
const many = await call('POST', '/products', { body: { name: 'Muchos', attributes: Object.fromEntries(Array.from({ length: 500 }, (_, i) => ['k' + i, 'v'])), agent_links: Array.from({ length: 500 }, (_, i) => ({ name: 'Otro', url: 'https://a.com/' + i })) } });
const mp = DB.products.find((p) => p.name === 'Muchos');
ok(many.s === 201 && Object.keys(mp.attributes).length === 30 && mp.agent_links.length === 10, 'listas enormes recortadas (30 atributos, 10 agentes)');

section('6. Búsqueda (inyección en filtros)');
for (const q of ['%', '_', '*', '%25', 'a,b', 'name.eq.x', 'or=(owner_id.neq.0)', "'; drop table products;--", '\\', '()', 'ñandú 中文']) {
  const r = await call('GET', '/products?q=' + encodeURIComponent(q));
  ok(r.s === 200 && r.j.products.every((p) => DB.products.find((x) => x.id === p.id)?.owner_id === OWNER), `q=${q} solo devuelve lo tuyo`);
}
ok((await call('GET', '/products?status=admin')).s === 400, 'estado inventado en el filtro → 400 (no error interno)');
ok((await call('GET', '/products?brand=*')).s === 200, 'comodín en marca no rompe');
for (const qs of ['limit=-5', 'limit=1e9', 'limit=abc', 'offset=-1', 'offset=1e15', 'limit=Infinity']) {
  const r = await call('GET', '/products?' + qs);
  ok(r.s === 200 && r.j.limit >= 1 && r.j.limit <= 50 && r.j.offset >= 0 && r.j.offset <= 10000, `paginación ${qs} acotada`);
}

section('7. Datos de otro usuario (IDOR)');
const mine = DB.products.find((p) => p.owner_id === OWNER);
ok((await call('GET', '/products/' + mine.id, { key: OKEY })).s === 404, 'ver tu producto');
ok((await call('PATCH', '/products/' + mine.id, { key: OKEY, body: { notes: 'hack' } })).s === 404, 'editar tu producto');
ok((await call('PUT', '/products/' + mine.id + '/favorite', { key: OKEY, body: { is_favorite: false } })).s === 404, 'cambiar tu favorito');
ok((await call('POST', '/products/' + mine.id + '/images', { key: OKEY, body: { images: ['https://cdn.x.com/fake.png'] } })).s === 404, 'añadir fotos a tu producto');
ok((await call('POST', '/products/' + mine.id + '/collections', { key: OKEY, body: { remove: ['Lista principal'] } })).s === 404, 'sacar tu producto de colecciones');
const otherCols = await call('GET', '/collections', { key: OKEY });
ok(!JSON.stringify(otherCols.j).includes('Regalos secretos'), 'no ve tus colecciones');
const op = await call('POST', '/products', { key: OKEY, body: { name: 'Producto del atacante', collections: ['0c0c0c0c-0000-4000-8000-000000000002'] } });
ok(op.s === 201 && !DB.product_collections.some((m) => m.collection_id === '0c0c0c0c-0000-4000-8000-000000000002' && m.owner_id === OTHER), 'no mete cosas en tu colección usando su id');
ok((await call('POST', '/products/check-duplicate', { key: OKEY, body: { url: 'https://www.hipobuy.com/p?url=https%3A%2F%2Fweidian.com%2Fitem.html%3FitemID%3D7' } })).j.duplicate === false, 'no puede saber qué enlaces guardaste');
ok((await call('GET', '/products', { key: OKEY })).j.products.every((p) => p.name === 'Producto del atacante'), 'su lista solo tiene lo suyo');
ok(mine.notes !== 'hack', 'tu producto intacto');

section('8. Enlaces guardados (contra páginas que manipulan a ChatGPT)');
for (const f of [{ original_url: 'https://evil.com' }, { agent_links: [{ name: 'Hipobuy', url: 'https://evil.com' }] }, { platform: 'Evil' }]) {
  ok((await call('PATCH', '/products/' + mine.id, { body: { ...f, notes: 'cambiado' } })).s === 403, 'PATCH ' + Object.keys(f)[0] + ' → 403');
}
ok(mine.notes !== 'cambiado', 'nada se aplicó a medias');
ok((await call('PATCH', '/products/' + mine.id, { body: { normalized_url: 'x', owner_id: OTHER } })).s === 400, 'campos internos en PATCH se ignoran (sin cambios → 400)');

section('9. SSRF: el servidor no visita tu red interna');
FETCHED.length = 0;
const ssrf = [
  'http://127.0.0.1/x.png', 'http://localhost/x.png', 'http://localhost./x.png', 'http://[::1]/x.png',
  'http://[::ffff:127.0.0.1]/x.png', 'http://[::ffff:169.254.169.254]/latest', 'http://[0:0:0:0:0:ffff:a9fe:a9fe]/',
  'http://[64:ff9b::a9fe:a9fe]/', 'http://[2002:a9fe:a9fe::]/', 'http://[fe80::1]/', 'http://[fd12::1]/',
  'http://169.254.169.254/latest/meta-data/', 'http://2130706433/', 'http://0x7f.1/', 'http://017700000001/',
  'http://10.0.0.1/', 'http://100.64.0.1/', 'http://192.168.1.1/router.png', 'http://0.0.0.0/',
  'http://db/x.png', 'http://kong:8000/x.png', 'http://supabase_kong_x/', 'http://metadata.google.internal./',
  'http://kubernetes.default.svc/', 'http://printer.local/x.png',
  'https://rebind.evil.com/x.png', 'https://meta.evil.com/x.png', 'https://mixed.evil.com/x.png', 'https://v6.evil.com/x.png',
  'https://nat64.evil.com/x.png', 'https://nodns.evil.com/x.png',
  'http://cdn.x.com:6379/fake.png', 'http://cdn.x.com:22/fake.png', 'https://user:pass@cdn.x.com/fake.png',
];
const sp0 = await call('POST', '/products', { key: TKEY, body: { name: 'SSRF' } });
const SID = sp0.j.product.id;
let savedSSRF = 0, rejected = 0;
const errsSSRF = [];
for (const u of ssrf) {
  USAGE.clear();
  const r = await call('POST', '/products/' + SID + '/images', { key: TKEY, body: { images: [u] } });
  savedSSRF += r.j.images_saved ?? 0;
  if (r.s === 400 || (r.j.image_errors ?? []).length === 1) rejected++;
  errsSSRF.push(r.j);
}
ok(savedSSRF === 0, `${ssrf.length} direcciones internas o trucadas: 0 descargadas`);
ok(rejected === ssrf.length, 'todas rechazadas (en la validación o antes de conectar)');
ok(FETCHED.length === 0, 'el servidor ni siquiera abrió conexión a ninguna (' + FETCHED.join(',') + ')');
USAGE.clear();
const redirs = await call('POST', '/products/' + SID + '/images', { key: TKEY, body: { images: ['https://cdn.x.com/to-meta', 'https://cdn.x.com/to-v6', 'https://cdn.x.com/to-file', 'https://cdn.x.com/to-rebind', 'https://cdn.x.com/loop'] } });
ok(redirs.j.images_saved === 0 && FETCHED.every((h) => h === 'cdn.x.com'), 'redirecciones hacia dentro, a file: o en bucle: bloqueadas tras cada salto');
const content = await call('POST', '/products/' + SID + '/images', { key: TKEY, body: { images: ['https://cdn.x.com/svg', 'https://cdn.x.com/html-as-png', 'https://cdn.x.com/huge', 'https://cdn.x.com/huge-declared'] } });
ok(content.j.images_saved === 0, 'SVG con script, HTML disfrazado de PNG y fotos gigantes: rechazados');
const msgs = [...errsSSRF, redirs.j, content.j].flatMap((r) => [...(r.image_errors ?? []).map((e) => e.error), ...(r.issues ?? [])]);
ok(msgs.length > 0 && !msgs.join('|').match(/169\.254|127\.0|10\.0\.0|ECONN|stack|\bat |TypeError/), 'los mensajes de error no revelan IPs internas ni detalles: ' + [...new Set(msgs)].slice(0, 6).join(' / '));
const t0 = Date.now();
const slow = await call('POST', '/products/' + SID + '/images', { key: TKEY, body: { images: ['https://cdn.x.com/slow'] } });
ok(slow.j.images_saved === 0 && Date.now() - t0 < 17000, `servidor lento que nunca termina: se corta a los ${Math.round((Date.now() - t0) / 1000)} s`);
const good = await call('POST', '/products/' + SID + '/images', { key: TKEY, body: { images: ['https://cdn.x.com/fake.png'] } });
ok(good.j.images_saved === 1, 'una foto real sí se guarda');

USAGE.clear();
section('10. Límites de abuso');
let hit = false;
const tp = DB.products.find((p) => p.owner_id === THIRD);
for (let i = 0; i < 45 && !hit; i++) if ((await call('PATCH', '/products/' + tp.id, { key: TKEY, body: { notes: 'n' + i } })).s === 429) hit = true;
ok(hit, 'más de 40 escrituras por minuto → 429');
DB.api_settings.push({ owner_id: OTHER, enabled: true, daily_create_limit: 3 });
let created = 0, limited = false;
for (let i = 0; i < 6; i++) { const r = await call('POST', '/products', { key: OKEY, body: { name: 'spam ' + i } }); if (r.s === 201) created++; if (r.s === 429) limited = true; }
ok(limited, 'límite diario de productos nuevos (' + created + ' creados antes del límite)');

USAGE.clear();
section('11. Permisos mínimos (clave "solo guardar" y "solo escribir")');
await call('POST', '/products', { key: KEY, body: { name: 'Base para permisos', original_url: 'https://weidian.com/item.html?itemID=31337' } });
const anyP = DB.products.find((p) => p.name === 'Base para permisos');
ok((await call('GET', '/products', { key: CKEY })).s === 403, 'solo guardar: no puede listar tu catálogo');
ok((await call('GET', '/products/' + anyP.id, { key: CKEY })).s === 403, 'solo guardar: no puede ver un producto');
ok((await call('PATCH', '/products/' + anyP.id, { key: CKEY, body: { notes: 'x' } })).s === 403, 'solo guardar: no puede editar lo existente');
ok((await call('PUT', '/products/' + anyP.id + '/favorite', { key: CKEY, body: { is_favorite: false } })).s === 403, 'solo guardar: no puede tocar favoritos');
ok((await call('POST', '/products/' + anyP.id + '/images', { key: CKEY, body: { images: ['https://cdn.x.com/fake.png'] } })).s === 403, 'solo guardar: no puede añadir fotos a lo existente');
ok((await call('POST', '/products/' + anyP.id + '/collections', { key: CKEY, body: { remove: ['Lista principal'] } })).s === 403, 'solo guardar: no puede sacar productos de colecciones');
ok((await call('GET', '/categories', { key: CKEY })).s === 200, 'solo guardar: sí ve las categorías (para guardar bien)');
ok((await call('GET', '/collections', { key: CKEY })).s === 403, 'solo guardar: no ve los nombres de tus colecciones');
const cnew = await call('POST', '/products', { key: CKEY, body: { name: 'Guardado con clave mínima', original_url: 'https://item.taobao.com/item.htm?id=424242' } });
ok(cnew.s === 202 && DB.products.some((p) => p.name === 'Guardado con clave mínima'), 'solo guardar: sí guarda productos nuevos');
const cdup = await call('POST', '/products', { key: CKEY, body: { name: 'otra vez', original_url: 'https://item.taobao.com/item.htm?id=424242' } });
ok(cdup.s === cnew.s && cdup.text === cnew.text, 'solo guardar: la respuesta es idéntica exista o no el producto (no se puede espiar)');
const cchk = await call('POST', '/products/check-duplicate', { key: CKEY, body: { url: anyP.original_url } });
ok(cchk.s === 403, 'solo guardar: no puede preguntar si un enlace está en tu catálogo');
// Oráculo del auditor: el servidor de fotos del atacante no debe notar diferencia entre "ya lo tienes" y "nuevo".
FETCHED.length = 0;
await call('POST', '/products', { key: CKEY, body: { name: 'sonda 1', original_url: 'https://item.taobao.com/item.htm?id=424242', images: ['https://cdn.x.com/probe-existe.png'] } });
await call('POST', '/products', { key: CKEY, body: { name: 'sonda 2', original_url: 'https://item.taobao.com/item.htm?id=999001', images: ['https://cdn.x.com/probe-nuevo.png'] } });
ok(FETCHED.filter((h) => h === 'cdn.x.com').length === 2, 'solo guardar: el servidor de fotos del atacante recibe la petición exista o no el producto (sin oráculo)');
const colQuiet1 = await call('POST', '/collections', { key: CKEY, body: { name: 'regalos secretos' } });
const colQuiet2 = await call('POST', '/collections', { key: CKEY, body: { name: 'colección que no existe xyz' } });
ok(colQuiet1.text === colQuiet2.text && colQuiet1.s === colQuiet2.s && !/Regalos/.test(colQuiet1.text), 'solo guardar: crear colección responde igual exista o no (no confirma nombres)');
const wpatch = await call('PATCH', '/products/' + anyP.id, { key: WKEY, body: { notes: 'nota desde clave sin lectura' } });
ok(wpatch.s === 200 && wpatch.j.ok === true && !('product' in wpatch.j), 'solo escribir: edita pero la respuesta no devuelve tus datos');
ok((await call('GET', '/products', { key: WKEY })).s === 403, 'solo escribir: no puede listar');
for (const [m, pth] of [['GET', '/'], ['POST', '/categories'], ['PUT', '/products'], ['PATCH', '/collections'], ['GET', '/products/' + anyP.id + '/images'], ['POST', '/products/x/y/z']]) {
  ok((await call(m, pth, m === 'GET' ? {} : { body: {} })).s === 404, `ruta inexistente ${m} ${pth} → 404`);
}

const racers = await Promise.all(Array.from({ length: 6 }, () => call('POST', '/products', { key: KEY, body: { name: 'Carrera', original_url: 'https://item.taobao.com/item.htm?id=777777' } })));
const alive = DB.products.filter((p) => p.normalized_url === 'item.taobao.com/item.htm?id=777777' && !p.deleted_at);
ok(alive.length === 1 && racers.filter((r) => r.s === 201).length === 1 && racers.filter((r) => r.s === 409).length === 5, `6 peticiones simultáneas con el mismo enlace: queda 1 producto (${alive.length}), 1×201 y 5×409`);

section('11b. Hallazgos del auditor independiente');
delete ENV.IMAGE_HOST_ALLOWLIST;
const defRead = await call('POST', '/products/' + anyP.id + '/images', { body: { images: ['https://cdn.x.com/a.jpg?d=nombres-de-tu-catalogo'] } });
ok(defRead.j.images_saved === 0 && /lista de sitios/.test(defRead.j.image_errors[0].error), 'por defecto, una clave que puede LEER solo descarga de sitios de fotos conocidos (no puede sacar datos a un dominio cualquiera)');
const defCreate = await call('POST', '/products', { key: CKEY, body: { name: 'Foto de tienda cualquiera', images: ['https://cdn.x.com/fake.png'] } });
ok(defCreate.s === 202 && DB.product_images.some((i) => i.source_url === 'https://cdn.x.com/fake.png' && i.owner_id === OWNER), 'una clave "solo guardar" sí descarga de cualquier tienda (no tiene datos que sacar)');
ENV.IMAGE_HOST_ALLOWLIST = '*';
USAGE.clear();
ok((await call('POST', '/products/' + anyP.id + '/images', { body: { images: ['https://evil.tld/a.jpg?d=' + 'x'.repeat(700)] } })).s === 400, 'enlaces de foto larguísimos (para sacar datos en la URL) → 400');
ENV.IMAGE_HOST_ALLOWLIST = 'alicdn';
const badList = await call('POST', '/products/' + anyP.id + '/images', { body: { images: ['https://cdn.x.com/fake.png?mal'] } });
ok(badList.j.images_saved === 0, 'una lista de sitios mal escrita no abre la puerta: no descarga nada');
ENV.IMAGE_HOST_ALLOWLIST = 'alicdn.com,geilicdn.com';
const allow1 = await call('POST', '/products/' + anyP.id + '/images', { body: { images: ['https://cdn.x.com/a.jpg?d=Base-para-permisos'] } });
const allow2 = await call('POST', '/products/' + anyP.id + '/images', { body: { images: ['https://img.alicdn.com/a.jpg'] } });
ENV.IMAGE_HOST_ALLOWLIST = '*';
ok(allow1.j.images_saved === 0 && /lista de sitios/.test(allow1.j.image_errors[0].error) && allow2.j.images_saved === 1, 'modo máximo: solo descarga de los sitios de fotos permitidos (un atacante no recibe nada)');
USAGE.clear();
let perProduct = 0, perLimited = false;
for (let i = 0; i < 25 && !perLimited; i++) { const r = await call('PATCH', '/products/' + anyP.id, { body: { notes: 'cambio ' + i } }); if (r.s === 200) perProduct++; if (r.s === 429) perLimited = true; }
ok(perLimited && perProduct <= 20, `un mismo producto admite como mucho 20 cambios al día desde la API (${perProduct})`);
USAGE.clear();
DB.api_settings.push({ owner_id: OWNER, enabled: true, daily_image_mb: 300, max_storage_mb: 2048 });
USAGE.set(OWNER + 'image-day', 10_000);
const noImg = await call('POST', '/products', { body: { name: 'Sin cupo de fotos', images: ['https://cdn.x.com/fake.png'] } });
const np = DB.products.find((p) => p.name === 'Sin cupo de fotos');
ok(noImg.s === 201 && noImg.j.images_saved === 0 && DB.api_audit_log.some((a) => a.operation === 'create_product' && a.product_id === np.id), 'si las fotos fallan, el producto queda registrado en el historial igualmente');
USAGE.clear();
const uniErr = await call('POST', '/products/' + anyP.id + '/images', { body: { images: ['https://cdn.x.com/svg', 'https://cdn.x.com/html-as-png', 'https://cdn.x.com/nada', 'https://cdn.x.com/huge-declared', 'https://cdn.x.com/to-meta'] } });
ok(new Set(uniErr.j.image_errors.map((e) => e.error)).size === 1, 'tras conectar, todos los fallos dan el mismo mensaje (no sirve para escanear): ' + uniErr.j.image_errors[0]?.error);

section('12. Revocar, pausar y caducar tienen efecto inmediato');
ok((await call('GET', '/categories', { key: XKEY })).s === 200, 'la clave funciona');
DB.api_keys.find((k) => k.id === 'k8').revoked_at = new Date().toISOString();
ok([401, 429].includes((await call('GET', '/categories', { key: XKEY })).s), 'revocada → la siguiente petición ya falla (sin caché; 429 si además ya hay bloqueo por intentos)');
ok([401, 429].includes((await call('GET', '/categories', { key: EKEY })).s), 'clave caducada → rechazada');
DB.api_settings.push({ owner_id: FOURTH, enabled: true });
ok((await call('GET', '/categories', { key: BKEY })).s === 200, 'acceso activo');
DB.api_settings.find((x) => x.owner_id === FOURTH).enabled = false;
ok((await call('POST', '/products', { key: BKEY, body: { name: 'durante la pausa' } })).s === 403 && !DB.products.some((p) => p.name === 'durante la pausa'), 'pausado → nada se guarda');
DB.api_settings.find((x) => x.owner_id === FOURTH).enabled = true;
ok((await call('GET', '/categories', { key: BKEY })).s === 200, 'al reactivar vuelve a funcionar');

section('13. Presupuesto de almacenamiento (costes)');
const bp = (await call('POST', '/products', { key: BKEY, body: { name: 'Presupuesto' } })).j.product.id;
DB.api_settings.find((x) => x.owner_id === FOURTH).max_storage_mb = 0;
const full = await call('POST', '/products/' + bp + '/images', { key: BKEY, body: { images: ['https://cdn.x.com/fake.png'] } });
ok(full.j.images_saved === 0 && /espacio máximo/.test(full.j.image_errors[0].error), 'espacio lleno → no se descarga ni se sube nada');
DB.api_settings.find((x) => x.owner_id === FOURTH).max_storage_mb = 2048;
DB.api_settings.find((x) => x.owner_id === FOURTH).daily_image_mb = 1;
const mb1 = await call('POST', '/products/' + bp + '/images', { key: BKEY, body: { images: ['https://cdn.x.com/fake.png?a', 'https://cdn.x.com/fake.png?b'] } });
ok(mb1.j.images_saved === 1 && /MB/.test(mb1.j.image_errors[0]?.error ?? ''), 'límite diario de MB: la segunda foto se rechaza');

section('14. Respuestas');
const hr = await call('GET', '/categories');
ok(!hr.h.get('access-control-allow-origin'), 'sin CORS: ninguna web puede leer tu API desde el navegador');
ok(hr.h.get('x-content-type-options') === 'nosniff' && hr.h.get('cache-control') === 'no-store', 'cabeceras de seguridad');
const saved = DB.categories; DB.categories = undefined;
const crash = await call('GET', '/categories');
DB.categories = saved;
ok(crash.s === 500 && crash.j.error === 'Error interno' && !/TypeError|undefined|at |\.ts/.test(crash.text), 'un fallo interno no revela detalles');
const detail = await call('GET', '/products/' + mine.id);
ok(!/owner_id|storage_path|normalized_url|search_text|key_hash|srv/.test(detail.text), 'el detalle no expone campos internos ni secretos');
ok(DB.api_audit_log.length > 0 && DB.api_audit_log.every((a) => a.ip_hash && !/\d+\.\d+\.\d+\.\d+/.test(a.ip_hash)), 'historial guarda la IP solo como huella');

section('15. Secretos');
const everything = JSON.stringify(DB) + LOGS.join('\n');
ok(![KEY, OKEY, TKEY, CKEY, WKEY, XKEY, BKEY, 'srv'].some((k) => everything.includes(k)), 'ninguna clave ni la clave de servicio aparece en la base de datos, historial ni logs');
ok(DB.api_keys.every((k) => /^[0-9a-f]{64}$/.test(k.key_hash)), 'solo se guardan huellas SHA-256 de las claves');

console.log(`\n${pass} ataques resistidos, ${fail} fallos`);
if (fail) process.exitCode = 1;
