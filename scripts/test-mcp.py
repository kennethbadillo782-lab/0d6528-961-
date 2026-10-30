"""Pruebas reales de catalog-mcp contra el proyecto de pruebas. No imprime secretos.

Para llamar a /mcp sin el paso del correo, rota MCP_SIGNING_SECRET a un valor que solo
conoce este proceso, firma tokens de prueba y al final lo rota otra vez a un valor
aleatorio desconocido (esto desconecta cualquier ChatGPT ya conectado: habrá que reconectar).
Crea un producto ficticio "[Prueba MCP]" y luego lo marca como borrado.
"""
import base64, hashlib, hmac, json, os, secrets, subprocess, sys, tempfile, time, urllib.error, urllib.parse, urllib.request, uuid
sys.stdout.reconfigure(encoding='utf-8')
cli = os.path.abspath('.tools/supabase.exe'); ref = 'ddppztnamwmryhamezwy'
BASE = f'https://{ref}.supabase.co/functions/v1/catalog-mcp'; RESOURCE = BASE + '/mcp'
results = []
def check(name, ok, detail=''):
    results.append({'test': name, 'ok': bool(ok), 'detail': detail}); print(('PASA ' if ok else 'FALLA ') + name + (f' — {detail}' if detail and not ok else ''))
def tool(args):
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode: raise SystemExit('Falló una operación de Supabase; salida sensible omitida.')
    return p.stdout
def set_secret(value):
    fd, path = tempfile.mkstemp(suffix='.env')
    try:
        with os.fdopen(fd, 'w') as f: f.write(f'MCP_SIGNING_SECRET={value}\n')
        tool([cli, 'secrets', 'set', '--project-ref', ref, '--env-file', path])
    finally: os.remove(path)
def http(method, url, body=None, headers=None, form=None):
    data = None; h = dict(headers or {})
    if form is not None: data = urllib.parse.urlencode(form).encode(); h['content-type'] = 'application/x-www-form-urlencoded'
    elif body is not None: data = json.dumps(body).encode(); h['content-type'] = 'application/json'
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k): return None
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=90) as r: return r.status, dict(r.headers), r.read().decode()
    except urllib.error.HTTPError as e: return e.code, dict(e.headers), e.read().decode()
b64u = lambda b: base64.urlsafe_b64encode(b).decode().rstrip('=')
def sign(secret, payload):
    body = b64u(json.dumps(payload).encode()); return body + '.' + b64u(hmac.new(secret.encode(), body.encode(), hashlib.sha256).digest())

keys = json.loads(tool([cli, 'projects', 'api-keys', '--project-ref', ref, '--output', 'json']))
service = next(x['api_key'] for x in keys if x['name'] == 'service_role')
SH = {'apikey': service, 'Authorization': 'Bearer ' + service}
rest = f'https://{ref}.supabase.co/rest/v1'
_, _, u = http('GET', f'https://{ref}.supabase.co/auth/v1/admin/users', headers=SH)
owner = next(x['id'] for x in json.loads(u)['users'] if x['email'] == 'kennethbadillo782@gmail.com')

# --- Metadatos y rechazo sin autorización ---
s, _, b = http('GET', BASE + '/.well-known/oauth-protected-resource'); pr = json.loads(b)
check('metadatos de recurso protegido', s == 200 and pr['resource'] == RESOURCE and pr['authorization_servers'] == [BASE])
s, _, b = http('GET', BASE + '/.well-known/openid-configuration'); am = json.loads(b)
check('metadatos del servidor OAuth (S256, CIMD, iss)', s == 200 and am['issuer'] == BASE and 'S256' in am['code_challenge_methods_supported'] and am['client_id_metadata_document_supported'] and am['authorization_response_iss_parameter_supported'])
init = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'test', 'version': '1'}}}
s, h, _ = http('POST', RESOURCE, init)
check('sin token → 401 con WWW-Authenticate', s == 401 and 'resource_metadata' in {k.lower(): v for k, v in h.items()}.get('www-authenticate', ''))
s, _, _ = http('POST', RESOURCE, init, {'Authorization': 'Bearer abc.def'})
check('token inventado → 401', s == 401)

# --- Registro de cliente y autorización ---
s, _, b = http('POST', BASE + '/register', {'redirect_uris': ['https://evil.example/cb']})
check('registro con destino ajeno → 400', s == 400)
s, _, b = http('POST', BASE + '/register', {'redirect_uris': ['https://chatgpt.com/connector_platform_oauth_redirect']})
client = json.loads(b).get('client_id', ''); check('registro dinámico para ChatGPT', s == 201 and client)
verifier = secrets.token_urlsafe(48); challenge = b64u(hashlib.sha256(verifier.encode()).digest())
q = {'response_type': 'code', 'client_id': client, 'redirect_uri': 'https://chatgpt.com/connector_platform_oauth_redirect', 'code_challenge': challenge, 'code_challenge_method': 'S256', 'state': 'xyz', 'resource': RESOURCE}
# Una autorización válida envía un correo real al propietario: no se lanza aquí.
s, _, _ = http('GET', BASE + '/authorize?' + urllib.parse.urlencode({**q, 'redirect_uri': 'https://evil.example/cb'}))
check('autorización a destino ajeno → 400', s == 400)
s, _, _ = http('GET', BASE + '/authorize?' + urllib.parse.urlencode({**q, 'code_challenge_method': 'plain'}))
check('sin PKCE S256 → 400', s == 400)
s, _, _ = http('GET', BASE + '/authorize?' + urllib.parse.urlencode(dict(q, client_id='https://chatgpt.com/oauth/client.json', redirect_uri='https://evil.example/cb')))
check('cliente CIMD con destino ajeno → 400', s == 400)
s, _, b = http('GET', BASE + '/authorize?' + urllib.parse.urlencode(q))
req_token = urllib.parse.parse_qs(urllib.parse.urlparse(b[b.find('https://'):].split()[0]).query).get('req', [''])[0] if s == 200 else ''
check('autorización muestra la dirección de aprobación', s == 200 and 'AÑADIR productos' in b and req_token)
s, _, b = http('GET', BASE + '/authorize/approve?' + urllib.parse.urlencode({'req': req_token, 'pin': 'CODIGOFALSO1'}))
check('código de emparejamiento incorrecto → 403', s == 403)

# --- Tokens con firma temporal conocida ---
secret = secrets.token_urlsafe(48); set_secret(secret); time.sleep(20)
product_id = None
try:
    now = int(time.time())
    code = sign(secret, {'t': 'code', 'cid': client, 'ru': q['redirect_uri'], 'cc': challenge, 'sub': owner, 'exp': now + 120, 'j': str(uuid.uuid4())})
    tok = lambda v: http('POST', BASE + '/token', form={'grant_type': 'authorization_code', 'code': code, 'client_id': client, 'redirect_uri': q['redirect_uri'], 'code_verifier': v, 'resource': RESOURCE})
    s, _, _ = tok(secrets.token_urlsafe(48)); check('PKCE incorrecto → invalid_grant', s == 400)
    s, _, b = tok(verifier); t = json.loads(b); check('canje de código con PKCE', s == 200 and t.get('access_token') and t.get('refresh_token'))
    s, _, _ = tok(verifier); check('código reutilizado → rechazo', s == 400)
    s, _, b = http('POST', BASE + '/token', form={'grant_type': 'refresh_token', 'refresh_token': t['refresh_token'], 'resource': RESOURCE})
    check('renovación de token', s == 200 and json.loads(b).get('access_token'))
    wrong_aud = sign(secret, {'t': 'at', 'sub': owner, 'aud': 'https://otro', 'scope': 'catalog.create', 'exp': now + 600})
    s, _, _ = http('POST', RESOURCE, init, {'Authorization': 'Bearer ' + wrong_aud}); check('token de otra audiencia → 401', s == 401)
    A = {'Authorization': 'Bearer ' + t['access_token']}
    rpc = lambda m, p=None, i=2: http('POST', RESOURCE, {'jsonrpc': '2.0', 'id': i, 'method': m, **({'params': p} if p is not None else {})}, A)
    s, _, b = http('POST', RESOURCE, init, A); r = json.loads(b)
    check('initialize', s == 200 and r['result']['protocolVersion'] == '2025-11-25' and 'tools' in r['result']['capabilities'])
    s, _, _ = http('POST', RESOURCE, {'jsonrpc': '2.0', 'method': 'notifications/initialized'}, A); check('notificación → 202', s == 202)
    s, _, b = rpc('tools/list'); tools = json.loads(b)['result']['tools']; names = sorted(x['name'] for x in tools)
    check('tools/list muestra exactamente dos tools', names == ['createProduct', 'listCategories'], str(names))
    cp = next(x for x in tools if x['name'] == 'createProduct'); lc = next(x for x in tools if x['name'] == 'listCategories')
    check('anotaciones: lectura vs escritura', lc['annotations']['readOnlyHint'] is True and cp['annotations']['readOnlyHint'] is False)
    s, _, b = rpc('tools/call', {'name': 'listCategories', 'arguments': {}}); r = json.loads(b)['result']
    cats = r.get('structuredContent', {}).get('categories', [])
    check('listCategories devuelve claves reales', not r['isError'] and any(c.get('key') == 'carteras' for c in cats) and all(set(c) <= {'key', 'name', 'group_key', 'subcategories'} for c in cats))
    for bad, label in [({'name': 'x', 'price_current': -3}, 'precio negativo'), ({'name': 'x', 'original_url': 'javascript:alert(1)'}, 'URL javascript:'),
                       ({'name': 'x', 'owner_id': owner}, 'campo privilegiado'), ({'name': 'x', 'images': [{'url': 'file:///etc/passwd'}]}, 'imagen file://')]:
        s, _, b = rpc('tools/call', {'name': 'createProduct', 'arguments': bad}); r = json.loads(b)['result']
        check(f'rechazo: {label}', r['isError'] and r['content'][0]['text'].startswith('400'))
    for name in ['listProducts', 'deleteProduct', 'updateProduct']:
        s, _, b = rpc('tools/call', {'name': name, 'arguments': {}}); check(f'no existe {name}', 'error' in json.loads(b))
    marker = '[Prueba MCP] Cartera crossbody negra ' + str(uuid.uuid4())[:8]
    item = {'name': marker, 'category_key': 'carteras', 'price_current': 129, 'currency': 'CNY',
            'original_url': 'https://example.com/mcp-test/' + str(uuid.uuid4()), 'collections': ['Carteras'],
            'images': [{'url': 'https://cdn.shopify.com/static/shopify-favicon.png', 'kind': 'official'}], 'notes': 'Creado por la prueba automática del MCP'}
    s, _, b = rpc('tools/call', {'name': 'createProduct', 'arguments': item}); r = json.loads(b)['result']
    check('createProduct → Recibido', not r['isError'] and r['content'][0]['text'].startswith('Recibido'))
    s, _, b = http('GET', rest + '/products?select=id,name,category_key,price_current,currency&owner_id=eq.' + owner + '&name=eq.' + urllib.parse.quote(marker), headers=SH)
    rows = json.loads(b); product_id = rows[0]['id'] if rows else None
    check('el producto existe en la base', bool(rows) and rows[0]['category_key'] == 'carteras' and float(rows[0]['price_current']) == 129)
    if product_id:
        s, _, b = http('GET', rest + f'/product_collections?select=collection_id,collections(name)&product_id=eq.{product_id}', headers=SH)
        check('añadido a la colección Carteras', any((x.get('collections') or {}).get('name') == 'Carteras' for x in json.loads(b)))
    s, _, b = rpc('tools/call', {'name': 'createProduct', 'arguments': item}); r = json.loads(b)['result']
    check('duplicado → mismo Recibido, sin revelar nada', not r['isError'] and r['content'][0]['text'].startswith('Recibido'))
    # Pausa desde la app (api_settings.enabled) → 403
    s, _, b = http('GET', rest + f'/api_settings?select=enabled&owner_id=eq.{owner}', headers=SH); prev = json.loads(b)
    if prev: http('PATCH', rest + f'/api_settings?owner_id=eq.{owner}', {'enabled': False}, SH)
    else: http('POST', rest + '/api_settings', {'owner_id': owner, 'enabled': False}, SH)
    try:
        s, _, b = rpc('tools/call', {'name': 'createProduct', 'arguments': dict(item, name=marker + ' pausa', original_url=item['original_url'] + '-p')}); r = json.loads(b)['result']
        check('acceso pausado → 403', r['isError'] and r['content'][0]['text'].startswith('403'))
    finally:
        if prev: http('PATCH', rest + f'/api_settings?owner_id=eq.{owner}', {'enabled': prev[0]['enabled']}, SH)
        else: http('DELETE', rest + f'/api_settings?owner_id=eq.{owner}', headers=SH)
finally:
    set_secret(secrets.token_urlsafe(48))  # firma temporal descartada
    if product_id:
        http('PATCH', rest + f'/products?id=eq.{product_id}', {'deleted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}, SH)
os.makedirs('reports', exist_ok=True)
json.dump(results, open('reports/mcp-tests.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
failed = [r for r in results if not r['ok']]
print(f"\n{len(results) - len(failed)}/{len(results)} pruebas pasan")
sys.exit(1 if failed else 0)
