-- Member-hosted events, check-in codes, badges, founding numbers and the Pro gift.
\set ON_ERROR_STOP on
\pset pager off
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

create function pg_temp.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'ok - %', msg;
end $$;
grant execute on function pg_temp.ok(boolean, text) to public;

\set host '''e0000000-0000-0000-0000-000000000001'''
\set guest '''e0000000-0000-0000-0000-000000000002'''
\set plain '''e0000000-0000-0000-0000-000000000003'''
insert into auth.users (id) values (:host), (:guest), (:plain);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, verification_status) values
  (:host,  'Hana',  '1995-01-01', 'woman', 'men',   'karaganda', '{h.jpg}', 'approved'),
  (:guest, 'Gani',  '1994-01-01', 'man',   'women', 'karaganda', '{g.jpg}', 'none'),
  (:plain, 'Pavel', '1993-01-01', 'man',   'women', 'karaganda', '{p.jpg}', 'none');

-- ---------------------------------------------------------------
-- Founding numbers
-- ---------------------------------------------------------------
select pg_temp.ok((select array_agg(city_no order by city_no) from profiles where id in (:host, :guest, :plain))
                  = (select array_agg(n) from generate_series(
                       (select city_no from profiles where id = :host), (select city_no from profiles where id = :host) + 2) n),
                  'each city numbers members in join order');

-- ---------------------------------------------------------------
-- Who can host
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000003';
do $$ begin
  insert into events (host_id, city, sport_code, title, meeting_point, starts_at)
  values (auth.uid(), 'karaganda', 'running', 'Unverified run', 'Central park', now() + interval '1 day');
  raise exception 'FAIL: unverified member hosted';
exception when insufficient_privilege then raise notice 'ok - only verified members host';
end $$;

set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000001';
insert into events (host_id, city, sport_code, title, meeting_point, starts_at, capacity)
values (auth.uid(), 'karaganda', 'skiing', 'Evening ski laps', 'Ski base gate', now() + interval '1 day', 10)
returning id as ev \gset
select pg_temp.ok((get_event(:'ev')->>'going_count')::int = 1, 'the host goes to their own event');

do $$ begin
  insert into events (host_id, city, sport_code, title, meeting_point, starts_at, price_kzt)
  values (auth.uid(), 'karaganda', 'running', 'Paid run', 'Central park', now() + interval '1 day', 2000);
  raise exception 'FAIL: paid member event';
exception when insufficient_privilege then raise notice 'ok - member events are free';
end $$;
do $$ begin
  insert into events (host_id, city, sport_code, title, meeting_point, starts_at, capacity)
  values (auth.uid(), 'karaganda', 'running', 'Huge run', 'Central park', now() + interval '1 day', 60);
  raise exception 'FAIL: huge member event';
exception when insufficient_privilege then raise notice 'ok - member events are at most 50 people';
end $$;
do $$ begin
  insert into events (host_id, city, sport_code, title, meeting_point, starts_at)
  values (auth.uid(), 'karaganda', 'running', 'Far future', 'Central park', now() + interval '90 days');
  raise exception 'FAIL: far-future event';
exception when insufficient_privilege then raise notice 'ok - events start within 60 days';
end $$;
insert into events (host_id, city, sport_code, title, meeting_point, starts_at)
values (auth.uid(), 'karaganda', 'running', 'Run two', 'Central park', now() + interval '2 days'),
       (auth.uid(), 'karaganda', 'running', 'Run three', 'Central park', now() + interval '3 days');
do $$ begin
  insert into events (host_id, city, sport_code, title, meeting_point, starts_at)
  values (auth.uid(), 'karaganda', 'running', 'Run four', 'Central park', now() + interval '4 days');
  raise exception 'FAIL: fourth upcoming event';
exception when insufficient_privilege then raise notice 'ok - at most 3 upcoming events per member';
end $$;

-- ---------------------------------------------------------------
-- Check-in codes
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000002';
select pg_temp.ok((join_event(:'ev')->>'ok')::boolean, 'a member joins');
select pg_temp.ok(host_checkin_code(:'ev')->>'error' = 'not_host', 'only the host sees the code');
reset role;
-- move the event to "now" (the start-time rule is for people, not this test)
alter table events disable trigger events_member_check;
update events set starts_at = now() - interval '5 minutes' where id = :'ev';
alter table events enable trigger events_member_check;
set role authenticated;
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000001';
select host_checkin_code(:'ev')->>'code' as code \gset
select pg_temp.ok(length(:'code') = 4, 'the host gets a 4-digit code');
select pg_temp.ok((check_in(:'ev')->>'ok')::boolean, 'the host checks in without a code');
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000002';
select pg_temp.ok(check_in(:'ev', '0000')->>'error' = 'bad_code' or :'code' = '0000', 'a wrong code is refused');
reset role;
select checkin_code(:'ev', now() - interval '1 minute') as prev \gset
set role authenticated;
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000002';
select pg_temp.ok((check_in(:'ev', :'prev')->>'ok')::boolean, 'last minute''s code still works');
reset role;
select pg_temp.ok(checkin_code(:'ev', now()) <> checkin_code(:'ev', now() + interval '2 minutes')
                  or checkin_code(:'ev', now() + interval '2 minutes') <> checkin_code(:'ev', now() + interval '3 minutes'),
                  'the code changes over time');
set role authenticated;
do $$ begin
  perform public.checkin_code('00000000-0000-0000-0000-000000000000', now());
  raise exception 'FAIL: checkin_code callable';
exception when insufficient_privilege then raise notice 'ok - codes are only shown to the host';
end $$;

-- ---------------------------------------------------------------
-- Badges
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000002';
select pg_temp.ok(get_profile(:guest)->'badges' @> '["founding", "showed_up", "winter"]'
                  and not get_profile(:guest)->'badges' @> '["verified"]', 'badges: founding, showed up, winter');
select pg_temp.ok(get_profile(:host)->'badges' @> '["verified"]', 'verified members get the Verified badge');
reset role;
-- five check-ins → Regular
insert into events (id, host_id, city, sport_code, title, meeting_point, starts_at)
  select ('e1000000-0000-0000-0000-00000000000' || g)::uuid, null, 'karaganda', 'running', 'Old run ' || g, 'Park',
         now() - (g || ' days')::interval
    from generate_series(1, 4) g;
insert into event_attendees (event_id, profile_id, checked_in_at)
  select ('e1000000-0000-0000-0000-00000000000' || g)::uuid, :guest, now() - (g || ' days')::interval from generate_series(1, 4) g;
select pg_temp.ok(profile_badges(:guest) @> '["regular", "summer"]', 'five check-ins make a Regular; a run gives Summer');
-- founding stops at 1,000
update profiles set city_no = 1001 where id = :plain;
select pg_temp.ok(not profile_badges(:plain) @> '["founding"]', 'number 1001 is not a founding member');
-- Host badge: 3 events with 3 checked-in guests each
insert into auth.users (id) select ('e2000000-0000-0000-0000-00000000000' || g)::uuid from generate_series(1, 3) g;
insert into profiles (id, name, birthdate, gender, interested_in, city, photos)
  select ('e2000000-0000-0000-0000-00000000000' || g)::uuid, 'Guest' || g, '1990-01-01', 'man', 'women', 'karaganda', '{x.jpg}'
    from generate_series(1, 3) g;
update events set host_id = :host where id::text like 'e1000000%' and title in ('Old run 1', 'Old run 2', 'Old run 3');
insert into event_attendees (event_id, profile_id, checked_in_at)
  select ('e1000000-0000-0000-0000-00000000000' || e)::uuid, ('e2000000-0000-0000-0000-00000000000' || g)::uuid, now() - interval '1 day'
    from generate_series(1, 3) e, generate_series(1, 1) g;
-- each old run now has 2 checked-in guests (Gani + Guest1)
select pg_temp.ok(not profile_badges(:host) @> '["host"]', 'not a Host yet: needs 3 checked-in guests per event');
insert into event_attendees (event_id, profile_id, checked_in_at)
  select ('e1000000-0000-0000-0000-00000000000' || e)::uuid, 'e2000000-0000-0000-0000-000000000002', now() - interval '1 day'
    from generate_series(1, 3) e;
select pg_temp.ok(profile_badges(:host) @> '["host"]', 'Host badge after 3 events with 3 guests each');
-- First step: an accepted date suggestion
insert into matches (user_a, user_b) values (least(:host::uuid, :guest::uuid), greatest(:host::uuid, :guest::uuid)) returning id as m \gset
insert into messages (match_id, sender_id, body, kind, payload)
values (:'m', :guest, 'Run?', 'date', '{"status": "accepted", "when": "2026-11-01T10:00:00Z", "place": "Park"}');
select pg_temp.ok(profile_badges(:guest) @> '["first_step"]' and not profile_badges(:host) @> '["first_step"]',
                  'First step goes to the person whose suggestion was accepted');

-- ---------------------------------------------------------------
-- Gift a week of Pro
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000001';
select pg_temp.ok(create_pro_gift()->>'error' = 'pro_only', 'only Pro members can gift');
reset role;
update profiles set pro_until = now() + interval '30 days' where id = :host;
set role authenticated;
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000001';
select create_pro_gift()->>'code' as gift \gset
select pg_temp.ok(length(:'gift') = 8, 'a Pro member gets a gift code');
select pg_temp.ok(create_pro_gift()->>'code' = :'gift', 'asking again this month returns the same code');
select pg_temp.ok(redeem_pro_gift(:'gift')->>'error' = 'own_gift', 'you can''t redeem your own gift');
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000003';
select pg_temp.ok((redeem_pro_gift(lower(:'gift'))->>'ok')::boolean, 'a friend redeems it (any case)');
select pg_temp.ok((my_limits()->>'pro')::boolean, 'the friend has Pro');
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000002';
select pg_temp.ok(redeem_pro_gift(:'gift')->>'error' = 'used', 'a code works once');
set request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000001';
select pg_temp.ok(create_pro_gift()->>'error' = 'once_a_month', 'one new gift per 30 days');
reset role;
\echo 'EVENTS AND BADGES TESTS PASSED'
