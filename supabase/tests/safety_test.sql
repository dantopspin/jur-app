-- Tests for the Safety screen tools (migration 20261023000021).
\set ON_ERROR_STOP on
\pset pager off
\pset tuples_only on
\pset format unaligned
set client_min_messages = warning;

create function pg_temp.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise warning 'ok - %', msg;
end $$;
grant execute on function pg_temp.ok(boolean, text) to public;

\set a '''5a000000-0000-0000-0000-000000000001'''
\set b '''5a000000-0000-0000-0000-000000000002'''
\set c '''5a000000-0000-0000-0000-000000000003'''
\set as_a 'reset role; set request.jwt.claim.sub = ''5a000000-0000-0000-0000-000000000001''; set role authenticated;'
\set as_b 'reset role; set request.jwt.claim.sub = ''5a000000-0000-0000-0000-000000000002''; set role authenticated;'
\set photo '''https://test.supabase.co/storage/v1/object/public/photos/'''
insert into auth.users (id) values (:a), (:b), (:c);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos) values
  (:a, 'Alma', '1995-01-01', 'woman', 'men', 'taraz', array[:photo || :a || '/1.jpg']),
  (:b, 'Berik', '1994-01-01', 'man', 'women', 'taraz', array[:photo || :b || '/1.jpg']),
  (:c, 'Chingis', '1993-01-01', 'man', 'women', 'taraz', array[:photo || :c || '/1.jpg']);

-- blocked list and unblock
:as_a
insert into blocks (blocker_id, blocked_id) values (auth.uid(), :c);
select pg_temp.ok((select jsonb_array_length(my_blocked()) = 1 and my_blocked()->0->>'name' = 'Chingis'), 'blocked people are listed with a name');
:as_b
select pg_temp.ok(jsonb_array_length(my_blocked()) = 0, 'only your own blocks');
:as_a
select unblock(:c);
select pg_temp.ok(jsonb_array_length(my_blocked()) = 0, 'unblock removes them');

-- upcoming accepted dates
reset role;
insert into swipes (swiper_id, target_id, kind) values (:a, :b, 'like');
:as_b
select swipe(:a, 'like')->>'match_id' as match \gset
select propose_date(:'match', 'running', now() + interval '1 day', 'Терренкур') ->>'message_id' as d1 \gset
select propose_date(:'match', 'padel', now() + interval '2 days', 'Padel Club') ->>'message_id' as d2 \gset
:as_a
select respond_date(:'d1', 'accepted');
select pg_temp.ok((select jsonb_array_length(my_upcoming_dates()) = 1
                     and my_upcoming_dates()->0->>'name' = 'Berik'
                     and my_upcoming_dates()->0->>'place' = 'Терренкур' from (select 1) x), 'an accepted date shows, with who and where');
:as_b
select pg_temp.ok(jsonb_array_length(my_upcoming_dates()) = 1 and my_upcoming_dates()->0->>'name' = 'Alma', '...for both people');
reset role;
update matches set unmatched_at = now() where id = :'match';
:as_a
select pg_temp.ok(jsonb_array_length(my_upcoming_dates()) = 0, 'not after an unmatch');
