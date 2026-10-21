-- Fair exposure: people with a pile of unanswered likes are shown after others;
-- answering brings them back; newcomers get a fair start; boosts still win.
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

-- v: a man in Oskemen. pop and norm: two women, equally matched; pop is more recently active.
\set v    '''f0000000-0000-0000-0000-000000000001'''
\set pop  '''f0000000-0000-0000-0000-000000000002'''
\set norm '''f0000000-0000-0000-0000-000000000003'''
insert into auth.users (id) values (:v), (:pop), (:norm);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, created_at, last_active_at) values
  (:v,    'Vlad',  '1994-01-01', 'man',   'women', 'oskemen', '{v.jpg}', now() - interval '30 days', now()),
  (:pop,  'Polina','1996-01-01', 'woman', 'men',   'oskemen', '{p.jpg}', now() - interval '30 days', now() - interval '1 minute'),
  (:norm, 'Nora',  '1996-01-01', 'woman', 'men',   'oskemen', '{n.jpg}', now() - interval '30 days', now() - interval '2 hours');

-- 30 admirers (other city, so they don't appear in v's deck)
insert into auth.users (id) select ('f1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid from generate_series(1, 30) g;
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, created_at)
  select ('f1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'Fan' || g, '1990-01-01', 'man', 'women', 'atyrau', '{f.jpg}',
         now() - interval '30 days'
    from generate_series(1, 30) g;

create function pg_temp.deck() returns uuid[] language sql as $$
  select array_agg((x->>'id')::uuid order by o) from jsonb_array_elements(public.discover(20)) with ordinality as t(x, o)
$$;
grant execute on function pg_temp.deck() to public;

set role authenticated;
set request.jwt.claim.sub = 'f0000000-0000-0000-0000-000000000001';
select pg_temp.ok((pg_temp.deck())[1] = :pop, 'with no likes waiting, the more active person comes first');
reset role;

-- 12 unanswered likes for pop
insert into swipes (swiper_id, target_id, kind, created_at)
  select ('f1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, :pop, 'like', now() - interval '1 day' from generate_series(1, 12) g;
select pg_temp.ok(pending_likes(:pop) = 12 and exposure_tier(:pop) = 1, '12 unanswered likes: shown later');
set role authenticated;
set request.jwt.claim.sub = 'f0000000-0000-0000-0000-000000000001';
select pg_temp.ok((pg_temp.deck())[1] = :norm and (pg_temp.deck())[2] = :pop, 'someone with likes waiting is shown after others');
reset role;

-- 26 → the last tier
insert into swipes (swiper_id, target_id, kind, created_at)
  select ('f1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, :pop, 'like', now() - interval '1 day' from generate_series(13, 26) g;
select pg_temp.ok(exposure_tier(:pop) = 2, '26 unanswered likes: shown last');

-- old likes don't count
update swipes set created_at = now() - interval '20 days' where target_id = :pop
   and swiper_id in (select ('f1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid from generate_series(1, 20) g);
select pg_temp.ok(pending_likes(:pop) = 6 and exposure_tier(:pop) = 0, 'likes older than 14 days no longer count');
update swipes set created_at = now() - interval '1 day' where target_id = :pop;

-- answering brings her back (passes count as answers too)
insert into swipes (swiper_id, target_id, kind)
  select :pop, ('f1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'pass' from generate_series(1, 20) g;
select pg_temp.ok(pending_likes(:pop) = 6 and exposure_tier(:pop) = 0, 'answering likes brings someone straight back');
set role authenticated;
set request.jwt.claim.sub = 'f0000000-0000-0000-0000-000000000001';
select pg_temp.ok((pg_temp.deck())[1] = :pop, 'back to the normal order');
reset role;

-- a banned admirer's like doesn't count
update profiles set banned = true where id = 'f1000000-0000-0000-0000-000000000021';
select pg_temp.ok(pending_likes(:pop) = 5, 'likes from banned accounts are ignored');

-- newcomers get a fair start
\set nu '''f0000000-0000-0000-0000-000000000004'''
insert into auth.users (id) values (:nu);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, last_active_at) values
  (:nu, 'Nurai', '1997-01-01', 'woman', 'men', 'oskemen', '{nu.jpg}', now() - interval '5 hours');
select pg_temp.ok(is_newcomer(:nu) and not is_newcomer(:norm), 'a new member is a newcomer for 3 days');
set role authenticated;
set request.jwt.claim.sub = 'f0000000-0000-0000-0000-000000000001';
select pg_temp.ok((pg_temp.deck())[1] = :nu, 'a newcomer is shown before people already established');
reset role;

-- a paid boost still comes first, even for someone with likes waiting
insert into swipes (swiper_id, target_id, kind)
  select ('f1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, :norm, 'like' from generate_series(1, 30) g;
update profiles set boosted_until = now() + interval '30 minutes' where id = :norm;
set role authenticated;
set request.jwt.claim.sub = 'f0000000-0000-0000-0000-000000000001';
select pg_temp.ok((pg_temp.deck())[1] = :norm, 'a boost still puts someone first');

-- the app can't read these signals
do $$ begin
  perform public.pending_likes('f0000000-0000-0000-0000-000000000002');
  raise exception 'FAIL: pending_likes callable';
exception when insufficient_privilege then raise notice 'ok - like counts are server-only';
end $$;
reset role;

-- picks: the same demotion applies
update profiles set boosted_until = null where id = :norm;
select pg_temp.ok(exposure_tier(:norm) = 2, 'norm now has many likes waiting');
set role authenticated;
set request.jwt.claim.sub = 'f0000000-0000-0000-0000-000000000001';
select pg_temp.ok((select (daily_picks()->-1->>'id')::uuid) = :norm, 'in daily picks too, a pile of waiting likes moves someone down');
reset role;
\echo 'FAIR EXPOSURE TESTS PASSED'
