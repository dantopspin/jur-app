#!/usr/bin/env bash
# Two people like each other at the same moment (migration 20, fix 1).
# Session A likes inside an open transaction; session B likes B→A meanwhile; then A commits.
# Before the fix B didn't wait, neither saw the other's like, and no match was made.
# Usage: audit_race.sh <database>   (run.sh calls it after the SQL tests)
set -euo pipefail
DB=$1
PSQL=${PSQL_RAW:-"psql -X -q -At"}
A='ad200000-0000-0000-0000-000000000001'; B='ad200000-0000-0000-0000-000000000002'
photo() { echo "array['https://test.supabase.co/storage/v1/object/public/photos/$1/1.jpg']"; }
$PSQL -d "$DB" -c "insert into auth.users (id) values ('$A'), ('$B');
  insert into profiles (id, name, birthdate, gender, interested_in, city, photos, last_like_push_at) values
  ('$A', 'Race A', '1995-01-01', 'woman', 'men', 'kyzylorda', $(photo $A), now()),
  ('$B', 'Race B', '1994-01-01', 'man', 'women', 'kyzylorda', $(photo $B), now());" >/dev/null

dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
mkfifo "$dir/a"
$PSQL -d "$DB" < "$dir/a" > "$dir/a.out" 2>&1 &
exec 7>"$dir/a"
echo "begin; set local request.jwt.claim.sub = '$A'; set local role authenticated; select swipe('$B', 'like')->>'ok';" >&7
sleep 0.5
# B's like runs while A's is still open. With the fix it waits for A, so give it time.
( $PSQL -d "$DB" -c "set request.jwt.claim.sub = '$B'" -c "set role authenticated" -c "select swipe('$A', 'like')->>'match_id'" > "$dir/b.out" 2>&1 ) &
bpid=$!
sleep 0.5
echo "commit;" >&7; exec 7>&-
wait "$bpid"; wait

n=$($PSQL -d "$DB" -c "select count(*) from matches where user_a = least('$A'::uuid, '$B'::uuid) and user_b = greatest('$A'::uuid, '$B'::uuid)")
if [ "$n" = 1 ] && grep -qE '^[0-9a-f-]{36}$' "$dir/b.out"; then
  echo "ok - two simultaneous likes make exactly one match (the second swipe sees the first)"
else
  echo "FAIL: simultaneous likes made $n matches; B said: $(cat "$dir/b.out")"; exit 1
fi
