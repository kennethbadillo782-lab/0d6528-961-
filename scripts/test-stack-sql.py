"""Regresión SQL en el stack LOCAL real. Fixtures y cambios dentro de BEGIN/ROLLBACK."""
from pathlib import Path
import json, re, subprocess
root=Path(__file__).resolve().parent.parent
docker=Path('C:/Program Files/Docker/Docker/resources/bin/docker.exe')
container='supabase_db_micatalogo-test'
source=(root/'backend/supabase/tests/sql/attack.sql').read_text(encoding='utf-8')
# Supabase real tiene más columnas en auth.users que el stub. No cambia la intención del ataque.
source=source.replace('insert into auth.users values','insert into auth.users (id,email) values')
# Preservar la cuenta ficticia local ya creada y permitir exactamente los tres fixtures.
source=source.replace('update private.app_config set max_users = 3;', 'update private.app_config set max_users = (select count(*) from auth.users) + 3;')
sql="BEGIN;\n"+source+"\nreset role; select 'STACK_RESULT|' || count(*) filter (where ok) || '|' || count(*) filter (where not ok) from t.results; ROLLBACK;\n"
result=subprocess.run([str(docker),'exec','-i',container,'psql','-X','-q','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],input=sql,encoding='utf-8',errors='replace',capture_output=True,timeout=120)
log=result.stdout+'\n'+result.stderr
log=re.sub(r'mc_[0-9a-f]{48}|eyJ[A-Za-z0-9_.-]+','[secreto omitido]',log)
(root/'reports/stack-sql.log').write_text(log,encoding='utf-8')
match=re.search(r'STACK_RESULT\|(\d+)\|(\d+)',log)
summary={'environment':'PostgreSQL del stack Supabase local real','rollback':True,'exitCode':result.returncode,'passed':result.returncode==0 and bool(match) and match[2]=='0'}
if match: summary.update(attacksPassed=int(match[1]),attacksFailed=int(match[2]))
(root/'reports/stack-sql.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
if not summary['passed']:
    print('FAIL regresión SQL del stack; revisar reports/stack-sql.log. Conexión cerrada y transacción revertida.')
    raise SystemExit(1)
print('PASS SQL del stack real: '+match[1]+' ataques; fixtures revertidos.')
