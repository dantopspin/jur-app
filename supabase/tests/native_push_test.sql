-- Native iOS push tokens and delivery bookkeeping.
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

\set nia '''c1000000-0000-0000-0000-000000000001'''
insert into auth.users (id) values (:nia);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, locale)
values (:nia, 'Nia', '1997-05-05', 'woman', 'men', 'almaty', '{n.jpg}', 'en');

set role authenticated;
set request.jwt.claim.sub = 'c1000000-0000-0000-0000-000000000001';
select register_push_token(repeat('ab', 32), 'ios');
do $$ begin
  perform register_push_token('ZZZ-not-hex', 'ios');
  raise exception 'FAIL: bad native token accepted';
exception when check_violation then raise notice 'ok - malformed native tokens are rejected';
end $$;
do $$ begin
  perform drop_push_token(repeat('ab', 32));
  raise exception 'FAIL: drop_push_token callable by clients';
exception when insufficient_privilege then raise notice 'ok - clients cannot drop tokens';
end $$;
reset role;

select pg_temp.ok((select count(*) from push_tokens where profile_id = :nia) = 1, 'a 64-hex APNs token is stored');
select queue_push(:nia, 'like', null, '{"url":"/likes"}');
select pg_temp.ok((select tokens from push_outbox where profile_id = :nia order by created_at desc limit 1) = 1,
  'queue_push counts the native token');
select drop_push_token(repeat('ab', 32));
select pg_temp.ok((select count(*) from push_tokens where profile_id = :nia) = 0, 'a dead token can be dropped');

-- JÜR product IDs turn on Pro even without entitlement ids in the event
set role service_role;
select pg_temp.ok(apply_revenuecat_event(jsonb_build_object(
  'id', 'evt-jur-1', 'type', 'INITIAL_PURCHASE', 'product_id', 'jur_pro_weekly',
  'expiration_at_ms', (extract(epoch from now() + interval '7 days') * 1000)::bigint,
  'app_user_id', 'c1000000-0000-0000-0000-000000000001')) like 'pro_until:%', 'jur_pro_weekly turns on Pro');
reset role;
select pg_temp.ok(is_pro('c1000000-0000-0000-0000-000000000001'), 'Nia is Pro');
