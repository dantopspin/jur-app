-- Tests for operations and webhooks (migration 20261026000024). Runs last: it replaces
-- pick_candidates with a stand-in to test the picks job's error handling.
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

create function pg_temp.rc(p jsonb) returns text language sql as $$ select public.apply_revenuecat_event(p) $$;

\set a '''7a000000-0000-0000-0000-000000000001'''
\set b '''7a000000-0000-0000-0000-000000000002'''
\set late '''7a000000-0000-0000-0000-000000000009'''
\set as_a 'reset role; set request.jwt.claim.sub = ''7a000000-0000-0000-0000-000000000001''; set role authenticated;'
\set photo '''https://test.supabase.co/storage/v1/object/public/photos/'''
insert into auth.users (id) values (:a), (:b), (:late);
insert into profiles (id, name, birthdate, gender, interested_in, city, photos, created_at) values
  (:a, 'Aru', '1995-01-01', 'woman', 'men', 'oral', array[:photo || :a || '/1.jpg'], now() - interval '10 days'),
  (:b, 'Baur', '1994-01-01', 'man', 'women', 'oral', array[:photo || :b || '/1.jpg'], now());

-- RevenueCat: an account that doesn't exist yet is retried, then applied
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev1', 'type', 'INITIAL_PURCHASE', 'product_id', 'jur_pro_monthly',
       'app_user_id', :late, 'expiration_at_ms', (extract(epoch from now() + interval '30 days') * 1000)::bigint)) = 'retry:unknown_user',
       'a purchase for an account not created yet asks RevenueCat to retry');
insert into profiles (id, name, birthdate, gender, interested_in, city) values (:late, 'Late', '1996-01-01', 'woman', 'men', 'oral');
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev1', 'type', 'INITIAL_PURCHASE', 'product_id', 'jur_pro_monthly',
       'app_user_id', :late, 'expiration_at_ms', (extract(epoch from now() + interval '30 days') * 1000)::bigint)) like 'pro_until:%',
       'the retry is applied once the account exists');
select pg_temp.ok((select pro_until > now() + interval '29 days' from profiles where id = :late), 'and Pro is on');
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev1', 'type', 'INITIAL_PURCHASE', 'product_id', 'jur_pro_monthly',
       'app_user_id', :late)) = 'duplicate', 'a third delivery is a duplicate');
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev2', 'type', 'INITIAL_PURCHASE', 'product_id', 'jur_pro_monthly',
       'app_user_id', '$RCAnonymousID:abc')) = 'ignored:unknown_user', 'an anonymous purchase waits for its transfer');

-- TRANSFER: restore on another account moves Pro
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev3', 'type', 'TRANSFER',
       'transferred_from', jsonb_build_array(:late), 'transferred_to', jsonb_build_array(:a))) like 'transferred:%',
       'a transfer is applied');
select pg_temp.ok((select pro_until > now() + interval '29 days' from profiles where id = :a), 'the receiving account has Pro');
select pg_temp.ok((select pro_until <= now() from profiles where id = :late), 'the old account no longer has it');
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev4', 'type', 'TRANSFER',
       'transferred_from', jsonb_build_array(:b), 'transferred_to', jsonb_build_array('nobody'))) = 'ignored:transfer_no_target',
       'a transfer to an unknown account changes nothing');

-- Refunds and reversed refunds
update profiles set pro_until = now() + interval '20 days' where id = :b;
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev5', 'type', 'CANCELLATION', 'cancel_reason', 'CUSTOMER_SUPPORT',
       'product_id', 'jur_pro_monthly', 'app_user_id', :b)) = 'pro_refunded', 'a Pro refund ends Pro');
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev6', 'type', 'REFUND_REVERSED', 'product_id', 'jur_pro_monthly',
       'app_user_id', :b, 'expiration_at_ms', (extract(epoch from now() + interval '20 days') * 1000)::bigint)) like 'pro_until:%',
       'a reversed refund is applied');
select pg_temp.ok((select pro_until > now() + interval '19 days' from profiles where id = :b), 'and gives Pro back');
select pg_temp.rc(jsonb_build_object('id', 'ev7', 'type', 'NON_RENEWING_PURCHASE', 'product_id', 'jur_boost_5', 'app_user_id', :b));
select pg_temp.ok((select boost_credits = 5 from profiles where id = :b), 'a boost pack credits 5');
update profiles set boost_credits = 2 where id = :b;  -- three already used
select pg_temp.ok(pg_temp.rc(jsonb_build_object('id', 'ev8', 'type', 'CANCELLATION', 'cancel_reason', 'CUSTOMER_SUPPORT',
       'product_id', 'jur_boost_5', 'app_user_id', :b)) = 'pack_refunded:jur_boost_5', 'a refunded pack is taken back');
select pg_temp.ok((select boost_credits = 0 from profiles where id = :b), 'credits never go below zero');

-- App error reports
:as_a
select report_client_error('crash', 'EXC_BAD_ACCESS in ChatView', '{"build": "10"}');
select report_client_error('nonsense', 'ignored', '{}');
reset role;
select pg_temp.ok((select count(*) = 1 from ops_events where source = 'app'), 'a crash is recorded, an unknown kind is not');
select pg_temp.ok((select profile_id = :a and level = 'error' from ops_events where source = 'app'), 'with who and how bad');
update rate_counters set n = 30 where key like 'clienterr:%';
:as_a
select report_client_error('crash', 'loop', '{}');
reset role;
select pg_temp.ok((select count(*) = 1 from ops_events where source = 'app'), 'a crash loop is capped at 30 an hour');

-- Push delivery is read back from pg_net
create schema if not exists net;
create table if not exists net._http_response (id bigint primary key, status_code int, content text, timed_out boolean, error_msg text);
insert into push_outbox (profile_id, kind, title, body, tokens, request_id) values
  (:a, 'like', 't', 'b', 1, 901), (:a, 'like', 't', 'b', 2, 902), (:a, 'like', 't', 'b', 1, 903);
insert into net._http_response values
  (901, 200, '{"sent":[{"token":"aa","status":200}]}', false, null),
  (902, 200, '{"sent":[{"token":"bb","status":403,"reason":"InvalidProviderToken"},{"token":"cc","status":410}]}', false, null),
  (903, 500, 'provider token failed', false, null);
select record_push_delivery();
select pg_temp.ok((select delivery_status = 200 and delivery_failed = 0 from push_outbox where request_id = 901), 'a delivered push is marked delivered');
select pg_temp.ok((select delivery_failed = 1 from push_outbox where request_id = 902), 'a refused token counts; an uninstalled app does not');
select pg_temp.ok((select delivery_status = 500 from push_outbox where request_id = 903), 'a failed call is recorded');
select pg_temp.ok(exists (select 1 from ops_events where source = 'push'), 'and summarised in the ops log');

-- The picks job keeps going past one member's error
reset role;
update profiles set last_active_at = now(), paused = false, hidden = false;
create or replace function public.pick_candidates(me profiles) returns int language plpgsql as $$
begin
  if me.name = 'Baur' then raise exception 'boom'; end if;
  return 1;
end $$;
select send_picks_push();
select pg_temp.ok((select count(distinct profile_id) = 2 from push_outbox where kind = 'picks' and profile_id in (:a, :late)),
                  'the other members still get their picks push');
select pg_temp.ok(not exists (select 1 from push_outbox where kind = 'picks' and profile_id = :b), 'the failing one gets none');
select pg_temp.ok(exists (select 1 from ops_events where source = 'picks' and message = 'boom' and profile_id = :b),
                  'the failing member is logged');

-- Pruning and health
insert into ops_events (at, source, message) values (now() - interval '100 days', 'old', 'x');
select prune_ops_data();
select pg_temp.ok(not exists (select 1 from ops_events where source = 'old'), 'old ops events are pruned');
select pg_temp.ok((select ops_health() ? 'ok' and ops_health() ? 'reasons'), 'ops_health answers');
:as_a
select pg_temp.ok((select has_function_privilege('authenticated', 'public.ops_health()', 'execute')) = false,
                  'members cannot read ops_health');
