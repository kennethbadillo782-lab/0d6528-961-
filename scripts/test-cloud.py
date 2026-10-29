import subprocess,json,os
from pathlib import Path
r=subprocess.run(['.tools/supabase.exe','projects','api-keys','--project-ref','ddppztnamwmryhamezwy','--output','json'],capture_output=True,text=True)
if r.returncode: raise SystemExit('No se pudieron obtener claves en memoria')
d=json.loads(r.stdout)
if isinstance(d,dict): d=d.get('keys',d.get('api_keys',[]))
keys={v.get('name'):v.get('api_key') for v in d}
if not keys.get('anon') or not keys.get('service_role'): raise SystemExit('Claves requeridas no disponibles')
env=os.environ.copy();env.update(MC_TEST_ANON_KEY=keys['anon'],MC_TEST_SERVICE_KEY=keys['service_role'],MC_CLOUD_TEST_APPROVED='ddppztnamwmryhamezwy')
with Path('reports/cloud-console.log').open('w',encoding='utf-8') as f:
 p=subprocess.run(['node','scripts/test-cloud.mjs'],env=env,stdout=f,stderr=subprocess.STDOUT)
print(Path('reports/cloud-console.log').read_text(encoding='utf-8'))
raise SystemExit(p.returncode)
