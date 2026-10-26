-- Operations: see what fails, recover from it, and keep tables from growing forever.
--
--  1. ops_events: one place for problems (app crashes and errors, failed pushes, a picks
--     job member that errored, webhooks that need a retry). The app reports through
--     report_client_error (rate limited).
--  2. Push delivery is checked: every 10 minutes the replies to the push calls are read
--     back from pg_net, and failures are counted on the outbox row.
--  3. The 19:00 picks job: one member's error no longer cancels everyone's push.
--  4. RevenueCat: TRANSFER moves Pro to the account that restored it; refunded packs take
--     their credits back; REFUND_REVERSED gives Pro back; an event for an account that
--     doesn't exist yet is retried by RevenueCat instead of dropped.
--  5. Pruning: outbox 30 days, picks 14 days, ops events 90 days.
--  6. ops_health(): one call that says whether anything needs attention (used by the
--     daily GitHub check, which emails you when it fails).

-- ---------------------------------------------------------------
-- 1. ops_events
-- ---------------------------------------------------------------
create table if not exists public.ops_events (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  source     text not null,          -- 'app', 'push', 'picks', 'revenuecat', …
  level      text not null default 'error' check (level in ('info', 'warning', 'error')),
  message    text not null,
  detail     jsonb not null default '{}',
  profile_id uuid
);
create index if not exists ops_events_recent_idx on public.ops_events (at desc);
create index if not exists ops_events_source_idx on public.ops_events (source, at desc);
alter table public.ops_events enable row level security;
revoke all on public.ops_events from public, anon, authenticated;

create or replace function public.log_ops(p_source text, p_message text, p_detail jsonb default '{}',
                                          p_level text default 'error', p_profile uuid default null)
returns void
language sql security definer set search_path = public as $$
  insert into ops_events (source, level, message, detail, profile_id)
  values (p_source, p_level, left(p_message, 500), coalesce(p_detail, '{}'), p_profile)
$$;
revoke execute on function public.log_ops(text, text, jsonb, text, uuid) from public, anon, authenticated;

/** From the app: crashes and hangs (MetricKit) and failed requests. 30 an hour per person;
    anything past that is dropped quietly so a crash loop can't flood the table. */
create or replace function public.report_client_error(p_kind text, p_message text, p_detail jsonb default '{}')
returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  if p_kind not in ('crash', 'hang', 'error', 'cpu', 'disk', 'launch') then return; end if;
  if not rate_ok('clienterr:' || auth.uid(), 30, interval '1 hour') then return; end if;
  -- Keep details small: a crash report can be large.
  perform log_ops('app', p_kind || ': ' || coalesce(p_message, ''),
                  case when octet_length(coalesce(p_detail, '{}')::text) > 16000
                       then jsonb_build_object('truncated', left(p_detail::text, 16000)) else coalesce(p_detail, '{}') end,
                  case when p_kind in ('crash', 'error') then 'error' else 'warning' end,
                  auth.uid());
end $$;
grant execute on function public.report_client_error(text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------
-- 2. Push delivery
-- ---------------------------------------------------------------
alter table public.push_outbox
  add column if not exists delivery_status int,       -- HTTP status of the call (null = not read yet)
  add column if not exists delivery_failed int;       -- tokens Apple refused

create index if not exists push_outbox_unchecked_idx on public.push_outbox (created_at)
  where delivery_status is null and request_id is not null;

/** Reads pg_net's replies (kept ~6 hours) for pushes not checked yet. */
create or replace function public.record_push_delivery() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int := 0; v_failed int;  -- v_n: outbox rows checked this run
begin
  if to_regclass('net._http_response') is null then return 0; end if;
  execute $q$
    with r as (
      select o.id, coalesce(h.status_code, 0) as status, h.timed_out, h.error_msg,
             (select count(*) from jsonb_array_elements(
                        case when h.content is not null and left(h.content, 1) = '{'
                             then coalesce(h.content::jsonb -> 'sent', '[]') else '[]' end) s
               -- An uninstalled app (410) or a dead token is normal churn, not a failure.
               where (s ->> 'status')::int not in (200, 410)
                 and coalesce(s ->> 'reason', '') <> 'BadDeviceToken')::int as refused
        from push_outbox o join net._http_response h on h.id = o.request_id
       where o.delivery_status is null and o.request_id is not null
         and o.created_at > now() - interval '1 day'
    )
    update push_outbox o set delivery_status = r.status, delivery_failed = r.refused
      from r where r.id = o.id
  $q$;
  get diagnostics v_n = row_count;
  -- One summary line per run instead of one per push.
  select count(*) into v_failed from push_outbox
   where created_at > now() - interval '15 minutes' and (delivery_status <> 200 or delivery_failed > 0);
  if v_failed > 0 then
    perform log_ops('push', v_failed || ' push call(s) failed or were refused in the last 15 minutes',
                    jsonb_build_object('failed', v_failed), 'warning');
  end if;
  -- A reply that never came within an hour: pg_net gave up.
  update push_outbox set delivery_status = 0
   where delivery_status is null and request_id is not null and created_at < now() - interval '1 hour';
  return v_n;
end $$;
revoke execute on function public.record_push_delivery() from public, anon, authenticated;

-- ---------------------------------------------------------------
-- 3. The picks job survives one member's error
-- ---------------------------------------------------------------
create or replace function public.send_picks_push() returns int
language plpgsql security definer set search_path = public as $$
declare r profiles%rowtype; v_n int; n int := 0; v_errors int := 0;
begin
  for r in select * from profiles
            where not banned and not hidden and not paused
              and last_active_at > now() - interval '14 days' loop
    begin
      -- Already opened today's picks: nothing new to announce.
      continue when exists (select 1 from daily_picks d where d.profile_id = r.id and d.day = local_today());
      v_n := pick_candidates(r);
      continue when v_n = 0;
      perform queue_push(r.id, 'picks', null, jsonb_build_object('url', '/picks'), v_n::text);
      n := n + 1;
    exception when others then
      v_errors := v_errors + 1;
      if v_errors <= 20 then
        perform log_ops('picks', sqlerrm, jsonb_build_object('state', sqlstate), 'error', r.id);
      end if;
    end;
  end loop;
  if v_errors > 0 then
    perform log_ops('picks', v_errors || ' member(s) failed in the picks job; ' || n || ' pushes sent',
                    jsonb_build_object('failed', v_errors, 'sent', n), 'warning');
  end if;
  return n;
end $$;
revoke all on function public.send_picks_push() from public, anon, authenticated;

-- ---------------------------------------------------------------
-- 4. RevenueCat
-- ---------------------------------------------------------------
create or replace function public.apply_revenuecat_event(p_event jsonb)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_id      text := p_event->>'id';
  v_type    text := p_event->>'type';
  v_product text := p_event->>'product_id';
  v_user    uuid;
  v_exp     timestamptz;
  v_result  text;
  v_is_pro_product boolean;
  v_from    uuid[];
  v_to      uuid;
  v_moved   timestamptz;
  v_n       int;
begin
  if v_id is null or v_type is null then return 'ignored:malformed'; end if;

  -- An event that was waiting for its account is processed again on RevenueCat's retry.
  delete from purchase_events where id = v_id and result like 'retry:%';
  insert into purchase_events (id, app_user_id, type, product_id, payload)
  values (v_id, p_event->>'app_user_id', v_type, v_product, p_event)
  on conflict (id) do nothing;
  if not found then return 'duplicate'; end if;

  -- Restore on another account: Pro moves to the newest of the receiving accounts.
  if v_type = 'TRANSFER' then
    select array_agg(p.id) into v_from
      from jsonb_array_elements_text(coalesce(p_event->'transferred_from', '[]')) f
      join profiles p on p.id::text = f.value;
    select p.id into v_to
      from jsonb_array_elements_text(coalesce(p_event->'transferred_to', '[]')) t
      join profiles p on p.id::text = t.value
     order by p.created_at desc limit 1;
    if v_to is null then
      v_result := 'ignored:transfer_no_target';
    else
      select max(pro_until) into v_moved from profiles where id = any (coalesce(v_from, '{}')) and pro_until > now();
      if v_moved is not null then
        update profiles set pro_until = greatest(pro_until, v_moved) where id = v_to;
        update profiles set pro_until = now() where id = any (v_from) and id <> v_to and pro_until > now();
      end if;
      v_result := 'transferred:' || coalesce(v_moved::text, 'nothing_active');
    end if;
    update purchase_events set result = v_result where id = v_id;
    return v_result;
  end if;

  -- The app logs in to RevenueCat with the Supabase user id.
  begin
    v_user := (p_event->>'app_user_id')::uuid;
  exception when invalid_text_representation then
    v_user := null;
  end;
  if v_user is null then
    -- An anonymous purchase: it reaches the account later with a TRANSFER.
    update purchase_events set result = 'ignored:unknown_user' where id = v_id;
    return 'ignored:unknown_user';
  end if;
  if not exists (select 1 from profiles where id = v_user) then
    -- Bought in the moment between sign-in and the profile being created: ask for a retry.
    update purchase_events set result = 'retry:unknown_user' where id = v_id;
    perform log_ops('revenuecat', 'event for an account without a profile; RevenueCat will retry',
                    jsonb_build_object('event', v_id, 'type', v_type), 'warning');
    return 'retry:unknown_user';
  end if;

  v_is_pro_product := v_product like 'qadam_pro_%' or v_product like 'jur_pro_%'
                      or coalesce(p_event->'entitlement_ids', '[]'::jsonb) ? 'pro';
  if p_event ? 'expiration_at_ms' and p_event->>'expiration_at_ms' is not null then
    v_exp := to_timestamp((p_event->>'expiration_at_ms')::bigint / 1000.0);
  end if;

  if v_type in ('INITIAL_PURCHASE','RENEWAL','PRODUCT_CHANGE','UNCANCELLATION',
                'SUBSCRIPTION_EXTENDED','TEMPORARY_ENTITLEMENT_GRANT','REFUND_REVERSED') and v_is_pro_product then
    -- Webhooks can arrive out of order: an older renewal never moves the date back.
    update profiles set pro_until = greatest(pro_until, v_exp) where id = v_user and v_exp is not null
    returning pro_until into v_exp;
    v_result := 'pro_until:' || coalesce(v_exp::text, 'null');

  elsif v_type = 'EXPIRATION' and v_is_pro_product then
    update profiles set pro_until = least(coalesce(v_exp, now()), now()) where id = v_user;
    v_result := 'pro_expired';

  elsif v_type = 'CANCELLATION' and p_event->>'cancel_reason' = 'CUSTOMER_SUPPORT' then
    if v_is_pro_product then
      -- refund: remove access now
      update profiles set pro_until = now() where id = v_user;
      v_result := 'pro_refunded';
    elsif v_product ~ '^(jur|qadam)_(boost|super)_[0-9]{1,3}$' then
      -- A refunded pack takes back what it gave (whatever is still unused).
      v_n := substring(v_product from '[0-9]+$')::int;
      if v_product ~ '_boost_' then
        update profiles set boost_credits = greatest(boost_credits - v_n, 0) where id = v_user;
      else
        update profiles set super_like_credits = greatest(super_like_credits - v_n, 0) where id = v_user;
      end if;
      v_result := 'pack_refunded:' || v_product;
    else
      v_result := 'noop:refund_unknown_product';
    end if;

  elsif v_type = 'NON_RENEWING_PURCHASE' then
    -- Packs are named jur_boost_<n> / jur_super_<n> (or the older qadam_…); the number
    -- is what gets credited, so decoy sizes need no migration.
    if v_product ~ '^(jur|qadam)_boost_[0-9]{1,3}$' then
      update profiles set boost_credits = boost_credits + substring(v_product from '[0-9]+$')::int where id = v_user;
    elsif v_product ~ '^(jur|qadam)_super_[0-9]{1,3}$' then
      update profiles set super_like_credits = super_like_credits + substring(v_product from '[0-9]+$')::int where id = v_user;
    else
      v_result := 'ignored:unknown_product';
    end if;
    v_result := coalesce(v_result, 'credited:' || v_product);

  else
    v_result := 'noop:' || v_type;
  end if;

  update purchase_events set result = v_result where id = v_id;
  return v_result;
end $$;
revoke execute on function public.apply_revenuecat_event(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------
-- 5. Pruning
-- ---------------------------------------------------------------
create or replace function public.prune_ops_data() returns jsonb
language plpgsql security definer set search_path = public as $$
declare a int; b int; c int;
begin
  delete from push_outbox where created_at < now() - interval '30 days';
  get diagnostics a = row_count;
  delete from daily_picks where day < current_date - 14;
  get diagnostics b = row_count;
  delete from ops_events where at < now() - interval '90 days';
  get diagnostics c = row_count;
  return jsonb_build_object('push_outbox', a, 'daily_picks', b, 'ops_events', c);
end $$;
revoke execute on function public.prune_ops_data() from public, anon, authenticated;

-- ---------------------------------------------------------------
-- 6. One health check
-- ---------------------------------------------------------------
/** Last 24 hours. `ok` is false when something needs a look; `reasons` says what. */
create or replace function public.ops_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_errors int; v_crashes int; v_push_total int; v_push_bad int; v_retry int; v_cron_failed int := 0;
  v_reasons text[] := '{}';
begin
  select count(*) filter (where level = 'error'), count(*) filter (where source = 'app' and message like 'crash:%')
    into v_errors, v_crashes from ops_events where at > now() - interval '24 hours';
  select count(*), count(*) filter (where delivery_status <> 200 or delivery_failed > 0)
    into v_push_total, v_push_bad from push_outbox where created_at > now() - interval '24 hours';
  select count(*) into v_retry from purchase_events where result like 'retry:%' and created_at < now() - interval '1 hour';
  if to_regclass('cron.job_run_details') is not null then
    execute 'select count(*) from cron.job_run_details where status = ''failed'' and start_time > now() - interval ''24 hours'''
      into v_cron_failed;
  end if;

  if v_crashes >= 5 then v_reasons := v_reasons || (v_crashes || ' app crashes'); end if;
  if v_errors >= 50 then v_reasons := v_reasons || (v_errors || ' errors logged'); end if;
  if v_push_total >= 20 and v_push_bad::numeric / v_push_total > 0.1 then
    v_reasons := v_reasons || (v_push_bad || ' of ' || v_push_total || ' pushes failed');
  end if;
  if v_retry > 0 then v_reasons := v_reasons || (v_retry || ' purchases stuck waiting for an account'); end if;
  if v_cron_failed > 0 then v_reasons := v_reasons || (v_cron_failed || ' scheduled job runs failed'); end if;

  return jsonb_build_object(
    'ok', cardinality(v_reasons) = 0, 'reasons', to_jsonb(v_reasons),
    'errors', v_errors, 'crashes', v_crashes, 'pushes', v_push_total, 'pushes_failed', v_push_bad,
    'purchases_stuck', v_retry, 'cron_failed', v_cron_failed,
    'members', (select count(*) from profiles where not banned),
    'active_today', (select count(*) from profiles where last_active_at > now() - interval '24 hours'),
    'db_bytes', pg_database_size(current_database()));
end $$;
revoke execute on function public.ops_health() from public, anon, authenticated;
grant execute on function public.ops_health() to service_role;

-- ---------------------------------------------------------------
-- Schedules
-- ---------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('jur-push-delivery', '*/10 * * * *', 'select public.record_push_delivery()');
    perform cron.schedule('jur-prune-ops', '23 3 * * *', 'select public.prune_ops_data()');
  else
    raise notice 'pg_cron not installed: schedule record_push_delivery (every 10 min) and prune_ops_data (daily)';
  end if;
end $$;
