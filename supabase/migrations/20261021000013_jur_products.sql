-- Product IDs for the native app use the JÜR prefix (jur_pro_weekly, jur_pro_monthly,
-- jur_pro_6m; jur_boost_*, jur_super_*). The old qadam_* IDs keep working.
create or replace function public.apply_revenuecat_event(p_event jsonb) returns text
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
    update profiles set pro_until = v_exp where id = v_user;
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
    -- Packs are named qadam_boost_<n> / qadam_super_<n>; the number is what gets credited.
    -- (Lets you add decoy sizes like boost_3 next to boost_5 without a migration.)
    if v_product ~ '^qadam_boost_[0-9]{1,3}$' then
      update profiles set boost_credits = boost_credits + substring(v_product from '[0-9]+$')::int where id = v_user;
    elsif v_product ~ '^qadam_super_[0-9]{1,3}$' then
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
