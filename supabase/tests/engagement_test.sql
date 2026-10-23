-- Tests for likes with a note, push notifications, reminders and shared events.
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

\set asel   '''a0000000-0000-0000-0000-000000000001'''
\set bolat  '''a0000000-0000-0000-0000-000000000002'''
\set cara   '''a0000000-0000-0000-0000-000000000003'''
\set daur   '''a0000000-0000-0000-0000-000000000004'''
\set erlan  '''a0000000-0000-0000-0000-000000000005'''

insert into auth.users (id) values (:asel), (:bolat), (:cara), (:daur), (:erlan);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, locale) values
  (:asel,  'Asel',  '1996-03-02', 'woman', 'men',   'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :asel || '/a.jpg'], 'kk'),
  (:bolat, 'Bolat', '1994-07-11', 'man',   'women', 'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :bolat || '/b.jpg'], 'en'),
  (:cara,  'Cara',  '1995-01-20', 'woman', 'men',   'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :cara || '/c.jpg'], 'ru'),
  (:daur,  'Daur',  '1993-09-09', 'man',   'women', 'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :daur || '/d.jpg'], 'ru'),
  (:erlan, 'Erlan', '1992-12-12', 'man',   'women', 'almaty', array['https://test.supabase.co/storage/v1/object/public/photos/' || :erlan || '/e.jpg'], 'ru');

-- ---------------------------------------------------------------
-- Push tokens
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000001';
do $$ begin
  perform register_push_token('not-a-token', 'ios');
  raise exception 'FAIL: bad token accepted';
exception when check_violation then raise notice 'ok - malformed push tokens are rejected';
end $$;
select register_push_token('ExponentPushToken[asel-phone]', 'ios');
do $$ begin
  perform * from push_tokens;
  raise exception 'FAIL: push_tokens readable';
exception when insufficient_privilege then raise notice 'ok - push tokens are not readable by clients';
end $$;
do $$ begin
  perform * from push_outbox;
  raise exception 'FAIL: push_outbox readable';
exception when insufficient_privilege then raise notice 'ok - push log is not readable by clients';
end $$;
do $$ begin
  perform queue_push('a0000000-0000-0000-0000-000000000002', 'match', 'x', '{}');
  raise exception 'FAIL: queue_push callable';
exception when insufficient_privilege then raise notice 'ok - clients cannot send pushes to others';
end $$;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000002';
select register_push_token('ExpoPushToken[bolat-phone]', 'android');
reset role;
select pg_temp.ok((select count(*) from push_tokens) = 2, 'tokens registered for two people');

-- ---------------------------------------------------------------
-- Likes with a note → opening messages on a match
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000001';
select pg_temp.ok(swipe(:bolat, 'like', repeat('x', 141))->>'error' = 'note_too_long', 'notes are capped at 140 characters');
select pg_temp.ok((swipe(:bolat, 'like', '  Saw your 10K PB — pacing tips for my first half? ')->>'ok')::boolean, 'like with a note');
select pg_temp.ok(swipe(:bolat, 'like', 'again')->>'match_id' is null, 'no match from a one-sided like');
-- re-like with the original note so the test below checks the right text
select swipe(:bolat, 'like', 'Saw your 10K PB — pacing tips for my first half?');
reset role;
select pg_temp.ok((select count(*) from push_outbox where profile_id = :bolat and kind = 'like') = 1,
                  'the liked person gets one "someone liked you" push');
select pg_temp.ok((select body from push_outbox where profile_id = :bolat and kind = 'like') not like '%Asel%',
                  'like pushes do not reveal who it was');

set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000002';
select swipe(:asel, 'like', 'Happy to! Saturday run at Medeu?')->>'match_id' as m \gset
select pg_temp.ok(:'m' <> '', 'mutual like creates a match');
reset role;
select pg_temp.ok((select array_agg(body order by created_at) from messages where match_id = :'m')
                  = array['Saw your 10K PB — pacing tips for my first half?', 'Happy to! Saturday run at Medeu?'],
                  'both notes open the chat, earlier note first');
select pg_temp.ok((select count(*) from push_outbox where kind = 'match' and profile_id in (:asel, :bolat)) = 2, 'both people get a match push');
select pg_temp.ok((select count(*) from push_outbox where kind = 'message' and profile_id in (:asel, :bolat)) = 0, 'notes do not trigger extra message pushes');
select pg_temp.ok((select title from push_outbox where profile_id = :asel and kind = 'match') = 'Бір қарқында!',
                  'push copy follows the recipient''s language (kk)');
select pg_temp.ok((select body from push_outbox where profile_id = :bolat and kind = 'match') like 'You and Asel%',
                  'push copy follows the recipient''s language (en)');
select pg_temp.ok((select tokens from push_outbox where profile_id = :asel and kind = 'match') = 1,
                  'the push is addressed to the person''s device');

-- ---------------------------------------------------------------
-- Message pushes, throttled per chat
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000002';
insert into messages (match_id, sender_id, body) values (:'m', :bolat, 'Meet at the gate at 8?');
insert into messages (match_id, sender_id, body) values (:'m', :bolat, 'Bring water!');
reset role;
select pg_temp.ok((select count(*) from push_outbox where profile_id = :asel and kind = 'message') = 1,
                  'a burst of messages sends one push per minute');
select pg_temp.ok((select title from push_outbox where profile_id = :asel and kind = 'message') = 'Bolat',
                  'message push names the sender, not the text');

-- ---------------------------------------------------------------
-- Like pushes are rate-limited; super likes always notify
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000004';
select swipe(:cara, 'like');
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000005';
select swipe(:cara, 'like', 'Ski day this weekend?');
reset role;
select pg_temp.ok((select count(*) from push_outbox where profile_id = :cara and kind = 'like') = 1,
                  'at most one like push every 6 hours');
set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000004';
select swipe(:asel, 'super');
reset role;
select pg_temp.ok((select count(*) from push_outbox where profile_id = :asel and kind = 'super') = 1, 'super likes notify');

-- ---------------------------------------------------------------
-- Likes received: Pro sees notes, free users only the count
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000003';
select pg_temp.ok((likes_received()->>'count')::int = 2 and jsonb_array_length(likes_received()->'profiles') = 0,
                  'free users see how many, not who');
reset role;
update profiles set pro_until = now() + interval '30 days' where id = :cara;
set role authenticated;
select pg_temp.ok((select bool_or(x->>'note' = 'Ski day this weekend?') from jsonb_array_elements(likes_received()->'profiles') x),
                  'Pro sees who liked them, with their note');

-- ---------------------------------------------------------------
-- "You're both going" and event reminders
-- ---------------------------------------------------------------
reset role;
insert into events (city, sport_code, title, meeting_point, starts_at)
values ('almaty', 'running', 'Saturday 5K', 'Medeu gate', now() + interval '100 minutes') returning id as ev \gset
insert into events (city, sport_code, title, meeting_point, starts_at)
values ('almaty', 'skiing', 'Ski day', 'Shymbulak', now() + interval '3 days') returning id as ev2 \gset
insert into event_attendees (event_id, profile_id) values (:'ev', :asel), (:'ev', :bolat), (:'ev2', :asel);

set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000001';
select pg_temp.ok(jsonb_array_length(shared_events(:'m')) = 1
                  and shared_events(:'m')->0->>'title' = 'Saturday 5K', 'match sees the one event both joined');
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000003';
select pg_temp.ok(jsonb_array_length(shared_events(:'m')) = 0, 'people outside the match see nothing');
do $$ begin
  perform send_event_reminders();
  raise exception 'FAIL: reminders callable by clients';
exception when insufficient_privilege then raise notice 'ok - reminders run on the server only';
end $$;
reset role;
select pg_temp.ok(send_event_reminders() = 2, 'two attendees reminded 2 hours before');
select pg_temp.ok(send_event_reminders() = 0, 'reminders are sent once');
select pg_temp.ok((select title from push_outbox where profile_id = :bolat and kind = 'event_reminder') = 'Saturday 5K',
                  'reminder names the event');

-- ---------------------------------------------------------------
-- Device changes hands; sign-out removes the token
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000003';
select register_push_token('ExponentPushToken[asel-phone]', 'ios');
reset role;
select pg_temp.ok((select profile_id from push_tokens where token = 'ExponentPushToken[asel-phone]') = :cara,
                  'a token moves to whoever signed in on that phone');
set role authenticated;
select unregister_push_token('ExponentPushToken[asel-phone]');
reset role;
select pg_temp.ok(not exists (select 1 from push_tokens where token = 'ExponentPushToken[asel-phone]'), 'sign-out removes the token');

\echo ENGAGEMENT TESTS PASSED
