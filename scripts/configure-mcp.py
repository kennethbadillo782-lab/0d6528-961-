"""Configura los secretos de catalog-mcp en Supabase. Nada se imprime ni se guarda en archivos del repo.

MCP_CATALOG_API_KEY: clave nueva de catalog-api con permiso SOLO 'create' (revoca la anterior de este uso).
MCP_SIGNING_SECRET:  aleatorio; cambiarlo revoca todas las conexiones de ChatGPT.
MCP_OWNER_ID:        UID del único usuario de Auth.
Uso: python -I scripts/configure-mcp.py [--rotate-signing]
"""
import json, os, secrets, subprocess, sys, tempfile, urllib.request
cli = os.path.abspath('.tools/supabase.exe'); ref = 'ddppztnamwmryhamezwy'
def tool(args, inp=None):
    p = subprocess.run(args, capture_output=True, text=True, input=inp)
    if p.returncode: raise SystemExit('Falló una operación de Supabase; salida sensible omitida.')
    return p.stdout
keys = json.loads(tool([cli, 'projects', 'api-keys', '--project-ref', ref, '--output', 'json']))
service = next(x['api_key'] for x in keys if x['name'] == 'service_role')
req = urllib.request.Request(f'https://{ref}.supabase.co/auth/v1/admin/users', headers={'apikey': service, 'Authorization': 'Bearer ' + service})
with urllib.request.urlopen(req, timeout=30) as f: users = json.load(f)['users']
real = [u for u in users if u['email'] == 'kennethbadillo782@gmail.com']
assert len(real) == 1, 'Usuario propietario no encontrado'
uid = real[0]['id']
tool([cli, 'db', 'query', '--linked', '--project-ref', ref, "update public.api_keys set revoked_at=now() where label='ChatGPT MCP (solo guardar)' and revoked_at is null", '--output', 'json'])
raw = json.loads(tool([cli, 'db', 'query', '--linked', '--project-ref', ref, "select public.create_api_key('ChatGPT MCP (solo guardar)',array['create'],1,'" + uid + "'::uuid) as key", '--output', 'json']))
values = {'MCP_CATALOG_API_KEY': raw['rows'][0]['key'], 'MCP_OWNER_ID': uid}
current = json.loads(tool([cli, 'secrets', 'list', '--project-ref', ref, '--output', 'json']))
if '--rotate-signing' in sys.argv or not any(s.get('name') == 'MCP_SIGNING_SECRET' for s in current):
    values['MCP_SIGNING_SECRET'] = secrets.token_urlsafe(48)
fd, path = tempfile.mkstemp(suffix='.env')
try:
    with os.fdopen(fd, 'w') as f: f.write(''.join(f'{k}={v}\n' for k, v in values.items()))
    tool([cli, 'secrets', 'set', '--project-ref', ref, '--env-file', path])
finally:
    os.remove(path)
print('Secretos de catalog-mcp configurados: ' + ', '.join(sorted(values)) + '. Valores no mostrados.')
