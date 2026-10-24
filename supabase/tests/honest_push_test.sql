-- The evening picks push only goes out when there's really someone (migration 20261024000022).
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

\set lone '''6b000000-0000-0000-0000-000000000001'''
\set a '''6b000000-0000-0000-0000-000000000002'''
\set b '''6b000000-0000-0000-0000-000000000003'''
\set photo '''https://test.supabase.co/storage/v1/object/public/photos/'''
insert into auth.users (id) values (:lone), (:a), (:b);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos) values
  (:lone, 'Lone', '1995-01-01', 'woman', 'men', 'emptytown', array[:photo || :lone || '/1.jpg']),
  (:a, 'Asel', '1995-01-01', 'woman', 'men', 'pairtown', array[:photo || :a || '/1.jpg']),
  (:b, 'Bolat', '1994-01-01', 'man', 'women', 'pairtown', array[:photo || :b || '/1.jpg']);

select pg_temp.ok(pick_candidates((select p from profiles p where id = :lone)) = 0, 'alone in a city: nobody to pick');
select pg_temp.ok(pick_candidates((select p from profiles p where id = :a)) = 1, 'one real person counts as one');

-- someone already passed is not counted again
insert into swipes (swiper_id, target_id, kind) values (:a, :b, 'pass');
select pg_temp.ok(pick_candidates((select p from profiles p where id = :a)) = 0, 'people already swiped are not counted');
delete from swipes where swiper_id = :a and target_id = :b;

-- the job runs, and never counts the person alone
select send_picks_push();
select pg_temp.ok(not exists (select 1 from push_outbox where profile_id = :lone and kind = 'picks'),
  'no picks push to someone with nobody to see');
select pg_temp.ok((select body from push_outbox where profile_id = :a and kind = 'picks' order by id desc limit 1)
  = 'Выбор дня готов: 1 человек для вас.', 'someone with a real person gets the push, with the real number');

-- the wording carries the real number, in each language
select pg_temp.ok((select body from push_text('ru', 'picks', null, '1')) = 'Выбор дня готов: 1 человек для вас.', 'ru: 1 человек');
select pg_temp.ok((select body from push_text('ru', 'picks', null, '3')) = 'Выбор дня готов: 3 человека для вас.', 'ru: 3 человека');
select pg_temp.ok((select body from push_text('en', 'picks', null, '1')) = 'Today''s picks are in: 1 person for you.', 'en: 1 person');
select pg_temp.ok((select body from push_text('en', 'picks', null, '4')) = 'Today''s picks are in: 4 people for you.', 'en: 4 people');
select pg_temp.ok((select body from push_text('kk', 'picks', null, '2')) = 'Күн таңдауы дайын: сізге 2 адам.', 'kk: 2 адам');

-- a paused profile gets no evening push
delete from push_outbox where kind = 'picks' and profile_id in (:a, :b);
update profiles set paused = true, hidden = true where id = :a;
select send_picks_push();
select pg_temp.ok(not exists (select 1 from push_outbox where profile_id = :a and kind = 'picks'),
  'paused people get no picks push');
select pg_temp.ok(not exists (select 1 from push_outbox where profile_id = :b and kind = 'picks'),
  '...and nobody is told about a paused person');

-- opened today's picks already: no push
update profiles set paused = false, hidden = false where id = :a;
insert into daily_picks (profile_id, day, picks) values (:a, local_today(), array[:b]::uuid[]);
select send_picks_push();
select pg_temp.ok(not exists (select 1 from push_outbox where profile_id = :a and kind = 'picks'),
  'no push after today''s picks were already opened');
