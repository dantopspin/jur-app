-- Behavioural tests for the Qadam backend. Run with tests/run.sh.
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

-- Fixed ids for readability
\set aliya  '''11111111-1111-1111-1111-111111111111'''
\set timur  '''22222222-2222-2222-2222-222222222222'''
\set dana   '''33333333-3333-3333-3333-333333333333'''
\set arman  '''44444444-4444-4444-4444-444444444444'''
\set host   '''55555555-5555-5555-5555-555555555555'''
\set kid    '''66666666-6666-6666-6666-666666666666'''

insert into auth.users (id) values (:aliya), (:timur), (:dana), (:arman), (:host), (:kid);

-- ---------------------------------------------------------------
-- Profiles: users create their own, cannot touch money columns
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, next_challenge)
values (:aliya, 'Aliya', '1997-05-01', 'woman', 'men', 'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :aliya || '/a.jpg'], 'First half marathon');
insert into profile_sports (profile_id, sport_code, level) values (:aliya, 'running', 'regular'), (:aliya, 'skiing', 'casual');
insert into achievements (profile_id, sport_code, title, result) values (:aliya, 'running', 'Almaty Marathon 10K', '52:10');

do $$ begin
  update profiles set pro_until = now() + interval '1 year' where id = auth.uid();
  raise exception 'FAIL: user could set pro_until';
exception when insufficient_privilege then raise notice 'ok - user cannot grant themselves Pro';
end $$;
do $$ begin
  update profiles set boost_credits = 99 where id = auth.uid();
  raise exception 'FAIL: user could set credits';
exception when insufficient_privilege then raise notice 'ok - user cannot add credits';
end $$;
do $$ begin
  insert into profile_sports (profile_id, sport_code) values ('22222222-2222-2222-2222-222222222222', 'running');
  raise exception 'FAIL: wrote someone else''s sports';
exception when insufficient_privilege then raise notice 'ok - cannot edit another profile''s sports';
end $$;
do $$ begin
  perform * from swipes;
  raise exception 'FAIL: swipes readable';
exception when insufficient_privilege then raise notice 'ok - swipes table is not readable directly';
end $$;
do $$ begin
  perform public.profile_card('11111111-1111-1111-1111-111111111111');
  raise exception 'FAIL: profile_card callable by clients';
exception when insufficient_privilege then raise notice 'ok - profile_card is internal';
end $$;
do $$ begin
  perform public.is_pro('22222222-2222-2222-2222-222222222222');
  raise exception 'FAIL: is_pro callable by clients';
exception when insufficient_privilege then raise notice 'ok - users cannot look up others'' Pro status';
end $$;
do $$ begin
  perform public.apply_revenuecat_event('{"id":"x","type":"INITIAL_PURCHASE"}');
  raise exception 'FAIL: client could call webhook function';
exception when insufficient_privilege then raise notice 'ok - clients cannot call the purchase webhook function';
end $$;

set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
insert into profiles (id, name, birthdate, gender, interested_in, city, photos)
values (:timur, 'Timur', '1994-02-10', 'man', 'women', 'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :timur || '/t.jpg']);
insert into profile_sports (profile_id, sport_code) values (:timur, 'skiing'), (:timur, 'tennis');
select pg_temp.ok((select count(*) from profiles) = 1, 'a user sees only their own profile row');

set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
insert into profiles (id, name, birthdate, gender, interested_in, city, photos)
values (:dana, 'Dana', '1998-08-08', 'woman', 'men', 'astana', array['https://test.supabase.co/storage/v1/object/public/photos/' || :dana || '/d.jpg']);

set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
insert into profiles (id, name, birthdate, gender, interested_in, city, photos)
values (:arman, 'Arman', '1990-01-01', 'man', 'women', 'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :arman || '/ar.jpg']);
insert into profile_sports (profile_id, sport_code) values (:arman, 'running');

set request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
do $$ begin
  insert into profiles (id, name, birthdate, gender, interested_in, city)
  values ('66666666-6666-6666-6666-666666666666', 'Kid', current_date - interval '17 years', 'man', 'women', 'almaty');
  raise exception 'FAIL: under-18 profile created';
exception when check_violation then raise notice 'ok - under-18 sign-up is rejected';
end $$;

-- ---------------------------------------------------------------
-- Discover
-- ---------------------------------------------------------------
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.ok(
  (select array_agg(x->>'name' order by x->>'name') from jsonb_array_elements(discover()) x) = '{Arman,Timur}',
  'discover: same city, matching preferences, not myself, not other cities');
select pg_temp.ok(
  (select (x->>'shared_sports')::int from jsonb_array_elements(discover()) x where x->>'name' = 'Timur') = 1,
  'discover: counts shared sports');
select pg_temp.ok(
  (discover()->0->>'member_no') is not null and (discover()->0->'sports') is not null,
  'discover cards carry bib number and sports');

-- ---------------------------------------------------------------
-- Swipes and matches
-- ---------------------------------------------------------------
select pg_temp.ok((swipe(:timur, 'like')->>'match_id') is null, 'one-sided like is not a match');
select pg_temp.ok(
  (select count(*) from jsonb_array_elements(discover()) x where x->>'name' = 'Timur') = 0,
  'swiped profiles leave the feed');

set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select pg_temp.ok((likes_received()->>'count')::int = 1 and jsonb_array_length(likes_received()->'profiles') = 0,
  'free user sees how many liked them, not who');
select (swipe(:aliya, 'like')->>'match_id') as match_id \gset
select pg_temp.ok(:'match_id' <> '', 'mutual like creates a match');
select set_config('test.match_id', :'match_id', false);
select pg_temp.ok(jsonb_array_length(my_matches()) = 1, 'match shows in the inbox');

-- ---------------------------------------------------------------
-- Chat permissions
-- ---------------------------------------------------------------
insert into messages (match_id, sender_id, body) values (:'match_id', :timur, 'Ski day on Saturday?');
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.ok((select count(*) from messages) = 1, 'match member reads the chat');
select pg_temp.ok((my_matches()->0->>'unread')::int = 1, 'unread count');
select mark_read(:'match_id');
select pg_temp.ok((my_matches()->0->>'unread')::int = 0, 'mark_read clears unread');
do $$ begin
  insert into messages (match_id, sender_id, body)
  values ((select id from matches limit 1), '22222222-2222-2222-2222-222222222222', 'spoofed');
  raise exception 'FAIL: spoofed sender';
exception when insufficient_privilege then raise notice 'ok - cannot send as someone else';
end $$;

set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select pg_temp.ok((select count(*) from messages) = 0 and (select count(*) from matches) = 0,
  'outsider cannot read other people''s matches or messages');
do $$ begin
  insert into messages (match_id, sender_id, body)
  values (current_setting('test.match_id')::uuid, '44444444-4444-4444-4444-444444444444', 'hi');
  raise exception 'FAIL: outsider wrote into a chat';
exception when insufficient_privilege then raise notice 'ok - outsider cannot write into a chat';
end $$;

-- ---------------------------------------------------------------
-- Free limits, credits and Pro via the purchase webhook
-- ---------------------------------------------------------------
reset role;
insert into auth.users (id) select gen_random_uuid() from generate_series(1, 40);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos)
select id, 'W' || row_number() over (), '1996-01-01', 'woman', 'men', 'almaty', '{w.jpg}'
from auth.users where id not in (select id from profiles) and id not in ('66666666-6666-6666-6666-666666666666', '55555555-5555-5555-5555-555555555555');

set role authenticated;
set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select pg_temp.ok((my_limits()->>'likes_left')::int = 30, 'free user starts with 30 likes');
do $$
declare r jsonb; i int := 0; t uuid;
begin
  for t in select (x->>'id')::uuid from jsonb_array_elements(discover(50)) x loop
    r := swipe(t, 'like'); i := i + 1;
    exit when i = 31;
  end loop;
  if r->>'error' <> 'like_limit' then raise exception 'FAIL: 31st like allowed: %', r; end if;
  raise notice 'ok - 31st like of the day is refused for free users';
end $$;
select pg_temp.ok((my_limits()->>'likes_left')::int = 0, 'likes_left reaches zero');

select (x->>'id') as t1 from jsonb_array_elements(discover(5)) x limit 1 \gset
select pg_temp.ok((swipe(:'t1', 'super')->>'ok')::boolean, 'one free super like a day');
select (x->>'id') as t2 from jsonb_array_elements(discover(5)) x limit 1 \gset
select pg_temp.ok(swipe(:'t2', 'super')->>'error' = 'super_limit', 'second super like needs credits');

reset role;
set role service_role;
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object(
  'id', 'evt-1', 'type', 'NON_RENEWING_PURCHASE', 'product_id', 'qadam_super_5',
  'app_user_id', '44444444-4444-4444-4444-444444444444')) = 'credited:qadam_super_5', 'webhook credits super likes');
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object(
  'id', 'evt-1', 'type', 'NON_RENEWING_PURCHASE', 'product_id', 'qadam_super_5',
  'app_user_id', '44444444-4444-4444-4444-444444444444')) = 'duplicate', 'duplicate webhook delivery is ignored');
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object(
  'id', 'evt-anon', 'type', 'INITIAL_PURCHASE', 'product_id', 'qadam_pro_monthly',
  'app_user_id', '$RCAnonymousID:abc')) = 'ignored:unknown_user', 'anonymous RevenueCat ids are ignored');

reset role;
set role authenticated;
set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select pg_temp.ok((my_limits()->>'supers_left')::int = 5, 'purchased super likes show up');
select pg_temp.ok((swipe(:'t2', 'super')->>'used_credit')::boolean, 'super like spends a credit');
select pg_temp.ok((my_limits()->>'supers_left')::int = 4, 'credit decremented');
select pg_temp.ok(activate_boost()->>'error' = 'no_boosts', 'no boost without credits or Pro');

reset role;
set role service_role;
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object(
  'id', 'evt-2', 'type', 'INITIAL_PURCHASE', 'product_id', 'qadam_pro_monthly',
  'entitlement_ids', jsonb_build_array('pro'),
  'expiration_at_ms', (extract(epoch from now() + interval '30 days') * 1000)::bigint,
  'app_user_id', '44444444-4444-4444-4444-444444444444')) like 'pro_until:%', 'webhook turns on Pro');

reset role;
set role authenticated;
set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select pg_temp.ok((my_limits()->>'pro')::boolean and my_limits()->>'likes_left' is null, 'Pro has unlimited likes');
select (x->>'id') as t3 from jsonb_array_elements(discover(5)) x limit 1 \gset
select pg_temp.ok((swipe(:'t3', 'like')->>'ok')::boolean, 'Pro can like past the free limit');
select pg_temp.ok((activate_boost()->>'ok')::boolean, 'Pro gets a free weekly boost');
select pg_temp.ok(activate_boost()->>'error' = 'already_boosted', 'cannot stack boosts');

-- Boosted profile is first in someone else's feed
reset role;
insert into auth.users (id) values ('77777777-7777-7777-7777-777777777777');
insert into profiles (id, name, birthdate, gender, interested_in, city, photos)
values ('77777777-7777-7777-7777-777777777777', 'Saule', '1995-03-03', 'woman', 'men', 'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || '77777777-7777-7777-7777-777777777777' || '/s.jpg']);
set role authenticated;
set request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
select pg_temp.ok(discover()->0->>'name' = 'Arman' and (discover()->0->>'boosted')::boolean, 'boosted profile leads the feed');

-- Pro sees who liked them
select pg_temp.ok((swipe(:arman, 'like')->>'match_id') is null, 'Saule likes Arman');
set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select pg_temp.ok(likes_received()->'profiles'->0->>'name' = 'Saule', 'Pro sees who liked them');

reset role;
set role service_role;
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object(
  'id', 'evt-3', 'type', 'EXPIRATION', 'product_id', 'qadam_pro_monthly',
  'expiration_at_ms', (extract(epoch from now() - interval '1 minute') * 1000)::bigint,
  'app_user_id', '44444444-4444-4444-4444-444444444444')) = 'pro_expired', 'webhook expiry');
reset role;
select pg_temp.ok(not is_pro('44444444-4444-4444-4444-444444444444'), 'Pro ends on expiry');

-- ---------------------------------------------------------------
-- Safety: block, unmatch, report
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into blocks (blocker_id, blocked_id) values (:aliya, :timur);
select pg_temp.ok(jsonb_array_length(my_matches()) = 0, 'blocked match disappears from inbox');
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select pg_temp.ok(jsonb_array_length(my_matches()) = 0, '...for both people');
select pg_temp.ok(get_profile(:aliya) is null, 'blocked person cannot open your profile');
do $$ begin
  insert into messages (match_id, sender_id, body)
  values (current_setting('test.match_id')::uuid, '22222222-2222-2222-2222-222222222222', 'hello?');
  raise exception 'FAIL: message after block';
exception when insufficient_privilege then raise notice 'ok - cannot message after a block';
end $$;

-- three different reporters who crossed paths with someone auto-hide them (here: she liked them)
reset role;
insert into swipes (swiper_id, target_id, kind)
select '33333333-3333-3333-3333-333333333333', id, 'like' from profiles where name like 'W%' order by id limit 3;
do $$
declare r uuid;
begin
  for r in select id from profiles where name like 'W%' order by id limit 3 loop
    perform set_config('request.jwt.claim.sub', r::text, true);
    execute 'set local role authenticated';
    insert into reports (reporter_id, reported_id, reason) values (r, '33333333-3333-3333-3333-333333333333', 'fake');
    execute 'reset role';
  end loop;
end $$;
select pg_temp.ok((select hidden from profiles where id = :dana), 'three reports auto-hide a profile for review');

-- ---------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------
reset role;
insert into profiles (id, name, birthdate, gender, interested_in, city, photos)
values (:host, 'Coach Erlan', '1988-01-01', 'man', 'women', 'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :host || '/h.jpg']);

set role authenticated;
set request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
do $$ begin
  insert into events (host_id, city, sport_code, title, meeting_point, starts_at)
  values (auth.uid(), 'almaty', 'running', 'Sunday 7K', 'Gorky Park gate', now() + interval '2 days');
  raise exception 'FAIL: non-host created an event';
exception when insufficient_privilege then raise notice 'ok - only approved hosts create events';
end $$;
reset role;
update profiles set is_host = true where id = :host;
set role authenticated;
set request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
insert into events (host_id, city, sport_code, title, meeting_point, starts_at, capacity)
values (auth.uid(), 'almaty', 'skiing', 'Shymbulak singles ski day', 'Medeu cable car', now() + interval '2 days', 3)  -- the host + 2
returning id as ev \gset
insert into events (host_id, city, sport_code, title, meeting_point, starts_at)
values (auth.uid(), 'almaty', 'running', 'Morning 5K', 'Botanical garden', now() + interval '1 day');

set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.ok(jsonb_array_length(upcoming_events()) = 2, 'events listed for my city');
select pg_temp.ok(
  (upcoming_events()->0->>'sport_code') = case when current_season() = 'winter' then 'skiing' else 'running' end,
  'in-season sports are listed first');
select pg_temp.ok(jsonb_array_length(event_people(:'ev')) = 0, 'attendee list hidden until you join');
select pg_temp.ok((join_event(:'ev')->>'ok')::boolean, 'join event');
set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select pg_temp.ok((join_event(:'ev')->>'ok')::boolean, 'second person joins');
select pg_temp.ok(event_people(:'ev') @> '[{"name": "Aliya"}]', 'attendees see each other');
set request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
select pg_temp.ok(join_event(:'ev')->>'error' = 'full', 'capacity is enforced');
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.ok(check_in(:'ev')->>'error' = 'not_now', 'check-in only opens near the start');
reset role;
update events set starts_at = now() - interval '10 minutes' where id = :'ev';
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.ok(check_in(:'ev')->>'error' = 'bad_code', 'check-in needs the host''s code');
reset role;
select checkin_code(:'ev', now()) as code \gset
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.ok((check_in(:'ev', :'code')->>'ok')::boolean, 'check-in during the event');
select pg_temp.ok((get_profile(:aliya)->>'events_attended')::int = 1, 'attended events count on the profile');

-- ---------------------------------------------------------------
-- Streak, referral, account deletion
-- ---------------------------------------------------------------
select pg_temp.ok((record_activity()->>'streak_days')::int = 1, 'streak starts');
reset role;
update profiles set streak_days = 6, streak_last_day = local_today() - 1, boost_credits = 0 where id = :aliya;
set role authenticated;
select pg_temp.ok((record_activity()->>'rewarded_boost')::boolean, '7-day streak earns a boost');
select pg_temp.ok((record_activity()->>'rewarded_boost')::boolean = false, 'reward is once per streak day');

select referral_code as code from profiles where id = :aliya \gset
reset role;
do $$
declare r uuid; v jsonb;
  v_code text := (select referral_code from profiles where id = '11111111-1111-1111-1111-111111111111');
begin
  for r in select id from profiles where name in ('W10', 'W11') loop
    perform set_config('request.jwt.claim.sub', r::text, true);
    execute 'set local role authenticated';
    v := redeem_referral(v_code);
    if not (v->>'ok')::boolean then raise exception 'FAIL: referral %', v; end if;
    execute 'reset role';
  end loop;
end $$;
select pg_temp.ok(not is_pro(:aliya), 'two sign-ups alone don''t unlock Pro (friends must be verified)');
update profiles set verification_status = 'approved' where name = 'W10';
select pg_temp.ok(not is_pro(:aliya), 'one verified friend is not enough');
update profiles set verification_status = 'approved' where name = 'W11';
select pg_temp.ok(is_pro(:aliya), 'two verified referrals unlock a week of Pro');
update profiles set verification_status = 'none' where name = 'W11';
update profiles set verification_status = 'approved' where name = 'W11';
select pg_temp.ok((select count(*) from referral_credits where referrer_id = :aliya) = 2,
                  'a friend counts once, even if verified again');

set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select delete_account();
reset role;
select pg_temp.ok(not exists (select 1 from profiles where id = :timur)
                  and not exists (select 1 from messages where sender_id = :timur),
                  'account deletion removes profile and messages');

\echo ALL TESTS PASSED
