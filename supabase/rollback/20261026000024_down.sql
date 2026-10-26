-- Undoes 20261026000024_ops_webhooks.sql: the webhook, the picks job go back to their
-- previous versions; the ops log, delivery checks and pruning are removed (the ops log's
-- rows go with it). Run by hand only if 024 causes trouble; then remove the 024 row from
-- supabase_migrations.schema_migrations. Redeploy the previous Edge Functions too
-- (git checkout <previous commit> -- supabase/functions && supabase functions deploy …).
begin;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('jur-push-delivery');
    perform cron.unschedule('jur-prune-ops');
  end if;
exception when others then null;
end $$;

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
begin
  if v_id is null or v_type is null then return 'ignored:malformed'; end if;

  insert into purchase_events (id, app_user_id, type, product_id, payload)
  values (v_id, p_event->>'app_user_id', v_type, v_product, p_event)
  on conflict (id) do nothing;
  if not found then return 'duplicate'; end if;

  -- The app logs in to RevenueCat with the Supabase user id.
  begin
    v_user := (p_event->>'app_user_id')::uuid;
  exception when invalid_text_representation then
    v_user := null;
  end;
  if v_user is null or not exists (select 1 from profiles where id = v_user) then
    update purchase_events set result = 'ignored:unknown_user' where id = v_id;
    return 'ignored:unknown_user';
  end if;

  v_is_pro_product := v_product like 'qadam_pro_%' or v_product like 'jur_pro_%'
                      or coalesce(p_event->'entitlement_ids', '[]'::jsonb) ? 'pro';
  if p_event ? 'expiration_at_ms' and p_event->>'expiration_at_ms' is not null then
    v_exp := to_timestamp((p_event->>'expiration_at_ms')::bigint / 1000.0);
  end if;

  if v_type in ('INITIAL_PURCHASE','RENEWAL','PRODUCT_CHANGE','UNCANCELLATION',
                'SUBSCRIPTION_EXTENDED','TEMPORARY_ENTITLEMENT_GRANT') and v_is_pro_product then
    -- Webhooks can arrive out of order: an older renewal never moves the date back.
    -- (Expiry and refunds below still end Pro.)
    update profiles set pro_until = greatest(pro_until, v_exp) where id = v_user and v_exp is not null
    returning pro_until into v_exp;
    v_result := 'pro_until:' || coalesce(v_exp::text, 'null');

  elsif v_type = 'EXPIRATION' and v_is_pro_product then
    update profiles set pro_until = least(coalesce(v_exp, now()), now()) where id = v_user;
    v_result := 'pro_expired';

  elsif v_type = 'CANCELLATION' and v_is_pro_product
        and p_event->>'cancel_reason' = 'CUSTOMER_SUPPORT' then
    -- refund: remove access now
    update profiles set pro_until = now() where id = v_user;
    v_result := 'pro_refunded';

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

create or replace function public.send_picks_push() returns int
language plpgsql security definer set search_path = public as $$
declare r profiles%rowtype; v_n int; n int := 0;
begin
  for r in select * from profiles
            where not banned and not hidden and not paused
              and last_active_at > now() - interval '14 days' loop
    -- Already opened today's picks: nothing new to announce.
    continue when exists (select 1 from daily_picks d where d.profile_id = r.id and d.day = local_today());
    v_n := pick_candidates(r);
    continue when v_n = 0;
    perform queue_push(r.id, 'picks', null, jsonb_build_object('url', '/picks'), v_n::text);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.send_picks_push() from public, anon, authenticated;

drop function if exists public.ops_health();
drop function if exists public.prune_ops_data();
drop function if exists public.record_push_delivery();
drop function if exists public.report_client_error(text, text, jsonb);
drop function if exists public.log_ops(text, text, jsonb, text, uuid);
drop index if exists public.push_outbox_unchecked_idx;
alter table public.push_outbox drop column if exists delivery_status, drop column if exists delivery_failed;
drop table if exists public.ops_events;

commit;
