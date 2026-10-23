-- Fixes from the logic audit of 23 Oct 2026. Each one has a test in supabase/tests/audit_test.sql.
--
--  1. Two people liking each other at the same moment no longer lose the match.
--  2. The event check-in code can't be guessed: 5 wrong tries, then a 10-minute wait.
--  3. Saying yes to a date at an event follows the event's rules (full, cancelled, started).
--  5. A referral counts once the friend is verified, not when an empty profile signs up.
--  6. A renewal that arrives late never shortens Pro.
--  7. Packs named jur_boost_<n> / jur_super_<n> are credited too.
--  8. Profile photos must be your own uploads in this project's storage.
--  9. Undo can bring back a specific person (the one the toast names).
-- 11. Events and clubs follow travel mode, like Discover.
-- 16. Only people who actually crossed paths with someone count towards hiding them.
-- 17. A banned person who deletes the account can't come back with the same email.

-- ---------------------------------------------------------------
-- 1. swipe: one lock per pair
-- ---------------------------------------------------------------
-- The lock per swiper stops quota races, but two people swiping each other ran in
-- parallel: neither saw the other's like yet, so no match was made, and since both had
-- swiped they never saw each other again. A second lock on the pair makes the later of
-- the two wait and then see the first like. (Always taken after the swiper's own lock,
-- and nobody waits for a swiper lock while holding a pair lock, so it can't deadlock.)
create or replace function public.swipe(p_target uuid, p_kind text, p_note text default null, p_prompt text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me         uuid := auth.uid();
  v_pro      boolean;
  v_count    int;
  v_match_id uuid;
  v_new_match boolean := false;
  v_used_credit boolean := false;
  v_note     text := nullif(btrim(coalesce(p_note, '')), '');
  theirs     swipes%rowtype;
  v_prompt   text := case when p_kind = 'pass' then null else p_prompt end;
  a profiles%rowtype; b profiles%rowtype;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if p_kind not in ('pass','like','super') then raise exception 'bad_kind'; end if;
  if p_target = me then raise exception 'self_swipe'; end if;
  if p_kind = 'pass' then v_note := null; end if;
  if char_length(v_note) > 140 then return jsonb_build_object('ok', false, 'error', 'note_too_long'); end if;
  if not exists (select 1 from profiles where id = me and not banned) then raise exception 'no_profile'; end if;
  if not exists (select 1 from profiles where id = p_target and not banned and not hidden)
     or blocked_between(me, p_target) or hidden_between(me, p_target) then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  -- one swipe at a time per user, so the quota checks can't be raced
  perform pg_advisory_xact_lock(hashtext('swipe:' || me::text));
  -- and one at a time per pair, so a mutual like is always seen by the second swipe
  perform pg_advisory_xact_lock(hashtext('pair:' || least(me, p_target)::text || greatest(me, p_target)::text));
  v_pro := is_pro(me);

  if p_kind = 'like' and not v_pro then
    select count(*) into v_count from swipes
     where swiper_id = me and kind = 'like' and created_at >= local_day_start();
    if v_count >= cfg('free_daily_likes') then
      return jsonb_build_object('ok', false, 'error', 'like_limit');
    end if;
  end if;

  if p_kind = 'super' then
    select count(*) into v_count from swipes
     where swiper_id = me and kind = 'super' and created_at >= local_day_start();
    if v_count >= (case when v_pro then cfg('pro_daily_supers') else cfg('free_daily_supers') end) then
      update profiles set super_like_credits = super_like_credits - 1
       where id = me and super_like_credits > 0;
      if not found then
        return jsonb_build_object('ok', false, 'error', 'super_limit');
      end if;
      v_used_credit := true;
    end if;
  end if;

  insert into swipes (swiper_id, target_id, kind, note, note_prompt) values (me, p_target, p_kind, v_note, v_prompt)
  on conflict (swiper_id, target_id) do update set kind = excluded.kind, note = excluded.note,
    note_prompt = excluded.note_prompt, created_at = now();

  update profiles set last_active_at = now() where id = me;

  if p_kind in ('like','super') then
    select * into theirs from swipes where swiper_id = p_target and target_id = me and kind in ('like','super');
    if found then
      select * into a from profiles where id = me;
      select * into b from profiles where id = p_target;
      insert into matches (user_a, user_b, kind) values (least(me, p_target), greatest(me, p_target),
                                                      case when dating_ok(a, b) then 'dating' else 'buddy' end)
      on conflict (user_a, user_b) do nothing
      returning id into v_match_id;
      v_new_match := v_match_id is not null;
      if not v_new_match then
        select id into v_match_id from matches
         where user_a = least(me, p_target) and user_b = greatest(me, p_target) and unmatched_at is null;
      end if;
      -- Notes open the conversation: theirs first (it was sent first), then mine.
      if v_new_match then
        perform set_config('qadam.mute_message_push', 'on', true);
        if theirs.note is not null then
          insert into messages (match_id, sender_id, body, created_at, payload)
          values (v_match_id, p_target, theirs.note, least(theirs.created_at, now() - interval '1 second'),
                  prompt_context(me, theirs.note_prompt));
        end if;
        if v_note is not null then
          insert into messages (match_id, sender_id, body, payload)
          values (v_match_id, me, v_note, prompt_context(p_target, v_prompt));
        end if;
        perform set_config('qadam.mute_message_push', 'off', true);
      end if;
    elsif p_kind = 'super' then
      perform queue_push(p_target, 'super', null, jsonb_build_object('url', '/discover'));
    else
      -- at most one "someone liked you" push every 6 hours
      update profiles set last_like_push_at = now()
       where id = p_target and (last_like_push_at is null or last_like_push_at < now() - interval '6 hours');
      if found then
        perform queue_push(p_target, 'like', null, jsonb_build_object('url', '/likes'));
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'match_id', v_match_id, 'used_credit', v_used_credit);
end $$;

-- ---------------------------------------------------------------
-- 2. check_in: a limit on wrong codes
-- ---------------------------------------------------------------
-- The code has 4 digits and two are valid at a time, so a script used to get in from home
-- in a few thousand tries. Now: 5 wrong codes, then a 10-minute wait (per person and
-- event). The attendance check also comes first, so people who aren't going can't
-- probe codes at all.
alter table public.event_attendees
  add column if not exists checkin_fails int not null default 0,
  add column if not exists checkin_fail_at timestamptz;

create or replace function public.check_in(p_event uuid, p_code text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e events%rowtype;
  a event_attendees%rowtype;
  v_wait timestamptz;
begin
  select * into e from events where id = p_event;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if now() < e.starts_at - interval '30 minutes'
     or now() > e.starts_at + make_interval(mins => e.duration_min) then
    return jsonb_build_object('ok', false, 'error', 'not_now');
  end if;
  select * into a from event_attendees
   where event_id = p_event and profile_id = auth.uid() and status = 'going' for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_going'); end if;
  if a.checked_in_at is not null then return jsonb_build_object('ok', true); end if;

  -- The host checks in without a code; everyone else needs this minute's or the previous one's.
  if e.host_id is distinct from auth.uid() then
    if a.checkin_fails >= 5 and a.checkin_fail_at > now() - interval '10 minutes' then
      v_wait := a.checkin_fail_at + interval '10 minutes';
      return jsonb_build_object('ok', false, 'error', 'too_many_tries', 'retry_at', v_wait);
    end if;
    if coalesce(p_code, '') not in (checkin_code(p_event, now()), checkin_code(p_event, now() - interval '1 minute')) then
      update event_attendees
         set checkin_fails = case when checkin_fail_at > now() - interval '10 minutes' then checkin_fails + 1 else 1 end,
             checkin_fail_at = now()
       where event_id = p_event and profile_id = auth.uid();
      return jsonb_build_object('ok', false, 'error', 'bad_code');
    end if;
  end if;

  update event_attendees set checked_in_at = now(), checkin_fails = 0, checkin_fail_at = null
   where event_id = p_event and profile_id = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------
-- 3. respond_date: the event's rules apply
-- ---------------------------------------------------------------
-- Saying yes used to put you on an event's list even when it was full, cancelled or had
-- already started, and worked after an unmatch. Now the pair must still be matched, a
-- plan for an event that's cancelled or started can't be accepted, and a full event
-- accepts the date without the spot (the answer says so: joined = false, reason 'full').
create or replace function public.respond_date(p_message uuid, p_answer text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m messages%rowtype;
  v_name text;
  v_event uuid;
  e events%rowtype;
  v_join jsonb;
  v_joined boolean;
begin
  if p_answer not in ('accepted','declined') then raise exception 'bad_answer'; end if;
  select * into m from messages where id = p_message and kind = 'date' for update;
  if not found or m.sender_id = auth.uid() or not exists (
       select 1 from matches x where x.id = m.match_id and auth.uid() in (x.user_a, x.user_b)
          and x.unmatched_at is null and not blocked_between(x.user_a, x.user_b)) then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if m.payload->>'status' <> 'pending' then return jsonb_build_object('ok', false, 'error', 'already_answered'); end if;

  v_event := (m.payload->>'event_id')::uuid;
  if p_answer = 'accepted' and v_event is not null then
    select * into e from events where id = v_event;
    if not found or e.cancelled then return jsonb_build_object('ok', false, 'error', 'event_cancelled'); end if;
    if e.starts_at < now() then return jsonb_build_object('ok', false, 'error', 'event_started'); end if;
  end if;

  update messages set payload = payload || jsonb_build_object('status', p_answer, 'answered_at', now()), updated_at = now()
   where id = p_message;

  -- saying yes to an event plan also puts you on the list (gold wristband), by the usual rules
  if p_answer = 'accepted' and v_event is not null then
    v_join := join_event(v_event, true);
    v_joined := coalesce((v_join->>'ok')::boolean, false);
  end if;

  select name into v_name from profiles where id = auth.uid();
  perform queue_push(m.sender_id, 'date_answer', v_name, jsonb_build_object('url', '/chat/' || m.match_id), p_answer);
  if v_event is null or p_answer = 'declined' then return jsonb_build_object('ok', true); end if;
  return jsonb_build_object('ok', true, 'joined', v_joined, 'reason', case when v_joined then null else v_join->>'error' end);
end $$;

-- ---------------------------------------------------------------
-- 5. Referrals count once the friend is verified
-- ---------------------------------------------------------------
-- Two empty sign-ups (an email code each) were enough for a week of Pro. A friend now
-- counts when their profile is verified (a selfie a moderator approved), once per friend.
create table if not exists public.referral_credits (
  referred_id uuid primary key references profiles(id) on delete cascade,
  referrer_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.referral_credits enable row level security;
revoke all on public.referral_credits from public, anon, authenticated;

create or replace function public.on_profile_referral()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if new.referred_by is null or new.verification_status <> 'approved' then return new; end if;
  if tg_op = 'UPDATE' and old.referred_by is not distinct from new.referred_by
     and old.verification_status is not distinct from new.verification_status then
    return new;
  end if;
  insert into referral_credits (referred_id, referrer_id) values (new.id, new.referred_by)
  on conflict (referred_id) do nothing;
  if not found then return new; end if;
  select count(*) into v_count from referral_credits where referrer_id = new.referred_by;
  if v_count % cfg('referrals_for_bonus') = 0 then
    update profiles
       set bonus_pro_until = greatest(coalesce(bonus_pro_until, now()), now())
                             + make_interval(days => cfg('referral_bonus_days'))
     where id = new.referred_by;
  end if;
  return new;
end $$;

drop trigger if exists profiles_after_referral on public.profiles;
create trigger profiles_after_referral after insert or update of referred_by, verification_status on public.profiles
  for each row execute function public.on_profile_referral();

-- Progress on Me: friends who are verified count; the rest are shown as waiting.
create or replace function public.my_referrals() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_count int;
  v_joined int;
  v_every int := cfg('referrals_for_bonus');
begin
  select count(*) into v_count from referral_credits where referrer_id = auth.uid();
  select count(*) into v_joined from profiles where referred_by = auth.uid();
  return jsonb_build_object(
    'count', v_count,
    'pending', greatest(v_joined - v_count, 0),
    'every', v_every,
    'toNext', v_every - (v_count % v_every),
    'bonusDays', cfg('referral_bonus_days'));
end $$;
revoke all on function public.my_referrals() from public, anon;
grant execute on function public.my_referrals() to authenticated;

-- Friends who were already verified before this change still count.
insert into referral_credits (referred_id, referrer_id)
select id, referred_by from profiles where referred_by is not null and verification_status = 'approved'
on conflict do nothing;

-- ---------------------------------------------------------------
-- 6 + 7. RevenueCat: late renewals and jur_ pack names
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

-- ---------------------------------------------------------------
-- 8. Photos: only your own uploads in this project's storage
-- ---------------------------------------------------------------
-- The photos column can be written straight through the API, so someone could show an
-- outside picture or another member's photo on their card. Every new entry must now be
-- https://<this project>/storage/v1/object/public/photos/<your id>/<file>. Photos already
-- on a profile stay as they are. The host comes from app_settings 'jur.supabase_host'
-- when set (e.g. abcd.supabase.co); otherwise any *.supabase.co host is accepted.
create or replace function public.photo_url_ok(p_url text, p_owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_url ~ ('^https://' || coalesce(nullif(app_setting('jur.supabase_host'), ''), '[a-z0-9-]+\.supabase\.co')
                  || '/storage/v1/object/public/photos/' || p_owner::text || '/[^/?#]+$')
$$;
revoke all on function public.photo_url_ok(text, uuid) from public, anon;
grant execute on function public.photo_url_ok(text, uuid) to authenticated;

-- Runs as the caller, so it applies to the app (the API roles) and not to the dashboard,
-- the service role or test seeds.
create or replace function public.check_profile_photos() returns trigger
language plpgsql set search_path = public as $$
declare u text;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  foreach u in array coalesce(new.photos, '{}') loop
    if tg_op = 'UPDATE' and u = any (coalesce(old.photos, '{}')) then continue; end if;
    if not photo_url_ok(u, new.id) then
      raise exception 'bad_photo_url' using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists profiles_photos_check on public.profiles;
create trigger profiles_photos_check before insert or update of photos on public.profiles
  for each row execute function public.check_profile_photos();

-- ---------------------------------------------------------------
-- 9. rewind: bring back a particular person
-- ---------------------------------------------------------------
-- "Пропущено · Вернуть" names one person; undo used to bring back whoever was passed
-- last, or nothing if a like came after. With a target it brings back that person (if
-- they were passed). Without one it is the Undo button: the last swipe, if a pass.
drop function if exists public.rewind();
create or replace function public.rewind(p_target uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare w swipes%rowtype;
begin
  if not is_pro(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'pro_only'); end if;
  if p_target is not null then
    select * into w from swipes where swiper_id = auth.uid() and target_id = p_target and kind = 'pass';
  else
    select * into w from swipes where swiper_id = auth.uid() order by created_at desc limit 1;
  end if;
  if not found or w.kind <> 'pass' then return jsonb_build_object('ok', false, 'error', 'nothing_to_undo'); end if;
  delete from swipes where swiper_id = w.swiper_id and target_id = w.target_id;
  return jsonb_build_object('ok', true, 'profile', profile_card(w.target_id));
end $$;
revoke all on function public.rewind(uuid) from public, anon;
grant execute on function public.rewind(uuid) to authenticated;

-- ---------------------------------------------------------------
-- 11. Events and clubs follow travel mode
-- ---------------------------------------------------------------
create or replace function public.my_city() returns text
language sql stable security definer set search_path = public as $$
  select effective_city(p) from profiles p where p.id = auth.uid()
$$;
grant execute on function public.my_city() to authenticated;

create or replace function public.upcoming_events(p_city text default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(event_card(e, auth.uid())
                            order by (s.season in (current_season(), 'all')) desc, e.starts_at), '[]'::jsonb)
  from events e join sports s on s.code = e.sport_code
  where not e.cancelled
    and e.starts_at > now() - make_interval(mins => e.duration_min)
    and e.starts_at < now() + interval '45 days'
    and e.city = coalesce(p_city, my_city())
$$;

create or replace function public.clubs_near(p_city text default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(club_card(c, auth.uid())
                            order by exists (select 1 from club_members m where m.club_id = c.id and m.profile_id = auth.uid()) desc,
                                     (select count(*) from club_members m where m.club_id = c.id) desc), '[]'::jsonb)
  from clubs c
  where not c.archived and c.city = coalesce(p_city, my_city())
$$;

-- ---------------------------------------------------------------
-- 16. Auto-hide counts only people who crossed paths
-- ---------------------------------------------------------------
-- Three fresh accounts could hide anyone. A report still blocks and still goes to the
-- moderators, but only reporters who had real contact count towards hiding someone
-- before review: a match, a like or super like from them, or the same event.
create or replace function public.had_contact(p_reporter uuid, p_reported uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from matches where user_a = least(p_reporter, p_reported) and user_b = greatest(p_reporter, p_reported))
      or exists (select 1 from swipes where swiper_id = p_reported and target_id = p_reporter and kind in ('like','super'))
      or exists (select 1 from event_attendees x join event_attendees y on x.event_id = y.event_id
                  where x.profile_id = p_reporter and y.profile_id = p_reported
                    and x.status = 'going' and y.status = 'going')
$$;
revoke all on function public.had_contact(uuid, uuid) from public, anon, authenticated;

create or replace function public.on_report_insert()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(distinct reporter_id) from reports r
      where r.reported_id = new.reported_id and r.status = 'open'
        and had_contact(r.reporter_id, r.reported_id)) >= cfg('reports_to_autohide') then
    update profiles set held = true, hidden = true where id = new.reported_id;
  end if;
  -- reporting also blocks, so the reporter never sees them again
  insert into blocks (blocker_id, blocked_id) values (new.reporter_id, new.reported_id)
    on conflict do nothing;
  return new;
end $$;

-- ---------------------------------------------------------------
-- 17. Bans outlive account deletion
-- ---------------------------------------------------------------
-- Deleting a banned account used to wipe every trace, so the same Apple ID or email could
-- sign up again. The identity hashes (email, phone) of a banned profile are kept when it is
-- deleted, and a new profile with a matching hash starts out banned.
create table if not exists public.banned_identities (
  kind text not null check (kind in ('email','phone')),
  hash text not null check (hash ~ '^[0-9a-f]{64}$'),
  banned_at timestamptz not null default now(),
  primary key (kind, hash)
);
alter table public.banned_identities enable row level security;
revoke all on public.banned_identities from public, anon, authenticated;

create or replace function public.on_profile_delete_keep_ban() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.banned then
    insert into banned_identities (kind, hash)
    select kind, hash from identity_hashes where profile_id = old.id
    on conflict do nothing;
  end if;
  return old;
end $$;

drop trigger if exists profiles_keep_ban on public.profiles;
create trigger profiles_keep_ban before delete on public.profiles
  for each row execute function public.on_profile_delete_keep_ban();

-- Banning also records the identity at once (in case the row is removed some other way).
create or replace function public.on_profile_banned() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into banned_identities (kind, hash)
  select kind, hash from identity_hashes where profile_id = new.id
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists profiles_banned_identity on public.profiles;
create trigger profiles_banned_identity after update of banned on public.profiles
  for each row when (new.banned and not old.banned) execute function public.on_profile_banned();

create or replace function public.on_profile_identity()
returns trigger
language plpgsql security definer set search_path = public, auth as $$
declare v_email text; v_hash text;
begin
  select lower(btrim(email)) into v_email from auth.users where id = new.id;
  if v_email is not null and v_email <> '' then
    v_hash := qadam_hash(v_email);
    insert into identity_hashes (profile_id, kind, hash) values (new.id, 'email', v_hash)
    on conflict (profile_id, kind) do update set hash = excluded.hash;
    if exists (select 1 from banned_identities where kind = 'email' and hash = v_hash) then
      update public.profiles set banned = true, hidden = true where id = new.id;
    end if;
  end if;
  return new;
end $$;

-- A phone added later is checked the same way.
create or replace function public.on_identity_hash_banned_check() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from banned_identities where kind = new.kind and hash = new.hash) then
    update profiles set banned = true, hidden = true where id = new.profile_id and not banned;
  end if;
  return new;
end $$;

drop trigger if exists identity_hashes_banned_check on public.identity_hashes;
create trigger identity_hashes_banned_check after insert or update of hash on public.identity_hashes
  for each row execute function public.on_identity_hash_banned_check();

-- People already banned today are recorded now.
insert into banned_identities (kind, hash)
select i.kind, i.hash from identity_hashes i join profiles p on p.id = i.profile_id where p.banned
on conflict do nothing;
