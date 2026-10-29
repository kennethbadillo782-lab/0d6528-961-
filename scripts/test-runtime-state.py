"""Verifica cron real dentro del stack de pruebas, sin secretos ni conexiones remotas."""
from pathlib import Path
import json, subprocess, time
root=Path(__file__).resolve().parent.parent
docker='C:/Program Files/Docker/Docker/resources/bin/docker.exe'
container='supabase_db_micatalogo-test'
def sql(text):
    result=subprocess.run([docker,'exec','-i',container,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],input=text,encoding='utf-8',capture_output=True,timeout=15)
    if result.returncode: raise RuntimeError('Falló la consulta de verificación de cron.')
    return result.stdout.strip()
results={}
job=None
try:
    assert sql("select count(*) from cron.job where jobname='mi-catalogo-api-cleanup' and schedule='17 4 * * *' and active")=='1'
    results['dailyJobActive']=True
    sql("insert into public.api_usage(owner_id,bucket,window_start,count) select id,'cron-regression-old',now()-interval '4 days',1 from auth.users limit 1")
    assert sql("select count(*) from public.api_usage where bucket='cron-regression-old'")=='1'
    job=sql("select cron.schedule('mi-catalogo-regression-cleanup','5 seconds','select public.api_cleanup()')")
    assert job.isdecimal()
    deadline=time.monotonic()+40
    while time.monotonic()<deadline:
        if sql("select count(*) from public.api_usage where bucket='cron-regression-old'")=='0': break
        time.sleep(2)
    else: raise RuntimeError('Cron no ejecutó la limpieza dentro del plazo de prueba.')
    results['scheduledCleanupExecuted']=True
    results['status']='passed'
    print('PASS cron: trabajo diario activo y ejecución real de limpieza comprobada.',flush=True)
finally:
    if job and job.isdecimal(): sql('select cron.unschedule('+job+')')
    sql("delete from public.api_usage where bucket='cron-regression-old'")
    (root/'reports/runtime-state.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
