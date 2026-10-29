"""PostgreSQL REAL con esquemas auth/storage de prueba; NO equivale a Supabase completo.
Solo conecta a un cluster dedicado en loopback. Nunca acepta una URL de producción.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse, json, os, secrets, subprocess, time

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--pg-bin', required=True, type=Path)
parser.add_argument('--port', type=int, default=55439)
args = parser.parse_args()
assert 1024 <= args.port <= 65535
bindir = args.pg_bin.resolve()
local = ROOT / '.local'
local.mkdir(exist_ok=True)
(ROOT / 'reports').mkdir(exist_ok=True)
flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
if os.name == 'nt':
    user = subprocess.check_output(['whoami'], text=True).strip()
    subprocess.run(['icacls', str(local), '/inheritance:r', '/grant:r', f'{user}:(OI)(CI)F'], check=True, capture_output=True, creationflags=flags)
data = local / 'pg-regression'
pwfile = local / 'pg-regression-password.txt'
env = os.environ.copy()
env.update(PGHOST='127.0.0.1', PGPORT=str(args.port), PGUSER='postgres', PGCLIENTENCODING='UTF8', PGCONNECT_TIMEOUT='10')
env.pop('PGSERVICE', None)
env.pop('PGOPTIONS', None)
def exe(name, *values, check=True):
    command = [str(bindir / (name + ('.exe' if os.name == 'nt' else ''))), *map(str,values)]
    if name == 'pg_ctl':
        # En Windows postgres hereda handles de pg_ctl: una PIPE puede no cerrar nunca.
        with (local / 'pg-control.log').open('w', encoding='utf-8') as log:
            proc = subprocess.run(command, env=env, stdout=log, stderr=log, creationflags=flags, timeout=90)
        proc.stdout = ''
        proc.stderr = (local / 'pg-control.log').read_text(encoding='utf-8',errors='replace')
    else:
        proc = subprocess.run(command, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', creationflags=flags, timeout=120)
    if check and proc.returncode:
        # No se imprimen argumentos ni el entorno; podrían contener secretos.
        raise RuntimeError(f'{name} falló (código {proc.returncode}): {proc.stderr[:1200]}')
    return proc
if not (data / 'PG_VERSION').exists():
    pwfile.write_text(secrets.token_hex(32), encoding='ascii')
    exe('initdb', '-D', data, '-U', 'postgres', '--auth=scram-sha-256', '--pwfile', pwfile, '--encoding=UTF8', '--locale=C')
env['PGPASSWORD'] = pwfile.read_text(encoding='ascii').strip()
started = False
names = []
def sql(db, statement):
    return exe('psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', statement).stdout.strip()
def file(db, path):
    return exe('psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', db, '-f', path)
def create_db(prefix):
    name = f'mc_{prefix}_{secrets.token_hex(5)}'
    sql('postgres', f'create database {name}')
    names.append(name)
    sql('postgres', f'alter database {name} set search_path = public, extensions')
    file(name, ROOT / 'backend/supabase/tests/sql/supabase-stub.sql')
    return name
summary = {'at': time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()), 'engine': 'PostgreSQL real', 'authStorage': 'test stubs', 'status': 'failed'}
try:
    status = exe('pg_ctl','-D',data,'status',check=False)
    if status.returncode != 0:
        exe('pg_ctl', '-D', data, '-l', local / 'postgres-regression.log', '-o', f'-h 127.0.0.1 -p {args.port}', '-w', 'start')
        started = True
    db = create_db('attack')
    migrations = sorted((ROOT / 'backend/supabase/migrations').glob('*.sql'))
    for migration in migrations:
        print('Migración:', migration.name, flush=True)
        file(db, migration)
    result = file(db, ROOT / 'backend/supabase/tests/sql/attack.sql')
    lines = [s for s in (result.stdout+'\n'+result.stderr).splitlines() if 'PASS ' in s or 'FAIL ' in s or s.startswith('---')]
    (ROOT / 'reports/database.log').write_text('\n'.join(lines), encoding='utf-8')
    counts = sql(db, 'select count(*) filter (where ok), count(*) filter (where not ok) from t.results').split('|')
    assert int(counts[1]) == 0, counts
    # Retención real: borra solo registros viejos y conserva los recientes.
    sql(db, """
      insert into public.api_usage values
        ('aaaaaaaa-0000-4000-8000-000000000001','cleanup-old',now()-interval '4 days',1),
        ('aaaaaaaa-0000-4000-8000-000000000001','cleanup-new',now(),1);
      insert into public.api_auth_failures values ('cleanup-old',now()-interval '2 days',1),('cleanup-new',now(),1);
      insert into public.api_audit_log(owner_id,operation,created_at) values
        ('aaaaaaaa-0000-4000-8000-000000000001','cleanup-old',now()-interval '366 days'),
        ('aaaaaaaa-0000-4000-8000-000000000001','cleanup-new',now());
      select public.api_cleanup();
    """)
    for table, field in [('api_usage','bucket'),('api_auth_failures','ip_hash'),('api_audit_log','operation')]:
        assert sql(db,f"select count(*) from public.{table} where {field}='cleanup-old'") == '0'
        assert sql(db,f"select count(*) from public.{table} where {field}='cleanup-new'") == '1'
    sql(db, "update private.app_config set max_users=20; insert into auth.users values ('dddddddd-0000-4000-8000-000000000004','race@example.invalid')")
    def consume(_):
        return sql(db, "set role service_role; select public.api_consume('dddddddd-0000-4000-8000-000000000004','race',3600,20,1)")
    with ThreadPoolExecutor(max_workers=60) as pool:
        responses = list(pool.map(consume, range(60)))
    accepted = sum(v.splitlines()[-1] == 't' for v in responses)
    assert accepted == 20, accepted
    upgrade = create_db('upgrade')
    for migration in migrations:
        if migration.name.startswith('20261028'): file(upgrade, migration)
    sql(upgrade, "insert into auth.users values ('eeeeeeee-0000-4000-8000-000000000005','upgrade@example.invalid'); select public.create_api_key('old','{read,write}',null,'eeeeeeee-0000-4000-8000-000000000005') is not null")
    for migration in migrations:
        if not migration.name.startswith('20261028'): file(upgrade, migration)
    assert sql(upgrade,'select count(*) from public.api_keys where expires_at is null') == '0'
    summary.update(status='passed', version=sql(db,'select version()'), attacksPassed=int(counts[0]), attacksFailed=int(counts[1]), concurrency={'requests':60,'accepted':accepted}, upgrade='passed', cleanupRetention='passed')
    print(f'PASS PostgreSQL: {counts[0]} ataques; carrera 20/60; actualización correcta.', flush=True)
finally:
    for name in names:
        assert name.startswith(('mc_attack_', 'mc_upgrade_'))
        try: sql('postgres',f'drop database if exists {name}')
        except Exception: pass
    if started: exe('pg_ctl','-D',data,'-m','fast','-w','stop',check=False)
    (ROOT / 'reports/database.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
