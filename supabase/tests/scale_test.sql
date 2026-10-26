-- Tests for scale and abuse limits (migration 20261026000023).
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

-- Runs a statement and says whether it was refused with rate_limited.
create function pg_temp.limited(sql text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  return sqlerrm = 'rate_limited';
end $$;
grant execute on function pg_temp.limited(text) to public;

\set a '''6a000000-0000-0000-0000-000000000001'''
\set b '''6a000000-0000-0000-0000-000000000002'''
\set c '''6a000000-0000-0000-0000-000000000003'''
\set as_a 'reset role; set request.jwt.claim.sub = ''6a000000-0000-0000-0000-000000000001''; set role authenticated;'
\set photo '''https://test.supabase.co/storage/v1/object/public/photos/'''
insert into auth.users (id) values (:a), (:b), (:c);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos) values
  (:a, 'Asel', '1995-01-01', 'woman', 'men', 'kokshetau', array[:photo || :a || '/1.jpg']),
  (:b, 'Bolat', '1994-01-01', 'man', 'women', 'kokshetau', array[:photo || :b || '/1.jpg']),
  (:c, 'Chokan', '1993-01-01', 'man', 'women', 'kokshetau', array[:photo || :c || '/1.jpg']);

-- Discover still finds people and still respects swipes and blocks
:as_a
select pg_temp.ok(jsonb_array_length(discover(20)) = 2, 'discover shows both people in the city');
select pg_temp.ok(discover_count() = 2, 'the live count agrees');
select swipe(:b, 'pass');
select pg_temp.ok(jsonb_array_length(discover(20)) = 1 and discover(20)->0->>'id' = :c, 'a passed person is gone');
insert into blocks (blocker_id, blocked_id) values (auth.uid(), :c);
select pg_temp.ok(jsonb_array_length(discover(20)) = 0, 'a blocked person is gone');

-- Travellers show up in the city they are visiting
reset role;
delete from blocks; delete from swipes;
update profiles set city = 'aktau', travel_city = 'kokshetau', travel_until = now() + interval '2 days' where id = :c;
:as_a
select pg_temp.ok(exists (select 1 from jsonb_array_elements(discover(20)) x where x->>'id' = :c), 'a traveller is found in the city they visit');
reset role;
update profiles set travel_until = now() - interval '1 minute' where id = :c;
:as_a
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(discover(20)) x where x->>'id' = :c), 'an expired trip no longer counts');

-- Discover itself is rate limited
reset role;
delete from rate_counters;
:as_a
select pg_temp.ok(not pg_temp.limited('select discover(20)'), 'normal use is fine');
reset role;
update rate_counters set n = 40 where key like 'discover:%';
:as_a
select pg_temp.ok(pg_temp.limited('select discover(20)'), 'the 41st Discover load in a minute is refused');

-- Messages are rate limited, but notes turned into first messages are not
reset role;
delete from rate_counters; delete from swipes; delete from matches;
update profiles set city = 'kokshetau', travel_city = null, travel_until = null where id = :c;
insert into swipes (swiper_id, target_id, kind, note) values (:b, :a, 'like', 'Пробежка в субботу?');
:as_a
select swipe(:b, 'like', 'Давай!')->>'match_id' as m \gset
select pg_temp.ok((select count(*) from messages where match_id = :'m') = 2, 'both notes became messages');
reset role;
select pg_temp.ok(not exists (select 1 from rate_counters where key like 'msg:%'), 'notes do not count towards the message limit');
:as_a
select pg_temp.ok(not pg_temp.limited(format('insert into messages (match_id, sender_id, body) values (%L, auth.uid(), %L)', :'m', 'привет')),
                  'a normal message goes through');
reset role;
update rate_counters set n = 30 where key like 'msg:m:%';
:as_a
select pg_temp.ok(pg_temp.limited(format('insert into messages (match_id, sender_id, body) values (%L, auth.uid(), %L)', :'m', 'спам')),
                  'the 31st message in a minute is refused');
reset role;
delete from rate_counters;
insert into rate_counters (key, window_start, n) values ('msg:d:' || :a, date_bin(interval '1 day', now(), timestamptz '2000-01-01'), 1500);
:as_a
select pg_temp.ok(pg_temp.limited(format('insert into messages (match_id, sender_id, body) values (%L, auth.uid(), %L)', :'m', 'ещё')),
                  'the daily message limit holds too');

-- Reports are limited
reset role;
delete from rate_counters;
:as_a
select pg_temp.ok(not pg_temp.limited(format('insert into reports (reporter_id, reported_id, reason) values (auth.uid(), %L, %L)', :b, 'scam')),
                  'a report goes through');
reset role;
update rate_counters set n = 5 where key like 'report:m:%';
:as_a
select pg_temp.ok(pg_temp.limited(format('insert into reports (reporter_id, reported_id, reason) values (auth.uid(), %L, %L)', :c, 'scam')),
                  'the 6th report in a minute is refused');

-- Old counters are pruned
reset role;
insert into rate_counters (key, window_start, n) values ('old', now() - interval '3 days', 1);
select prune_rate_counters();
select pg_temp.ok(not exists (select 1 from rate_counters where key = 'old'), 'counters older than two days are pruned');

-- Referral codes never collide
reset role;
update profiles set referral_code = 'TAKEN1' where id = :a;
insert into auth.users (id) values ('6a000000-0000-0000-0000-000000000004');
insert into profiles (id, name, birthdate, gender, interested_in, city, referral_code)
values ('6a000000-0000-0000-0000-000000000004', 'Dana', '1996-01-01', 'woman', 'men', 'kokshetau', 'TAKEN1');
select pg_temp.ok((select referral_code from profiles where id = '6a000000-0000-0000-0000-000000000004') <> 'TAKEN1',
                  'a taken code is replaced with a fresh one instead of failing the sign-up');
select pg_temp.ok((select referral_code ~ '^[A-HJ-NP-Z2-9]{6}$' from profiles where id = '6a000000-0000-0000-0000-000000000004'),
                  'new codes are six characters without 0, O, 1 or I');
