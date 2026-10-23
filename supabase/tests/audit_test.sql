-- Tests for the fixes in migration 20261023000020_audit_fixes.sql (logic audit, 23 Oct 2026).
-- The race between two simultaneous likes needs two sessions: see audit_race.sh.
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

-- In Taraz: women w1, w2; men m1, m2, m3; a host h; strangers s1..s3.
\set w1 '''ad000000-0000-0000-0000-000000000001'''
\set w2 '''ad000000-0000-0000-0000-000000000002'''
\set m1 '''ad000000-0000-0000-0000-000000000003'''
\set m2 '''ad000000-0000-0000-0000-000000000004'''
\set m3 '''ad000000-0000-0000-0000-000000000005'''
\set h  '''ad000000-0000-0000-0000-000000000006'''
\set s1 '''ad000000-0000-0000-0000-000000000007'''
\set s2 '''ad000000-0000-0000-0000-000000000008'''
\set s3 '''ad000000-0000-0000-0000-000000000009'''
\set as_w1 'reset role; set request.jwt.claim.sub = ''ad000000-0000-0000-0000-000000000001''; set role authenticated;'
\set as_w2 'reset role; set request.jwt.claim.sub = ''ad000000-0000-0000-0000-000000000002''; set role authenticated;'
\set as_m1 'reset role; set request.jwt.claim.sub = ''ad000000-0000-0000-0000-000000000003''; set role authenticated;'
\set as_m2 'reset role; set request.jwt.claim.sub = ''ad000000-0000-0000-0000-000000000004''; set role authenticated;'
\set as_m3 'reset role; set request.jwt.claim.sub = ''ad000000-0000-0000-0000-000000000005''; set role authenticated;'
\set as_h  'reset role; set request.jwt.claim.sub = ''ad000000-0000-0000-0000-000000000006''; set role authenticated;'
\set as_s1 'reset role; set request.jwt.claim.sub = ''ad000000-0000-0000-0000-000000000007''; set role authenticated;'
\set photo '''https://test.supabase.co/storage/v1/object/public/photos/'''

insert into auth.users (id, email) select ('ad000000-0000-0000-0000-00000000000' || i)::uuid, 'audit' || i || '@example.com'
  from generate_series(1, 9) i;
insert into city_launch (city) values ('taraz'), ('turkistan') on conflict do nothing;
insert into profiles (id, name, birthdate, gender, interested_in, city, photos)
select ('ad000000-0000-0000-0000-00000000000' || i)::uuid,
       (array['W1','W2','M1','M2','M3','Host','S1','S2','S3'])[i], '1995-01-01',
       case when i <= 2 then 'woman' else 'man' end, case when i <= 2 then 'men' else 'women' end, 'taraz',
       array[:photo || ('ad000000-0000-0000-0000-00000000000' || i) || '/1.jpg']
  from generate_series(1, 9) i;
update profiles set is_host = true where id = :h;  -- an approved host, so tests can move start times
insert into events (id, host_id, city, sport_code, title, meeting_point, starts_at, capacity) values
  ('ad100000-0000-0000-0000-000000000001', :h, 'taraz', 'running', 'Morning run', 'Park', now() + interval '5 minutes', 30),
  ('ad100000-0000-0000-0000-000000000002', :h, 'taraz', 'running', 'Small hike', 'Gate', now() + interval '2 days', 2),
  ('ad100000-0000-0000-0000-000000000003', :h, 'turkistan', 'running', 'Run in Turkistan', 'Square', now() + interval '1 day', 30);
\set ev_now  '''ad100000-0000-0000-0000-000000000001'''
\set ev_full '''ad100000-0000-0000-0000-000000000002'''

-- ---------------------------------------------------------------
-- #2 Check-in codes can't be guessed
-- ---------------------------------------------------------------
:as_m1
select join_event(:ev_now);
:as_m2
select pg_temp.ok(check_in(:ev_now, '0000')->>'error' = 'not_going', 'not going: no code feedback at all');
:as_m1
do $$ declare i int; begin
  for i in 1..5 loop
    if check_in('ad100000-0000-0000-0000-000000000001', 'xxxx')->>'error' <> 'bad_code' then raise exception 'FAIL: try %', i; end if;
  end loop;
end $$;
reset role;
select checkin_code(:ev_now, now()) as code \gset
:as_m1
select pg_temp.ok(check_in(:ev_now, :'code')->>'error' = 'too_many_tries', 'after 5 wrong codes even the right one waits');
select pg_temp.ok(check_in(:ev_now, :'code') ? 'retry_at', '...and the answer says until when');
reset role;
update event_attendees set checkin_fail_at = now() - interval '11 minutes' where profile_id = :m1;
select checkin_code(:ev_now, now()) as code \gset
:as_m1
select pg_temp.ok((check_in(:ev_now, :'code')->>'ok')::boolean, 'ten minutes later the right code works');
reset role;
select pg_temp.ok((select checked_in_at is not null and checkin_fails = 0 from event_attendees
                    where event_id = :ev_now and profile_id = :m1), 'checked in, counter cleared');
-- brute force: a script running through every code is stopped at 5
:as_m3
select join_event(:ev_now);
do $$ declare i int; r jsonb; n int := 0; begin
  for i in 0..9999 loop
    r := check_in('ad100000-0000-0000-0000-000000000001', lpad(i::text, 4, '0'));
    exit when r->>'error' = 'too_many_tries' or (r->>'ok')::boolean;
    n := n + 1;
  end loop;
  perform pg_temp.ok(r->>'error' = 'too_many_tries' and n <= 5, 'running through all 10 000 codes stops after 5 tries');
end $$;
:as_h
select pg_temp.ok((check_in(:ev_now)->>'ok')::boolean, 'the host still checks in without a code');

-- ---------------------------------------------------------------
-- #3 Accepting a date follows the event's rules
-- ---------------------------------------------------------------
reset role;
insert into swipes (swiper_id, target_id, kind) values (:w1, :m2, 'like');
:as_m2
select swipe(:w1, 'like')->>'match_id' as match \gset
select propose_date(:'match', 'running', null, '', :ev_full)->>'message_id' as d_full \gset
select propose_date(:'match', 'running', null, '', :ev_full)->>'message_id' as d_cancel \gset
select propose_date(:'match', 'running', null, '', :ev_full)->>'message_id' as d_started \gset
select propose_date(:'match', 'running', null, '', :ev_full)->>'message_id' as d_unmatched \gset
:as_s1
select join_event(:ev_full);
:as_w1
select pg_temp.ok(join_event(:ev_full)->>'error' = 'full', 'the event is full (host + 1, capacity 2)');
select respond_date(:'d_full', 'accepted') as r \gset
select pg_temp.ok((:'r'::jsonb->>'ok')::boolean and not (:'r'::jsonb->>'joined')::boolean
                  and :'r'::jsonb->>'reason' = 'full', 'yes to a date at a full event: date accepted, no spot, told why');
reset role;
select pg_temp.ok((select count(*) from event_attendees where event_id = :ev_full and status = 'going') = 2,
                  'nobody squeezed in over capacity');
update events set cancelled = true where id = :ev_full;
:as_w1
select pg_temp.ok(respond_date(:'d_cancel', 'accepted')->>'error' = 'event_cancelled', 'a cancelled event''s plan can''t be accepted');
reset role;
update events set cancelled = false, starts_at = now() - interval '10 minutes' where id = :ev_full;
:as_w1
select pg_temp.ok(respond_date(:'d_started', 'accepted')->>'error' = 'event_started', '...nor one that already started');
select pg_temp.ok((respond_date(:'d_started', 'declined')->>'ok')::boolean, 'saying no still works');
reset role;
update events set starts_at = now() + interval '2 days' where id = :ev_full;
update matches set unmatched_at = now() where id = :'match';
:as_w1
select pg_temp.ok(respond_date(:'d_unmatched', 'accepted')->>'error' = 'not_found', 'no answering after an unmatch');

-- ---------------------------------------------------------------
-- #6, #7 RevenueCat: late renewals, jur_ packs
-- ---------------------------------------------------------------
reset role;
select apply_revenuecat_event(jsonb_build_object('id', 'au1', 'type', 'RENEWAL', 'product_id', 'jur_pro_monthly',
  'app_user_id', :w2, 'expiration_at_ms', (extract(epoch from timestamptz '2026-12-22') * 1000)::bigint));
select apply_revenuecat_event(jsonb_build_object('id', 'au0', 'type', 'RENEWAL', 'product_id', 'jur_pro_monthly',
  'app_user_id', :w2, 'expiration_at_ms', (extract(epoch from timestamptz '2026-11-22') * 1000)::bigint));
select pg_temp.ok((select pro_until::date from profiles where id = :w2) = '2026-12-22', 'a late older renewal doesn''t shorten Pro');
select apply_revenuecat_event(jsonb_build_object('id', 'au2', 'type', 'EXPIRATION', 'product_id', 'jur_pro_monthly',
  'app_user_id', :w2, 'expiration_at_ms', (extract(epoch from now() - interval '1 minute') * 1000)::bigint));
select pg_temp.ok(not is_pro(:w2), 'expiry still ends it');
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object('id', 'au3', 'type', 'NON_RENEWING_PURCHASE',
  'product_id', 'jur_boost_5', 'app_user_id', :w2)) = 'credited:jur_boost_5', 'jur_boost_5 is credited');
select apply_revenuecat_event(jsonb_build_object('id', 'au4', 'type', 'NON_RENEWING_PURCHASE', 'product_id', 'jur_super_10', 'app_user_id', :w2));
select apply_revenuecat_event(jsonb_build_object('id', 'au5', 'type', 'NON_RENEWING_PURCHASE', 'product_id', 'qadam_boost_1', 'app_user_id', :w2));
select pg_temp.ok((select boost_credits = 6 and super_like_credits = 10 from profiles where id = :w2), '...as are jur_super_10 and old qadam_ names');
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object('id', 'au6', 'type', 'NON_RENEWING_PURCHASE',
  'product_id', 'jur_boost_lots', 'app_user_id', :w2)) = 'ignored:unknown_product', 'malformed names are still ignored');

-- ---------------------------------------------------------------
-- #8 Photos are your own uploads
-- ---------------------------------------------------------------
:as_w2
do $$ begin
  update profiles set photos = array['https://evil.example/x.jpg'] where id = auth.uid();
  raise exception 'FAIL: outside photo accepted';
exception when insufficient_privilege then perform pg_temp.ok(true, 'an outside picture is refused');
end $$;
do $$ begin
  update profiles set photos = array['https://test.supabase.co/storage/v1/object/public/photos/ad000000-0000-0000-0000-000000000001/1.jpg']
   where id = auth.uid();
  raise exception 'FAIL: borrowed photo accepted';
exception when insufficient_privilege then perform pg_temp.ok(true, 'another member''s photo is refused');
end $$;
do $$ begin
  update profiles set photos = array['https://test.supabase.co/storage/v1/object/public/photos/ad000000-0000-0000-0000-000000000002/../ad000000-0000-0000-0000-000000000001/1.jpg']
   where id = auth.uid();
  raise exception 'FAIL: path trick accepted';
exception when insufficient_privilege then perform pg_temp.ok(true, '...also with a ../ path trick');
end $$;
update profiles set photos = photos || (:photo || :w2 || '/2.jpg') where id = auth.uid();
select pg_temp.ok((select array_length(photos, 1) = 2 from profiles where id = :w2), 'adding your own upload works');
reset role;
update profiles set photos = array['legacy.jpg'] where id = :m3;
:as_m3
update profiles set photos = photos || (:photo || :m3 || '/2.jpg') where id = auth.uid();
select pg_temp.ok((select photos[1] = 'legacy.jpg' from profiles where id = :m3), 'photos already on a profile can stay');
reset role;
update profiles set photos = array[:photo || :m3 || '/1.jpg'] where id = :m3;

-- ---------------------------------------------------------------
-- #9 Undo brings back the person the toast named
-- ---------------------------------------------------------------
reset role;
update profiles set pro_until = now() + interval '30 days' where id = :w1;
:as_w1
select swipe(:m1, 'pass');
select swipe(:m3, 'like');
select pg_temp.ok(rewind()->>'error' = 'nothing_to_undo', 'the Undo button still only takes back a last pass');
select pg_temp.ok(rewind(:m1)->'profile'->>'name' = 'M1', 'the toast''s undo brings back M1 even after a like');
select pg_temp.ok(rewind(:m3)->>'error' = 'nothing_to_undo', 'a like can''t be undone that way');
select swipe(:m1, 'pass');
select pg_temp.ok(rewind()->'profile'->>'name' = 'M1', 'without a target: the last pass, as before');

-- ---------------------------------------------------------------
-- #11 Events and clubs follow travel mode
-- ---------------------------------------------------------------
:as_w1
select set_travel('turkistan', 3);
select pg_temp.ok((select bool_and(e->>'city' = 'turkistan') and count(*) = 1 from jsonb_array_elements(upcoming_events()) e),
                  'travelling: events are in the travel city');
select pg_temp.ok(upcoming_events('taraz') <> '[]'::jsonb, 'a city can still be asked for');
reset role;
update profiles set travel_until = now() - interval '1 minute' where id = :w1;
:as_w1
select pg_temp.ok((select bool_and(e->>'city' = 'taraz') from jsonb_array_elements(upcoming_events()) e), 'back home: home events');

-- ---------------------------------------------------------------
-- #16 Reports from strangers don't hide anyone on their own
-- ---------------------------------------------------------------
reset role;
do $$ declare r uuid; begin
  foreach r in array array['ad000000-0000-0000-0000-000000000007','ad000000-0000-0000-0000-000000000008',
                           'ad000000-0000-0000-0000-000000000009']::uuid[] loop
    perform set_config('request.jwt.claim.sub', r::text, true);
    execute 'set local role authenticated';
    insert into reports (reporter_id, reported_id, reason) values (r, 'ad000000-0000-0000-0000-000000000002', 'fake');
    execute 'reset role';
  end loop;
end $$;
select pg_temp.ok((select not hidden from profiles where id = :w2), 'three strangers'' reports don''t hide her');
select pg_temp.ok((select count(*) = 3 from reports where reported_id = :w2 and status = 'open'), '...but all three wait for moderators');
select pg_temp.ok((select count(*) = 3 from blocks where blocked_id = :w2), '...and each reporter has blocked her');
insert into swipes (swiper_id, target_id, kind) values (:m3, :w1, 'like'), (:m3, :w2, 'like'), (:m3, :s1, 'like');
do $$ declare r uuid; begin
  foreach r in array array['ad000000-0000-0000-0000-000000000001','ad000000-0000-0000-0000-000000000002',
                           'ad000000-0000-0000-0000-000000000007']::uuid[] loop
    perform set_config('request.jwt.claim.sub', r::text, true);
    execute 'set local role authenticated';
    insert into reports (reporter_id, reported_id, reason) values (r, 'ad000000-0000-0000-0000-000000000005', 'harassment');
    execute 'reset role';
  end loop;
end $$;
select pg_temp.ok((select hidden and held from profiles where id = :m3), 'three people he liked reporting him do hide him');

-- ---------------------------------------------------------------
-- #17 A ban outlives deleting the account
-- ---------------------------------------------------------------
reset role;
update profiles set banned = true where id = :m3;
delete from auth.users where id = :m3;       -- what the delete-account function does
select pg_temp.ok(not exists (select 1 from profiles where id = :m3), 'the banned account is gone');
insert into auth.users (id, email) values ('ad000000-0000-0000-0000-000000000099', ' Audit5@Example.com');
insert into profiles (id, name, birthdate, gender, interested_in, city)
values ('ad000000-0000-0000-0000-000000000099', 'New me', '1995-01-01', 'man', 'women', 'taraz');
select pg_temp.ok((select banned and hidden from profiles where id = 'ad000000-0000-0000-0000-000000000099'),
                  'signing up again with the same email starts banned');
insert into auth.users (id, email) values ('ad000000-0000-0000-0000-000000000098', 'someone.else@example.com');
insert into profiles (id, name, birthdate, gender, interested_in, city)
values ('ad000000-0000-0000-0000-000000000098', 'Fresh', '1995-01-01', 'man', 'women', 'taraz');
select pg_temp.ok((select not banned from profiles where id = 'ad000000-0000-0000-0000-000000000098'), 'other new people are not affected');

-- ---------------------------------------------------------------
-- #5 Referral progress counts verified friends; the rest wait
-- ---------------------------------------------------------------
reset role;
update profiles set referred_by = :w1 where id in (:m1, :m2);
select pg_temp.ok((select bonus_pro_until is null from profiles where id = :w1), 'two unverified sign-ups give nothing');
update profiles set verification_status = 'approved' where id = :m1;
:as_w1
select pg_temp.ok((select (r->>'count')::int = 1 and (r->>'pending')::int = 1 and (r->>'toNext')::int = 1
                     from my_referrals() r), 'progress: 1 verified, 1 waiting, 1 to go');
reset role;
select pg_temp.ok((select bonus_pro_until is null from profiles where id = :w1), 'no bonus yet');
update profiles set verification_status = 'approved' where id = :m2;
select pg_temp.ok((select bonus_pro_until > now() + interval '6 days' from profiles where id = :w1), 'the second verified friend unlocks the week');
