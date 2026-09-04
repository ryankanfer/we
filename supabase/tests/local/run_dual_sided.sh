#!/usr/bin/env bash
# Dual-sided lifecycle run against a throwaway PostgreSQL cluster.
#
# Starts a local cluster, applies the Supabase shim and every migration in
# supabase/migrations, then drives two authenticated sessions through the whole
# relationship lifecycle and prints a pass/fail report.
#
#   ./supabase/tests/local/run_dual_sided.sh
#
# Requires a PostgreSQL 16 server binary set (initdb, pg_ctl, psql) on the host.
# It does not touch any hosted project.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
BASE="${WE_TEST_CLUSTER:-/var/tmp/we-dual-sided}"
PORT="${WE_TEST_PORT:-5433}"
export PATH="$PGBIN:$PATH"

PG_USER="postgres"
RUN_AS=""
if [ "$(id -u)" -eq 0 ]; then
  RUN_AS="postgres"
fi

as_pg() {
  if [ -n "$RUN_AS" ]; then
    su "$RUN_AS" -c "PATH=$PGBIN:\$PATH $*"
  else
    bash -c "$*"
  fi
}

echo "==> fresh cluster at $BASE"
if [ -d "$BASE/data" ]; then
  as_pg "pg_ctl -D $BASE/data stop -m immediate" >/dev/null 2>&1 || true
fi
rm -rf "$BASE"
mkdir -p "$BASE/data" "$BASE/sock"
if [ -n "$RUN_AS" ]; then chown -R "$RUN_AS" "$BASE"; fi
as_pg "initdb -D $BASE/data -U $PG_USER --auth=trust" >/dev/null
as_pg "pg_ctl -D $BASE/data -o '-k $BASE/sock -p $PORT -c listen_addresses=' -l $BASE/log start" >/dev/null

cleanup() { as_pg "pg_ctl -D $BASE/data stop -m immediate" >/dev/null 2>&1 || true; }
trap cleanup EXIT

PSQL="psql -X -q -v ON_ERROR_STOP=1 -h $BASE/sock -p $PORT -U $PG_USER"

$PSQL -d postgres -c "create database we;" >/dev/null
echo "==> supabase shim"
$PSQL -d we -f "$ROOT/supabase/tests/local/supabase_shim.sql" >/dev/null

echo "==> migrations"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "    $(basename "$f")"
  $PSQL -d we -f "$f" >/dev/null
done

echo "==> dual-sided lifecycle"
$PSQL -d we -f "$ROOT/supabase/tests/local/dual_sided_lifecycle.sql" >/dev/null

$PSQL -d we -P pager=off -c "
  select case when passed then 'PASS' else 'FAIL' end as result,
         phase, name
  from wetest.results order by id;"

FAILED=$($PSQL -d we -At -c "select count(*) from wetest.results where not passed;")
TOTAL=$($PSQL -d we -At -c "select count(*) from wetest.results;")
if [ "$FAILED" != "0" ]; then
  $PSQL -d we -P pager=off -c "select phase, name, detail from wetest.results where not passed order by id;"
  echo "==> $FAILED of $TOTAL assertions FAILED"
  exit 1
fi
echo "==> all $TOTAL assertions passed"
