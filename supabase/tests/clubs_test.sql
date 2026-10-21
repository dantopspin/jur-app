-- Tests for clubs, the open-to-meet signal and city launch.
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

\set org   '''c0000000-0000-0000-0000-000000000001'''
\set ana   '''c0000000-0000-0000-0000-000000000002'''
\set ben   '''c0000000-0000-0000-0000-000000000003'''
\set stray '''c0000000-0000-0000-0000-000000000004'''
insert into auth.users (id) values (:org), (:ana), (:ben), (:stray);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos) values
  (:org, 'Dias', '1990-02-02', 'man', 'women', 'almaty', '{d.jpg}'),
  (:ana, 'Ana', '1996-06-06', 'woman', 'men', 'almaty', '{a.jpg}'),
  (:ben, 'Ben', '1995-05-05', 'man', 'women', 'almaty', '{b.jpg}'),
  (:stray, 'Saule', '1997-07-07', 'woman', 'men', 'almaty', '{s.jpg}');

-- ---------------------------------------------------------------
-- Applying to start a club → moderator approves → organizer
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000001';
select pg_temp.ok((apply_club('almaty', 'running', 'Medeu Morning Runners', 'Easy 6K every Saturday, then tea.')->>'ok')::boolean,
                  'anyone can apply to start a club');
select pg_temp.ok(apply_club('almaty', 'running', 'Second club', 'Another idea for a club.')->>'error' = 'pending_exists',
                  'one pending application at a time');
do $$ begin
  perform approve_club_application((select id from club_applications limit 1));
  raise exception 'FAIL: users can approve';
exception when insufficient_privilege then raise notice 'ok - only moderators approve clubs';
end $$;
reset role;
select approve_club_application((select id from club_applications where profile_id = :org), 'Saturdays 08:00 · Medeu') as club \gset
select pg_temp.ok((select is_host from profiles where id = :org), 'approved organizers can host events');

-- ---------------------------------------------------------------
-- Joining, club card, club chat
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000002';
select pg_temp.ok(jsonb_array_length(clubs_near()) >= 1 and clubs_near()->0->>'name' = 'Medeu Morning Runners', 'clubs in my city are listed');
do $$ begin
  insert into club_messages (club_id, sender_id, body)
  values ((select id from clubs limit 1), 'c0000000-0000-0000-0000-000000000002', 'hi');
  raise exception 'FAIL: non-member posted';
exception when insufficient_privilege then raise notice 'ok - only members can post in the club chat';
end $$;
select pg_temp.ok(jsonb_array_length(club_feed(:'club')) = 0, 'non-members cannot read the club chat');
select pg_temp.ok((join_club(:'club')->>'ok')::boolean, 'join a club');
insert into club_messages (club_id, sender_id, body) values (:'club', :ana, 'See you Saturday!');
select pg_temp.ok(club_feed(:'club')->0->>'body' = 'See you Saturday!', 'members read the club chat');
select pg_temp.ok((get_club(:'club')->>'member_count')::int = 2 and (get_club(:'club')->>'i_am_member')::boolean,
                  'club card counts members');

-- blocked people disappear from the club chat
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000003';
select join_club(:'club');
insert into blocks (blocker_id, blocked_id) values (:ben, :ana);
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(club_feed(:'club')) x where x->>'sender_id' = 'c0000000-0000-0000-0000-000000000002'),
                  'blocked members are hidden in the club chat');

-- ---------------------------------------------------------------
-- Club events: organizer only, members notified, joining = membership
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000001';
insert into events (host_id, city, sport_code, title, meeting_point, starts_at, club_id)
values (auth.uid(), 'almaty', 'running', 'Saturday 6K', 'Medeu gate', now() + interval '2 days', :'club') returning id as ev \gset
reset role;
select pg_temp.ok((select count(*) from push_outbox where kind = 'club_event' and data->>'url' = '/event/' || :'ev') = 2,
                  'club members hear about a new club event');
update profiles set is_host = true where id = :ben;
set role authenticated;
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000003';
do $$ begin
  insert into events (host_id, city, sport_code, title, meeting_point, starts_at, club_id)
  values (auth.uid(), 'almaty', 'running', 'Fake club run', 'Somewhere', now() + interval '2 days',
          (select id from clubs limit 1));
  raise exception 'FAIL: non-organizer created a club event';
exception when insufficient_privilege then raise notice 'ok - only the organizer posts club events';
end $$;

-- ---------------------------------------------------------------
-- Open to meet
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000004';
select pg_temp.ok((join_event(:'ev', false)->>'ok')::boolean, 'join an event as "here for the sport"');
select pg_temp.ok((get_club(:'club')->>'i_am_member')::boolean, 'joining a club event joins the club');
select pg_temp.ok((get_event(:'ev')->>'i_am_open')::boolean = false, 'my choice is remembered');
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000002';
select join_event(:'ev');
-- the host attends their own event (gold by default), so: host + Saule (blue) + this person (gold)
select pg_temp.ok((get_event(:'ev')->>'open_count')::int = 2 and (get_event(:'ev')->>'going_count')::int = 3,
                  'event shows how many are open to meet');
select pg_temp.ok((select bool_and((x->>'open_to_meet')::boolean = (x->>'name' <> 'Saule'))
                   from jsonb_array_elements(event_people(:'ev')) x), 'attendee list shows each person''s wristband');
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000004';
select set_open_to_meet(:'ev', true);
select pg_temp.ok((get_event(:'ev')->>'open_count')::int = 3, 'switch to "open to meet" any time');
select pg_temp.ok(get_event(:'ev')->'club'->>'name' = 'Medeu Morning Runners', 'event shows its club');
reset role;

-- ---------------------------------------------------------------
-- City launch
-- ---------------------------------------------------------------
-- every city opens at launch (20261021000007); gate one again to test the mechanism
update city_launch set opens_at_members = 2, opened_at = null where city = 'atyrau';
insert into auth.users (id) values ('c0000000-0000-0000-0000-0000000000a1'), ('c0000000-0000-0000-0000-0000000000a2');
insert into profiles (id, name, birthdate, gender, interested_in, city, photos) values
  ('c0000000-0000-0000-0000-0000000000a1', 'Aru', '1998-01-01', 'woman', 'men', 'atyrau', '{x.jpg}');
set role authenticated;
set request.jwt.claim.sub = 'c0000000-0000-0000-0000-0000000000a1';
select pg_temp.ok(not (city_status()->>'open')::boolean and (city_status()->>'members')::int = 1
                  and (city_status()->>'needed')::int = 2, 'a new city waits for enough members');
select pg_temp.ok((city_status('almaty')->>'open')::boolean, 'Almaty is open from day one');
reset role;
insert into profiles (id, name, birthdate, gender, interested_in, city, photos) values
  ('c0000000-0000-0000-0000-0000000000a2', 'Erzhan', '1996-01-01', 'man', 'women', 'atyrau', '{y.jpg}');
select pg_temp.ok((select opened_at is not null from city_launch where city = 'atyrau'), 'the city opens when it reaches the bar');
select pg_temp.ok((select count(*) from push_outbox where kind = 'city_open') = 2, 'everyone there hears the city opened');
select pg_temp.ok((select body from push_outbox where kind = 'city_open' limit 1) like 'Атырау%', 'push names the city');
set role authenticated;
do $$ begin
  perform * from city_launch;
  raise exception 'FAIL: city_launch readable';
exception when insufficient_privilege then raise notice 'ok - launch settings are server-side';
end $$;
reset role;

-- ---------------------------------------------------------------
-- Pricing: decoy pack sizes and the intro offer
-- ---------------------------------------------------------------
select apply_revenuecat_event(jsonb_build_object('id', 'evt-b3', 'type', 'NON_RENEWING_PURCHASE',
  'product_id', 'qadam_boost_3', 'app_user_id', 'c0000000-0000-0000-0000-000000000002'));
select apply_revenuecat_event(jsonb_build_object('id', 'evt-s15', 'type', 'NON_RENEWING_PURCHASE',
  'product_id', 'qadam_super_15', 'app_user_id', 'c0000000-0000-0000-0000-000000000002'));
select pg_temp.ok((select boost_credits = 3 and super_like_credits = 15 from profiles where id = :ana),
                  'any pack size is credited by its number');
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object('id', 'evt-x', 'type', 'NON_RENEWING_PURCHASE',
  'product_id', 'qadam_boost_lots', 'app_user_id', 'c0000000-0000-0000-0000-000000000002')) = 'ignored:unknown_product',
  'unknown products are ignored');
select apply_revenuecat_event(jsonb_build_object('id', 'evt-intro', 'type', 'INITIAL_PURCHASE',
  'product_id', 'qadam_pro_monthly_intro', 'app_user_id', 'c0000000-0000-0000-0000-000000000003',
  'expiration_at_ms', ((extract(epoch from now()) + 30 * 86400) * 1000)::bigint));
select pg_temp.ok(is_pro(:ben), 'the 50% intro offer grants Pro');

\echo CLUBS TESTS PASSED
