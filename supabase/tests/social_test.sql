-- Tests for prompts, date cards, undo, daily picks, travel, hidden contacts,
-- chat media and reactions, training-partner mode and double dates.
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

-- d1..d4: two women, two men (dating). b1, b2: training partners only.
\set d1 '''d0000000-0000-0000-0000-000000000001'''
\set d2 '''d0000000-0000-0000-0000-000000000002'''
\set d3 '''d0000000-0000-0000-0000-000000000003'''
\set d4 '''d0000000-0000-0000-0000-000000000004'''
\set b1 '''d0000000-0000-0000-0000-000000000005'''
\set b2 '''d0000000-0000-0000-0000-000000000006'''
insert into auth.users (id, email) values (:d1, 'Dana@Example.com'), (:d2, 'dina@example.com'), (:d3, 'dias@example.com'),
  (:d4, 'daur@example.com'), (:b1, 'bota@example.com'), (:b2, 'bolat@example.com');
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, mode) values
  (:d1, 'Dana', '1996-01-01', 'woman', 'men',   'shymkent', '{1.jpg}', 'dating'),
  (:d2, 'Dina', '1997-01-01', 'woman', 'men',   'shymkent', '{2.jpg}', 'both'),
  (:d3, 'Dias', '1995-01-01', 'man',   'women', 'shymkent', '{3.jpg}', 'dating'),
  (:d4, 'Daur', '1994-01-01', 'man',   'women', 'shymkent', '{4.jpg}', 'both'),
  (:b1, 'Bota', '1998-01-01', 'woman', 'men',   'shymkent', '{5.jpg}', 'buddy'),
  (:b2, 'Bolat','1993-01-01', 'man',   'women', 'shymkent', '{6.jpg}', 'buddy');
update city_launch set opens_at_members = 0 where city = 'shymkent';

-- ---------------------------------------------------------------
-- Prompts
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
insert into profile_prompts (profile_id, position, prompt_key, answer)
values (:d1, 0, 'perfect_sunday', 'Long run, then manti with friends');
do $$ begin
  insert into profile_prompts (profile_id, position, prompt_key, answer)
  values ('d0000000-0000-0000-0000-000000000003', 0, 'teach_me', 'nope');
  raise exception 'FAIL: wrote someone else''s prompt';
exception when insufficient_privilege then raise notice 'ok - prompts are your own';
end $$;
select pg_temp.ok(get_profile(:d1)->'prompts'->0->>'answer' = 'Long run, then manti with friends', 'prompts show on the card');

-- ---------------------------------------------------------------
-- Modes: dating vs training partners
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
select pg_temp.ok((select bool_and(x->>'name' in ('Dana', 'Dina')) and count(*) = 2 from jsonb_array_elements(discover(20)) x),
                  'dating-only people see only dating profiles');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000005';
select pg_temp.ok((select array_agg(x->>'name' order by x->>'name') from jsonb_array_elements(discover(20)) x)
                  = array['Bolat', 'Daur', 'Dina'], 'training-partner mode finds people open to training');
select pg_temp.ok((select bool_and(x->>'match_mode' = 'buddy') from jsonb_array_elements(discover(20)) x),
                  'cards say why they were shown');
reset role;
update profiles set buddy_with = 'men' where id = :b2;
set role authenticated;
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(discover(20)) x where x->>'name' = 'Bolat'),
                  'training-partner preferences are mutual');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000004';
select pg_temp.ok(jsonb_array_length(discover(20, 'buddy')) = 3 and jsonb_array_length(discover(20, 'dating')) = 2,
                  '"both" people can browse each mode separately');

-- like with a note on a prompt → match kind and opening message context
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
select swipe(:d1, 'like', 'Manti after the run? I know a place.', 'perfect_sunday');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
select swipe(:d3, 'like')->>'match_id' as m \gset
select pg_temp.ok((select kind from matches where id = :'m') = 'dating', 'dating likes make a dating match');
select pg_temp.ok((select payload->'prompt'->>'key' from messages where match_id = :'m' order by created_at limit 1) = 'perfect_sunday',
                  'a note on a prompt carries the prompt into the chat');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000005';
select swipe(:d2, 'like');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000002';
select swipe(:b1, 'like')->>'match_id' as bm \gset
reset role;
select pg_temp.ok((select kind from matches where id = :'bm') = 'buddy', 'training partners get a buddy match');
select pg_temp.ok(exists (select 1 from push_outbox where kind = 'buddy_match' and profile_id = :b1), 'buddy match has its own push');

-- ---------------------------------------------------------------
-- Chat: photos, replies, reactions
-- ---------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
-- photo safety: no photos until both people have written (d3 sent the opening note, d1 hasn't written yet)
select set_config('test.m', :'m', false);
do $$ begin
  insert into messages (match_id, sender_id, body, kind, media_path)
  values (current_setting('test.m')::uuid, 'd0000000-0000-0000-0000-000000000003', '', 'photo', current_setting('test.m') || '/early.jpg');
  raise exception 'FAIL: photo before both wrote';
exception when insufficient_privilege then
  if sqlerrm <> 'photo_too_soon' then raise exception 'FAIL: wrong refusal %', sqlerrm; end if;
  raise notice 'ok - no photos until both people have written';
end $$;
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
insert into messages (match_id, sender_id, body) values (:'m', :d1, 'Manti sounds great');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
insert into messages (match_id, sender_id, body, kind, media_path)
values (:'m', :d3, '', 'photo', :'m' || '/trail.jpg') returning id as ph \gset
do $$ begin
  insert into messages (match_id, sender_id, body, kind, media_path)
  values ((select id from matches where kind = 'dating' limit 1), 'd0000000-0000-0000-0000-000000000003', '', 'photo', 'elsewhere/x.jpg');
  raise exception 'FAIL: media outside the match folder';
exception when insufficient_privilege then raise notice 'ok - media must live in the match folder';
end $$;
do $$ begin
  insert into messages (match_id, sender_id, body, kind)
  values ((select id from matches where kind = 'dating' limit 1), 'd0000000-0000-0000-0000-000000000003', '', 'voice');
  raise exception 'FAIL: voice without file';
exception when check_violation then raise notice 'ok - voice notes need a file';
end $$;
do $$ begin
  insert into messages (match_id, sender_id, body, kind, payload)
  values ((select id from matches where kind = 'dating' limit 1), 'd0000000-0000-0000-0000-000000000003', '', 'date', '{}');
  raise exception 'FAIL: client wrote a date card';
exception when insufficient_privilege then raise notice 'ok - date cards come only from the server';
end $$;
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
insert into messages (match_id, sender_id, body, reply_to) values (:'m', :d1, 'Where is this?', :'ph');
select react(:'ph', 'fire');
select pg_temp.ok((chat_messages(:'m')->0->'reply'->>'kind') = 'photo', 'replies carry a preview of the quoted message');
select pg_temp.ok((select x->'reactions'->0->>'reaction' from jsonb_array_elements(chat_messages(:'m')) x where x->>'id' = :'ph') = 'fire',
                  'reactions are attached to messages');
select react(:'ph', 'fire');
select pg_temp.ok((select jsonb_array_length(x->'reactions') from jsonb_array_elements(chat_messages(:'m')) x where x->>'id' = :'ph') = 0,
                  'the same reaction again removes it');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000005';
select pg_temp.ok(jsonb_array_length(chat_messages(:'m')) = 0, 'outsiders cannot read a chat');

-- ---------------------------------------------------------------
-- Suggest a date
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
select pg_temp.ok(propose_date(:'m', 'running', now() - interval '1 hour', 'Park')->>'error' = 'bad_time', 'dates must be in the future');
select propose_date(:'m', 'running', now() + interval '2 days', 'Central park gate')->>'message_id' as dm \gset
select pg_temp.ok(respond_date(:'dm', 'accepted')->>'error' = 'not_found', 'you cannot answer your own suggestion');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
select pg_temp.ok((respond_date(:'dm', 'accepted')->>'ok')::boolean, 'the other person says yes');
select pg_temp.ok(respond_date(:'dm', 'declined')->>'error' = 'already_answered', 'one answer per suggestion');
reset role;
select pg_temp.ok((select payload->>'status' from messages where id = :'dm') = 'accepted', 'the card shows the answer');
select pg_temp.ok(exists (select 1 from push_outbox where kind = 'date_answer' and profile_id = :d3), 'the suggester hears back');
insert into events (city, sport_code, title, meeting_point, starts_at)
values ('shymkent', 'running', 'Riverside 5K', 'Riverside', now() + interval '3 days') returning id as ev \gset
set role authenticated;
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
select propose_date(:'m', null, null, null, :'ev')->>'message_id' as dm2 \gset
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
select respond_date(:'dm2', 'accepted');
select pg_temp.ok((get_event(:'ev')->>'i_am_going')::boolean, 'saying yes to an event plan joins the event');

-- ---------------------------------------------------------------
-- Undo (Pro) and travel (Pro)
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000004';
select swipe(:d2, 'pass');
select pg_temp.ok(rewind()->>'error' = 'pro_only', 'undo is a Pro feature');
select pg_temp.ok(set_travel('almaty', 3)->>'error' = 'pro_only', 'travel mode is a Pro feature');
reset role;
update profiles set pro_until = now() + interval '30 days' where id = :d4;
set role authenticated;
select pg_temp.ok(rewind()->'profile'->>'name' = 'Dina', 'undo brings the last pass back');
select pg_temp.ok(rewind()->>'error' = 'nothing_to_undo', 'only the last pass can be undone');
select swipe(:d2, 'like');
select pg_temp.ok(rewind()->>'error' = 'nothing_to_undo', 'likes are not undone');
select pg_temp.ok(set_travel('nowhere', 3)->>'error' = 'bad_city', 'travel only to known cities');
select pg_temp.ok((set_travel('almaty', 3)->>'ok')::boolean, 'set a trip');
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(discover(50)) x where x->>'city' = 'shymkent'),
                  'while travelling, Discover shows the trip city');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000002';
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(discover(50)) x where x->>'name' = 'Daur'),
                  'travellers leave their home city for the trip');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000004';
select clear_travel();
select pg_temp.ok(get_profile(:d4)->>'travel_city' is null, 'end the trip');

-- ---------------------------------------------------------------
-- Daily picks
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000006';
insert into profile_sports (profile_id, sport_code) values (:b2, 'running');
reset role;
insert into profile_sports (profile_id, sport_code) values (:d4, 'running');
update profiles set buddy_with = 'everyone' where id = :b2;
set role authenticated;
select daily_picks() as p1 \gset
select pg_temp.ok(jsonb_array_length(:'p1'::jsonb) between 1 and 5, 'up to five picks a day');
select pg_temp.ok((:'p1'::jsonb)->0->>'name' = 'Daur', 'shared sports rank first');
select pg_temp.ok(daily_picks() = :'p1'::jsonb, 'picks stay the same all day');

-- ---------------------------------------------------------------
-- Hide from contacts (both ways)
-- ---------------------------------------------------------------
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000002';
select pg_temp.ok(set_contact_hides(array[encode(sha256(convert_to('qadam:bota@example.com', 'UTF8')), 'hex'), 'nonsense']) = 1,
                  'only valid hashes are stored');
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(discover(50)) x where x->>'name' = 'Bota'),
                  'people in my contacts are hidden from me');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000005';
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(discover(50)) x where x->>'name' = 'Dina'),
                  '…and I am hidden from them');
select set_phone_hash(encode(sha256(convert_to('qadam:77011234567', 'UTF8')), 'hex'));
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
select set_contact_hides(array[encode(sha256(convert_to('qadam:77011234567', 'UTF8')), 'hex')]);
reset role;
select pg_temp.ok(hidden_between(:d3, :b1), 'phone numbers work too, if the person added theirs');
set role authenticated;
do $$ begin
  perform * from contact_hides;
  raise exception 'FAIL: hashes readable';
exception when insufficient_privilege then raise notice 'ok - contact hashes are never readable';
end $$;

-- ---------------------------------------------------------------
-- Double dates
-- ---------------------------------------------------------------
reset role;
select member_no as d2no from profiles where id = :d2 \gset
select member_no as d4no from profiles where id = :d4 \gset
set role authenticated;
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
select pg_temp.ok((duo_invite(:d2no)->>'ok')::boolean, 'invite a friend by member number');
select pg_temp.ok(duo_invite(:d2no)->>'error' = 'already_in_duo', 'one duo at a time');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000002';
select pg_temp.ok(jsonb_array_length(my_duo()->'invites') = 1, 'the friend sees the invite');
select duo_respond((my_duo()->'invites'->0->>'id')::uuid, true);
select pg_temp.ok(my_duo()->'duo'->>'status' = 'active', 'accepted duos are active');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
select duo_invite(:d4no);
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000004';
select duo_respond((my_duo()->'invites'->0->>'id')::uuid, true);
select pg_temp.ok(jsonb_array_length(duo_discover()) = 1, 'duos see compatible duos in their city');
select (duo_discover()->0->>'duo_id') as womenduo \gset
select pg_temp.ok(duo_swipe(:'womenduo', 'like')->>'match_id' is null, 'one side liking is not a match');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000002';
select duo_swipe((duo_discover()->0->>'duo_id')::uuid, 'like') as dmres \gset
reset role;
select pg_temp.ok((select count(*) from duo_matches) = 1, 'both duos liking each other is a double date match');
select pg_temp.ok((select count(*) from push_outbox where kind = 'duo_match') = 4, 'all four people hear about it');
select id as dmatch from duo_matches limit 1 \gset
set role authenticated;
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000003';
insert into duo_messages (duo_match_id, sender_id, body) values (:'dmatch', :d3, 'Padel doubles on Saturday?');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
select pg_temp.ok(duo_feed(:'dmatch')->0->>'body' = 'Padel doubles on Saturday?', 'all four share one chat');
select pg_temp.ok(jsonb_array_length(my_duo()->'matches') = 1, 'double-date chats are listed');
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000005';
do $$ begin
  insert into duo_messages (duo_match_id, sender_id, body)
  values ((select id from duo_matches limit 1), 'd0000000-0000-0000-0000-000000000005', 'hi');
  raise exception 'FAIL: outsider posted';
exception when insufficient_privilege then raise notice 'ok - only the four can post';
end $$;
set request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';
select duo_leave();
select pg_temp.ok(my_duo()->'duo' = 'null'::jsonb, 'leave the duo');
reset role;

\echo SOCIAL TESTS PASSED
