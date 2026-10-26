#!/usr/bin/env bash
# Runs the migrations and behavioural tests on a throwaway local Postgres database.
# Usage: ./supabase/tests/run.sh   (needs psql and a local superuser; set PSQL to override)
set -euo pipefail
cd "$(dirname "$0")/.."
PSQL=${PSQL:-"psql -v ON_ERROR_STOP=1 -q"}
DB=qadam_test_$$
createdb "$DB"
trap 'dropdb --if-exists "$DB"' EXIT
$PSQL -d "$DB" -f tests/supabase_stub.sql
for f in migrations/*.sql; do $PSQL -d "$DB" -f "$f"; done
for t in tests/backend_test.sql tests/engagement_test.sql tests/dastarkhan_test.sql tests/clubs_test.sql tests/social_test.sql tests/launch_test.sql tests/fair_test.sql tests/events_badges_test.sql tests/native_push_test.sql tests/audit_test.sql tests/safety_test.sql tests/honest_push_test.sql tests/scale_test.sql; do $PSQL -d "$DB" -f "$t"; done
bash tests/audit_race.sh "$DB"
