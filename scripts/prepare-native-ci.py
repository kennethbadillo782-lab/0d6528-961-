"""Credenciales efímeras para XCTest: solo memoria y secretos cifrados del repo privado."""
import subprocess,json,urllib.request
cli='.tools/supabase.exe'; ref='ddppztnamwmryhamezwy'; repo='kennethbadillo782-lab/MiCatalogo'
def tool(args):
 p=subprocess.run(args,capture_output=True,text=True)
 if p.returncode: raise SystemExit('Falló una operación de credenciales; salida sensible omitida.')
 return p.stdout
keys=json.loads(tool([cli,'projects','api-keys','--project-ref',ref,'--output','json']))
service=next(x['api_key'] for x in keys if x['name']=='service_role')
def api(path,body=None,method=None):
 req=urllib.request.Request('https://'+ref+'.supabase.co'+path,data=None if body is None else json.dumps(body).encode(),headers={'apikey':service,'Authorization':'Bearer '+service,'Content-Type':'application/json'},method=method)
 with urllib.request.urlopen(req,timeout=30) as f: return json.load(f)
users=api('/auth/v1/admin/users')['users'];assert len(users)==1 and users[0]['email']=='kennethbadillo782@gmail.com'
uid=users[0]['id']
# No envía email; credencial de un solo uso para el test nativo.
link=api('/auth/v1/admin/generate_link',{'type':'magiclink','email':users[0]['email']},'POST')
props=link.get('properties',link);token=props['hashed_token']
# Revocar únicamente claves anteriores de este workflow de pruebas.
tool([cli,'db','query','--linked','--project-ref',ref,"update public.api_keys set revoked_at=now() where label='Native CI integration' and revoked_at is null",'--output','json'])
raw=json.loads(tool([cli,'db','query','--linked','--project-ref',ref,"select public.create_api_key('Native CI integration',array['read','create'],1,'"+uid+"'::uuid) as key",'--output','json']))
key=raw['rows'][0]['key']
for name,value in [('MC_NATIVE_TOKEN_HASH',token),('MC_NATIVE_API_KEY',key)]:
 p=subprocess.run(['C:/Program Files/GitHub CLI/gh.exe','secret','set',name,'--repo',repo],input=value,text=True,capture_output=True)
 if p.returncode: raise SystemExit('No se pudo configurar el secreto cifrado de CI.')
print('Credencial de un solo uso y clave limitada configuradas en secretos cifrados de CI. No se guardaron en archivos ni logs.')
