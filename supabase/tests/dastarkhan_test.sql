-- Tests for event "after" plans and the card back.
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

\set host '''b0000000-0000-0000-0000-000000000001'''
\set guest '''b0000000-0000-0000-0000-000000000002'''
insert into auth.users (id) values (:host), (:guest);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, is_host) values
  (:host, 'Madina', '1994-04-04', 'woman', 'men', 'almaty', '{m.jpg}', true),
  (:guest, 'Nurlan', '1993-03-03', 'man', 'women', 'almaty', '{n.jpg}', false);

set role authenticated;
set request.jwt.claim.sub = 'b0000000-0000-0000-0000-000000000001';
insert into events (host_id, city, sport_code, title, meeting_point, starts_at, after_text)
values (auth.uid(), 'almaty', 'running', 'Long table run', 'Botanical garden', now() + interval '3 days', 'Tea at the long table')
returning id as ev \gset
select pg_temp.ok(get_event(:'ev')->>'after_text' = 'Tea at the long table', 'events carry the "after" plan');
update events set after_text = 'Coffee at Nedelka' where id = :'ev';
select pg_temp.ok(get_event(:'ev')->>'after_text' = 'Coffee at Nedelka', 'hosts can change the "after" plan');
do $$ begin
  update events set after_text = 'x' where host_id = auth.uid();
  raise exception 'FAIL: one-letter after_text accepted';
exception when check_violation then raise notice 'ok - "after" plan needs at least two characters';
end $$;

set request.jwt.claim.sub = 'b0000000-0000-0000-0000-000000000002';
select pg_temp.ok(get_profile(:host)->>'member_since' = to_char(now() at time zone 'Asia/Almaty', 'YYYY-MM'),
                  'profile card shows the month the member joined');
select pg_temp.ok((get_profile(:host) ? 'member_no') and (get_profile(:host) ? 'events_attended'),
                  'card back still has member number and events');
do $$ begin
  perform public.profile_card('b0000000-0000-0000-0000-000000000001');
  raise exception 'FAIL: profile_card callable';
exception when insufficient_privilege then raise notice 'ok - profile_card stays internal';
end $$;
reset role;

\echo DASTARKHAN TESTS PASSED
