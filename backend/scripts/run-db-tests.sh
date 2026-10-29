#!/usr/bin/env bash
# Prueba las migraciones y los ataques a la base de datos en un Postgres LOCAL (nunca en producción).
# Uso: PGHOST=/ruta/socket PGUSER=postgres ./run-db-tests.sh
set -euo pipefail
cd "$(dirname "$0")/../supabase"
DB="mc_attack_$$"
psql -q -d postgres -c "create database $DB" >/dev/null
trap 'psql -q -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
psql -q -d postgres -c "alter database $DB set search_path = public, extensions" >/dev/null
run() { psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$1" >/dev/null 2>"$DB.err" || { cat "$DB.err"; rm -f "$DB.err"; exit 1; }; rm -f "$DB.err"; }
run tests/sql/supabase-stub.sql
for f in migrations/*.sql; do echo "Migración: $f"; run "$f"; done
set +e
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/sql/attack.sql > attack.out 2>&1
STATUS=$?
set -e
sed -nE 's/^psql:[^ ]+ (NOTICE|ERROR): +//p; /^--- /p' attack.out
rm -f attack.out
[ "$STATUS" = 0 ] || { echo "HAY FALLOS (código $STATUS)"; exit 1; }
echo "Base de datos: $(psql -X -At -d "$DB" -c "select count(*) from t.results where ok") ataques bloqueados, $(psql -X -At -d "$DB" -c "select count(*) from t.results where not ok") fallos"

echo "--- 8. Carrera contra el límite de uso (60 peticiones a la vez, máximo 20) ---"
psql -X -q -d "$DB" -c "insert into auth.users values ('dddddddd-0000-4000-8000-000000000004','r@x.com')" 2>/dev/null || psql -X -q -d "$DB" -c "update private.app_config set max_users=20; insert into auth.users values ('dddddddd-0000-4000-8000-000000000004','r@x.com')"
for i in $(seq 1 60); do
  psql -X -At -d "$DB" -c "set role service_role; select public.api_consume('dddddddd-0000-4000-8000-000000000004','race',3600,20,1)" &
done > race.out; wait
OK=$(grep -c '^t$' race.out || true); rm -f race.out
if [ "$OK" = "20" ]; then echo "PASS  exactamente 20 de 60 aceptadas"; else echo "FAIL  aceptadas: $OK"; exit 1; fi
echo "--- 9. Actualización desde la versión anterior (con una clave sin caducidad ya creada) ---"
UP="mc_upgrade_$$"
psql -q -d postgres -c "create database $UP" >/dev/null
psql -q -d postgres -c "alter database $UP set search_path = public, extensions" >/dev/null
psql -q -v ON_ERROR_STOP=1 -d "$UP" -f tests/sql/supabase-stub.sql >/dev/null 2>&1
for f in migrations/2026102800*.sql migrations/2026102801*.sql migrations/2026102802*.sql; do psql -q -v ON_ERROR_STOP=1 -d "$UP" -f "$f" >/dev/null 2>&1; done
psql -q -d "$UP" -c "insert into auth.users values ('eeeeeeee-0000-4000-8000-000000000005','u@x.com'); select public.create_api_key('vieja','{read,write}',null,'eeeeeeee-0000-4000-8000-000000000005');" >/dev/null
UPOK=1
for f in migrations/20261029*.sql; do psql -q -v ON_ERROR_STOP=1 -d "$UP" -f "$f" >/dev/null 2>&1 || UPOK=0; done
LEFT=$(psql -X -At -d "$UP" -c "select count(*) from public.api_keys where expires_at is null")
psql -q -d postgres -c "drop database $UP" >/dev/null
if [ "$UPOK" = 1 ] && [ "$LEFT" = 0 ]; then echo "PASS  la actualización funciona y la clave eterna queda con caducidad"; else echo "FAIL  actualización ($UPOK, $LEFT)"; exit 1; fi
echo "TODO OK"
