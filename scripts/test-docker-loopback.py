"""Prueba el lanzador contra Docker real, con contenedores efímeros sin secretos."""
from pathlib import Path
import json, subprocess
root = Path(__file__).resolve().parent.parent
shim = root / '.tools/loopback/docker.exe'
image = 'public.ecr.aws/supabase/gotrue:v2.197.0'
results = []
def check(value, name):
    results.append({'name':name,'passed':bool(value)})
    print(('PASS ' if value else 'FAIL ')+name,flush=True)
    assert value, name
def call(*args, data=None):
    return subprocess.run([str(shim),*args],input=data,capture_output=True,timeout=60)
name = 'supabase_binding_probe_micatalogo-test'
try:
    denied = call('create','--name',name,'-p','0.0.0.0:18439:9999',image)
    check(denied.returncode == 125,'Rechaza publicar este proyecto en todas las interfaces')
    created = call('run','--rm','-d','--name',name,'--network','micatalogo-local','-p','18439:9999','--entrypoint','/bin/sh',image,'-c','sleep 120')
    check(created.returncode == 0,'Crea contenedor efímero con puerto de prueba')
    ports = call('port',name)
    check(ports.returncode == 0 and b'127.0.0.1:18439' in ports.stdout and b'0.0.0.0' not in ports.stdout,'Docker confirma publicación solo en loopback')
    binary = bytes(range(256))*128
    piped = call('exec','-i',name,'/bin/sh','-c','cat',data=binary)
    check(piped.returncode == 0 and piped.stdout == binary,'Conserva stdin/stdout binarios sin cambios')
    text = 'test with spaces "quotes" and \\slashes\\'
    quoted = call('exec',name,'/bin/sh','-c','printf %s "$1"','sh',text)
    check(quoted.returncode == 0 and quoted.stdout.decode() == text,'Conserva argumentos con espacios, comillas y barras')
finally:
    call('stop',name)
    (root/'reports/docker-loopback-tests.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
