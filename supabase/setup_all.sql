-- JÜR: whole database setup in one script (Supabase SQL editor). Generated from migrations/; don't edit by hand.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- ===== migrations/20261020000001_core.sql =====
-- =====================================================================
-- Qadam — core schema
-- Multi-sport dating: profiles, seasonal sports, swipes, matches, chat,
-- events (club runs, ski days...), safety, and purchase crediting.
--
-- Security model:
--   * Clients never write money-related columns (Pro, credits). Those are
--     set only by apply_revenuecat_event(), called by the webhook with the
--     service role.
--   * Other people's profiles are only readable through RPCs that apply
--     block / ban / visibility rules.
--   * Free-tier limits are enforced in SQL, not in the app.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Tunables (change here, not in the app)
-- ---------------------------------------------------------------------
create or replace function public.cfg(key text) returns int
language sql immutable as $$
  select case key
    when 'free_daily_likes'      then 30
    when 'free_daily_supers'     then 1
    when 'pro_daily_supers'      then 5
    when 'boost_minutes'         then 30
    when 'streak_days_for_boost' then 7
    when 'referrals_for_bonus'   then 2
    when 'referral_bonus_days'   then 7
    when 'reports_to_autohide'   then 3
  end
$$;

-- Business day boundary for daily limits and streaks (Kazakhstan, UTC+5).
create or replace function public.local_today() returns date
language sql stable as $$ select (now() at time zone 'Asia/Almaty')::date $$;

create or replace function public.local_day_start() returns timestamptz
language sql stable as $$ select (public.local_today()::timestamp) at time zone 'Asia/Almaty' $$;

-- Winter = Nov..Mar. Drives which sports and events are shown first.
create or replace function public.current_season() returns text
language sql stable as $$
  select case when extract(month from now() at time zone 'Asia/Almaty')::int in (11,12,1,2,3)
              then 'winter' else 'summer' end
$$;

create or replace function public.age_years(d date) returns int
language sql stable as $$ select extract(year from age(current_date, d))::int $$;

-- ---------------------------------------------------------------------
-- Sports (reference data, seeded below)
-- ---------------------------------------------------------------------
create table public.sports (
  code     text primary key,
  season   text not null check (season in ('summer','winter','all')),
  emoji    text not null,
  name_kk  text not null,
  name_ru  text not null,
  name_en  text not null,
  sort     int  not null default 100
);

-- ---------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------
create sequence public.member_no_seq start 1;

create table public.profiles (
  id                   uuid primary key references auth.users(id) on delete cascade,
  member_no            int  not null unique default nextval('public.member_no_seq'),
  name                 text not null check (char_length(btrim(name)) between 1 and 40),
  birthdate            date not null,
  gender               text not null check (gender in ('woman','man')),
  interested_in        text not null check (interested_in in ('women','men','everyone')),
  age_min              int  not null default 18 check (age_min between 18 and 99),
  age_max              int  not null default 60 check (age_max between 18 and 99),
  city                 text not null check (char_length(city) between 2 and 40),
  bio                  text check (char_length(bio) <= 500),
  next_challenge       text check (char_length(next_challenge) <= 80),
  photos               text[] not null default '{}'
                         check (coalesce(array_length(photos, 1), 0) <= 6),
  locale               text not null default 'ru' check (locale in ('kk','ru','en')),
  referral_code        text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  referred_by          uuid references public.profiles(id) on delete set null,
  -- server-managed below this line ------------------------------------
  verification_status  text not null default 'none'
                         check (verification_status in ('none','pending','approved','rejected')),
  verification_selfie  text,
  is_host              boolean not null default false,
  pro_until            timestamptz,          -- from the stores via RevenueCat
  bonus_pro_until      timestamptz,          -- from referrals
  boost_credits        int not null default 0 check (boost_credits >= 0),
  super_like_credits   int not null default 0 check (super_like_credits >= 0),
  boosted_until        timestamptz,
  last_free_boost_at   timestamptz,
  streak_days          int not null default 0,
  streak_last_day      date,
  hidden               boolean not null default false,   -- user paused, or auto-hidden by reports
  banned               boolean not null default false,
  created_at           timestamptz not null default now(),
  last_active_at       timestamptz not null default now(),
  check (age_min <= age_max)
);

create index profiles_discover_idx on public.profiles (city, gender) where not hidden and not banned;

-- 18+ only, enforced in the database.
create or replace function public.enforce_adult() returns trigger
language plpgsql as $$
begin
  if new.birthdate > (current_date - interval '18 years')::date then
    raise exception 'must_be_18' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger profiles_adult before insert or update of birthdate on public.profiles
  for each row execute function public.enforce_adult();

create or replace function public.is_pro(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select greatest(coalesce(pro_until, '-infinity'), coalesce(bonus_pro_until, '-infinity')) > now()
    from profiles where id = uid), false)
$$;

create table public.profile_sports (
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  sport_code  text not null references public.sports(code),
  level       text not null default 'casual'
                check (level in ('beginner','casual','regular','competitive')),
  primary key (profile_id, sport_code)
);

-- Personal bests, finished races, peaks climbed...
create table public.achievements (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  sport_code   text references public.sports(code),
  title        text not null check (char_length(title) between 1 and 60),
  result       text check (char_length(result) <= 20),
  achieved_on  date,
  created_at   timestamptz not null default now()
);
create index on public.achievements (profile_id);

-- ---------------------------------------------------------------------
-- Swipes, matches, chat
-- ---------------------------------------------------------------------
create table public.swipes (
  swiper_id   uuid not null references public.profiles(id) on delete cascade,
  target_id   uuid not null references public.profiles(id) on delete cascade,
  kind        text not null check (kind in ('pass','like','super')),
  created_at  timestamptz not null default now(),
  primary key (swiper_id, target_id),
  check (swiper_id <> target_id)
);
create index swipes_target_idx on public.swipes (target_id, kind);
create index swipes_swiper_day_idx on public.swipes (swiper_id, created_at);

create table public.matches (
  id               uuid primary key default gen_random_uuid(),
  user_a           uuid not null references public.profiles(id) on delete cascade,
  user_b           uuid not null references public.profiles(id) on delete cascade,
  created_at       timestamptz not null default now(),
  last_message_at  timestamptz,
  unmatched_at     timestamptz,
  check (user_a < user_b),
  unique (user_a, user_b)
);
create index on public.matches (user_b);

create table public.messages (
  id          uuid primary key default gen_random_uuid(),
  match_id    uuid not null references public.matches(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  body        text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
create index messages_match_idx on public.messages (match_id, created_at desc);

-- ---------------------------------------------------------------------
-- Safety
-- ---------------------------------------------------------------------
create table public.blocks (
  blocker_id  uuid not null references public.profiles(id) on delete cascade,
  blocked_id  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index on public.blocks (blocked_id);

create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.profiles(id) on delete cascade,
  reported_id  uuid not null references public.profiles(id) on delete cascade,
  reason       text not null check (reason in ('fake','inappropriate','harassment','underage','scam','other')),
  details      text check (char_length(details) <= 1000),
  status       text not null default 'open' check (status in ('open','actioned','dismissed')),
  created_at   timestamptz not null default now(),
  check (reporter_id <> reported_id)
);
create unique index reports_once_idx on public.reports (reporter_id, reported_id) where status = 'open';

create or replace function public.blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocks
                 where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a))
$$;

-- ---------------------------------------------------------------------
-- Events: club runs, ski days, padel nights...
-- ---------------------------------------------------------------------
create table public.events (
  id             uuid primary key default gen_random_uuid(),
  host_id        uuid references public.profiles(id) on delete set null,
  city           text not null,
  sport_code     text not null references public.sports(code),
  title          text not null check (char_length(title) between 3 and 80),
  description    text check (char_length(description) <= 1500),
  meeting_point  text not null check (char_length(meeting_point) between 3 and 160),
  starts_at      timestamptz not null,
  duration_min   int not null default 90 check (duration_min between 15 and 720),
  capacity       int not null default 30 check (capacity between 2 and 500),
  level          text not null default 'all' check (level in ('all','beginner','casual','regular','competitive')),
  price_kzt      int not null default 0 check (price_kzt >= 0),  -- paid at the venue in V1
  cover_url      text,
  cancelled      boolean not null default false,
  created_at     timestamptz not null default now()
);
create index events_city_time_idx on public.events (city, starts_at);

create table public.event_attendees (
  event_id       uuid not null references public.events(id) on delete cascade,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  status         text not null default 'going' check (status in ('going','cancelled')),
  checked_in_at  timestamptz,
  created_at     timestamptz not null default now(),
  primary key (event_id, profile_id)
);
create index on public.event_attendees (profile_id);

-- ---------------------------------------------------------------------
-- Purchases (RevenueCat webhook log; idempotency)
-- ---------------------------------------------------------------------
create table public.purchase_events (
  id           text primary key,
  app_user_id  text,
  type         text not null,
  product_id   text,
  result       text,
  payload      jsonb not null,
  created_at   timestamptz not null default now()
);

-- =====================================================================
-- Row level security + column grants
-- =====================================================================
alter table public.sports            enable row level security;
alter table public.profiles          enable row level security;
alter table public.profile_sports    enable row level security;
alter table public.achievements      enable row level security;
alter table public.swipes            enable row level security;
alter table public.matches           enable row level security;
alter table public.messages          enable row level security;
alter table public.blocks            enable row level security;
alter table public.reports           enable row level security;
alter table public.events            enable row level security;
alter table public.event_attendees   enable row level security;
alter table public.purchase_events   enable row level security;

-- Supabase grants ALL on new tables to anon/authenticated by default.
-- Start from nothing and grant back only what the app needs.
revoke all on public.sports, public.profiles, public.profile_sports, public.achievements,
              public.swipes, public.matches, public.messages, public.blocks, public.reports,
              public.events, public.event_attendees, public.purchase_events
  from anon, authenticated;

grant usage on sequence public.member_no_seq to authenticated;

-- sports: public reference data
grant select on public.sports to anon, authenticated;
create policy sports_read on public.sports for select using (true);

-- profiles: you read and edit only your own row directly.
grant select on public.profiles to authenticated;
grant insert (id, name, birthdate, gender, interested_in, age_min, age_max, city, bio,
              next_challenge, photos, locale)
  on public.profiles to authenticated;
grant update (name, interested_in, age_min, age_max, city, bio, next_challenge, photos,
              locale, hidden)
  on public.profiles to authenticated;
create policy profiles_self_read   on public.profiles for select using (id = auth.uid());
create policy profiles_self_insert on public.profiles for insert with check (id = auth.uid());
create policy profiles_self_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- profile_sports / achievements: own rows
grant select, insert, update, delete on public.profile_sports to authenticated;
create policy ps_self on public.profile_sports for all
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

grant select, delete on public.achievements to authenticated;
grant insert (profile_id, sport_code, title, result, achieved_on) on public.achievements to authenticated;
grant update (sport_code, title, result, achieved_on) on public.achievements to authenticated;
create policy ach_self on public.achievements for all
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- swipes: RPC only (no grants).

-- matches: members can read; writes via RPC
grant select on public.matches to authenticated;
create policy matches_member_read on public.matches for select
  using (auth.uid() in (user_a, user_b));

-- messages: members read; sender inserts into an active, unblocked match
grant select on public.messages to authenticated;
grant insert (match_id, sender_id, body) on public.messages to authenticated;
create policy messages_member_read on public.messages for select
  using (exists (select 1 from public.matches m
                 where m.id = match_id and auth.uid() in (m.user_a, m.user_b)));
create policy messages_member_send on public.messages for insert
  with check (
    sender_id = auth.uid()
    and exists (select 1 from public.matches m
                where m.id = match_id
                  and auth.uid() in (m.user_a, m.user_b)
                  and m.unmatched_at is null
                  and not public.blocked_between(m.user_a, m.user_b))
  );

-- blocks: your own list
grant select, insert, delete on public.blocks to authenticated;
create policy blocks_self on public.blocks for all
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

-- reports: write-only for users
grant insert (reporter_id, reported_id, reason, details) on public.reports to authenticated;
create policy reports_insert on public.reports for insert with check (reporter_id = auth.uid());

-- events: everyone signed in can read; hosts create and edit their own
grant select on public.events to authenticated;
grant insert (host_id, city, sport_code, title, description, meeting_point, starts_at,
              duration_min, capacity, level, price_kzt, cover_url)
  on public.events to authenticated;
grant update (title, description, meeting_point, starts_at, duration_min, capacity, level,
              price_kzt, cover_url, cancelled)
  on public.events to authenticated;
create policy events_read on public.events for select using (true);
create policy events_host_insert on public.events for insert
  with check (host_id = auth.uid()
              and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_host and not p.banned));
create policy events_host_update on public.events for update
  using (host_id = auth.uid()) with check (host_id = auth.uid());

-- event_attendees: read your own rows; joining goes through RPC (capacity check)
grant select on public.event_attendees to authenticated;
create policy ea_self_read on public.event_attendees for select using (profile_id = auth.uid());

-- purchase_events: service role only (no grants, no policies)

-- =====================================================================
-- Triggers
-- =====================================================================

-- Keep matches.last_message_at fresh for the inbox ordering.
create or replace function public.on_message_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update matches set last_message_at = new.created_at where id = new.match_id;
  update profiles set last_active_at = now() where id = new.sender_id;
  return new;
end $$;
create trigger messages_after_insert after insert on public.messages
  for each row execute function public.on_message_insert();

-- Auto-hide a profile once enough different people report it; a moderator reviews.
create or replace function public.on_report_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(distinct reporter_id) from reports
      where reported_id = new.reported_id and status = 'open') >= cfg('reports_to_autohide') then
    update profiles set hidden = true where id = new.reported_id;
  end if;
  -- reporting also blocks, so the reporter never sees them again
  insert into blocks (blocker_id, blocked_id) values (new.reporter_id, new.reported_id)
    on conflict do nothing;
  return new;
end $$;
create trigger reports_after_insert after insert on public.reports
  for each row execute function public.on_report_insert();

-- Referral bonus: every N completed sign-ups with your code = N days of Pro.
create or replace function public.on_profile_referral() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if new.referred_by is not null and (tg_op = 'INSERT' or old.referred_by is distinct from new.referred_by) then
    select count(*) into v_count from profiles where referred_by = new.referred_by;
    if v_count % cfg('referrals_for_bonus') = 0 then
      update profiles
         set bonus_pro_until = greatest(coalesce(bonus_pro_until, now()), now())
                               + make_interval(days => cfg('referral_bonus_days'))
       where id = new.referred_by;
    end if;
  end if;
  return new;
end $$;
create trigger profiles_after_referral after insert or update of referred_by on public.profiles
  for each row execute function public.on_profile_referral();

-- =====================================================================
-- RPCs (called from the app with supabase.rpc)
-- =====================================================================

-- Card payload used everywhere a profile is shown to someone else.
create or replace function public.profile_card(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'member_no', p.member_no,
    'name', p.name,
    'age', age_years(p.birthdate),
    'city', p.city,
    'bio', p.bio,
    'next_challenge', p.next_challenge,
    'photos', to_jsonb(p.photos),
    'verified', p.verification_status = 'approved',
    'is_host', p.is_host,
    'events_attended', (select count(*) from event_attendees a
                        where a.profile_id = p.id and a.checked_in_at is not null),
    'sports', coalesce((select jsonb_agg(jsonb_build_object('code', ps.sport_code, 'level', ps.level)
                                         order by s.sort)
                        from profile_sports ps join sports s on s.code = ps.sport_code
                        where ps.profile_id = p.id), '[]'::jsonb),
    'achievements', coalesce((select jsonb_agg(jsonb_build_object('title', a.title, 'result', a.result,
                                                                  'sport', a.sport_code)
                                               order by a.achieved_on desc nulls last, a.created_at desc)
                              from achievements a where a.profile_id = p.id), '[]'::jsonb)
  )
  from profiles p where p.id = p_id
$$;
revoke execute on function public.profile_card(uuid) from public, anon, authenticated;

-- View one profile (from a match, an event, a chat header).
create or replace function public.get_profile(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_id <> auth.uid() and (
       blocked_between(auth.uid(), p_id)
       or exists (select 1 from profiles where id = p_id and banned)) then
    return null;
  end if;
  return profile_card(p_id);
end $$;

-- The discover feed. City + mutual preferences, unseen, unblocked.
-- Boosted first, then people who super-liked you, then shared in-season sports.
create or replace function public.discover(p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_season text := current_season();
  v_result jsonb;
begin
  select * into me from profiles where id = auth.uid();
  if not found then raise exception 'no_profile'; end if;

  select coalesce(jsonb_agg(profile_card(c.id)
                              || jsonb_build_object('shared_sports', c.shared, 'super_liked_me', c.super_me,
                                                    'boosted', c.boosted)
                            order by c.boosted desc, c.super_me desc, c.shared_season desc, c.shared desc,
                                     c.last_active_at desc), '[]'::jsonb)
    into v_result
  from (
    select p.id, p.last_active_at,
           coalesce(p.boosted_until > now(), false) as boosted,
           exists (select 1 from swipes w where w.swiper_id = p.id and w.target_id = me.id and w.kind = 'super') as super_me,
           (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
             where a.profile_id = p.id and b.profile_id = me.id)::int as shared,
           (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
                                                 join sports s on s.code = a.sport_code
             where a.profile_id = p.id and b.profile_id = me.id and s.season in (v_season, 'all'))::int as shared_season
    from profiles p
    where p.id <> me.id
      and not p.hidden and not p.banned
      and p.city = me.city
      and coalesce(array_length(p.photos, 1), 0) >= 1
      and age_years(p.birthdate) between me.age_min and me.age_max
      and age_years(me.birthdate) between p.age_min and p.age_max
      and (me.interested_in = 'everyone'
           or (me.interested_in = 'women' and p.gender = 'woman')
           or (me.interested_in = 'men'   and p.gender = 'man'))
      and (p.interested_in = 'everyone'
           or (p.interested_in = 'women' and me.gender = 'woman')
           or (p.interested_in = 'men'   and me.gender = 'man'))
      and not exists (select 1 from swipes w where w.swiper_id = me.id and w.target_id = p.id)
      and not blocked_between(me.id, p.id)
    order by 3 desc, 4 desc, 6 desc, 5 desc, p.last_active_at desc
    limit least(greatest(p_limit, 1), 50)
  ) c;

  return v_result;
end $$;

-- Like / pass / super like. Enforces daily limits, spends credits, creates matches.
create or replace function public.swipe(p_target uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me         uuid := auth.uid();
  v_pro      boolean;
  v_count    int;
  v_match_id uuid;
  v_used_credit boolean := false;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if p_kind not in ('pass','like','super') then raise exception 'bad_kind'; end if;
  if p_target = me then raise exception 'self_swipe'; end if;
  if not exists (select 1 from profiles where id = me and not banned) then raise exception 'no_profile'; end if;
  if not exists (select 1 from profiles where id = p_target and not banned and not hidden)
     or blocked_between(me, p_target) then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  -- one swipe at a time per user, so the quota checks can't be raced
  perform pg_advisory_xact_lock(hashtext('swipe:' || me::text));
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

  insert into swipes (swiper_id, target_id, kind) values (me, p_target, p_kind)
  on conflict (swiper_id, target_id) do update set kind = excluded.kind, created_at = now();

  update profiles set last_active_at = now() where id = me;

  if p_kind in ('like','super')
     and exists (select 1 from swipes where swiper_id = p_target and target_id = me and kind in ('like','super')) then
    insert into matches (user_a, user_b) values (least(me, p_target), greatest(me, p_target))
    on conflict (user_a, user_b) do nothing
    returning id into v_match_id;
    if v_match_id is null then
      select id into v_match_id from matches
       where user_a = least(me, p_target) and user_b = greatest(me, p_target) and unmatched_at is null;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'match_id', v_match_id, 'used_credit', v_used_credit);
end $$;

-- How many likes and super likes you have left today (for the UI).
create or replace function public.my_limits() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_pro boolean := is_pro(me);
  v_likes int; v_supers int; p profiles%rowtype;
begin
  select * into p from profiles where id = me;
  select count(*) filter (where kind = 'like'), count(*) filter (where kind = 'super')
    into v_likes, v_supers
    from swipes where swiper_id = me and created_at >= local_day_start();
  return jsonb_build_object(
    'pro', v_pro,
    'pro_until', greatest(p.pro_until, p.bonus_pro_until),
    'likes_left', case when v_pro then null else greatest(cfg('free_daily_likes') - v_likes, 0) end,
    'supers_left', greatest((case when v_pro then cfg('pro_daily_supers') else cfg('free_daily_supers') end) - v_supers, 0)
                   + p.super_like_credits,
    'boost_credits', p.boost_credits,
    'free_boost_available', v_pro and (p.last_free_boost_at is null or p.last_free_boost_at < now() - interval '7 days'),
    'boosted_until', case when p.boosted_until > now() then p.boosted_until end,
    'streak_days', p.streak_days,
    'referral_code', p.referral_code
  );
end $$;

-- People who liked you and you haven't answered. Pro sees them; free sees the count.
create or replace function public.likes_received() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_ids uuid[];
begin
  select coalesce(array_agg(w.swiper_id order by (w.kind = 'super') desc, w.created_at desc), '{}')
    into v_ids
    from swipes w join profiles p on p.id = w.swiper_id
   where w.target_id = me and w.kind in ('like','super')
     and not p.hidden and not p.banned
     and not exists (select 1 from swipes mine where mine.swiper_id = me and mine.target_id = w.swiper_id)
     and not blocked_between(me, w.swiper_id);

  return jsonb_build_object(
    'count', coalesce(array_length(v_ids, 1), 0),
    'profiles', case when is_pro(me)
                     then coalesce((select jsonb_agg(profile_card(x) order by o) from unnest(v_ids) with ordinality as t(x, o)), '[]'::jsonb)
                     else '[]'::jsonb end
  );
end $$;

-- Inbox: matches with the other person's card, last message and unread count.
create or replace function public.my_matches() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_data order by sort_at desc), '[]'::jsonb)
  from (
    select coalesce(m.last_message_at, m.created_at) as sort_at,
           jsonb_build_object(
             'match_id', m.id,
             'created_at', m.created_at,
             'other', profile_card(case when m.user_a = auth.uid() then m.user_b else m.user_a end),
             'last_message', (select jsonb_build_object('body', x.body, 'sender_id', x.sender_id, 'created_at', x.created_at)
                              from messages x where x.match_id = m.id order by x.created_at desc limit 1),
             'unread', (select count(*) from messages x
                        where x.match_id = m.id and x.sender_id <> auth.uid() and x.read_at is null)
           ) as row_data
    from matches m
    where auth.uid() in (m.user_a, m.user_b)
      and m.unmatched_at is null
      and not blocked_between(m.user_a, m.user_b)
  ) s
$$;

create or replace function public.mark_read(p_match uuid) returns void
language sql security definer set search_path = public as $$
  update messages set read_at = now()
   where match_id = p_match and sender_id <> auth.uid() and read_at is null
     and exists (select 1 from matches m where m.id = p_match and auth.uid() in (m.user_a, m.user_b))
$$;

create or replace function public.unmatch(p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_other uuid;
begin
  select case when user_a = auth.uid() then user_b else user_a end into v_other
    from matches where id = p_match and auth.uid() in (user_a, user_b);
  if v_other is null then raise exception 'not_found'; end if;
  update matches set unmatched_at = now() where id = p_match;
  insert into blocks (blocker_id, blocked_id) values (auth.uid(), v_other) on conflict do nothing;
end $$;

-- Boost: 30 minutes at the top of the feed. Pro gets one free per week.
create or replace function public.activate_boost() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  p profiles%rowtype;
  v_until timestamptz;
begin
  select * into p from profiles where id = me for update;
  if not found then raise exception 'no_profile'; end if;
  if p.boosted_until > now() then
    return jsonb_build_object('ok', false, 'error', 'already_boosted', 'boosted_until', p.boosted_until);
  end if;
  v_until := now() + make_interval(mins => cfg('boost_minutes'));
  if is_pro(me) and (p.last_free_boost_at is null or p.last_free_boost_at < now() - interval '7 days') then
    update profiles set boosted_until = v_until, last_free_boost_at = now() where id = me;
  elsif p.boost_credits > 0 then
    update profiles set boosted_until = v_until, boost_credits = boost_credits - 1 where id = me;
  else
    return jsonb_build_object('ok', false, 'error', 'no_boosts');
  end if;
  return jsonb_build_object('ok', true, 'boosted_until', v_until);
end $$;

-- Called on app open. Keeps the daily streak; a 7-day streak earns a boost.
create or replace function public.record_activity() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  p profiles%rowtype;
  v_today date := local_today();
  v_streak int;
  v_reward boolean := false;
begin
  select * into p from profiles where id = me for update;
  if not found then return null; end if;
  if p.streak_last_day = v_today then
    v_streak := p.streak_days;
  elsif p.streak_last_day = v_today - 1 then
    v_streak := p.streak_days + 1;
  else
    v_streak := 1;
  end if;
  if v_streak <> p.streak_days and v_streak > 0 and v_streak % cfg('streak_days_for_boost') = 0 then
    v_reward := true;
  end if;
  update profiles
     set streak_days = v_streak, streak_last_day = v_today, last_active_at = now(),
         boost_credits = boost_credits + case when v_reward then 1 else 0 end
   where id = me;
  return jsonb_build_object('streak_days', v_streak, 'rewarded_boost', v_reward);
end $$;

-- Enter a friend's code within 7 days of signing up.
create or replace function public.redeem_referral(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_ref uuid;
  p profiles%rowtype;
begin
  select * into p from profiles where id = me;
  if not found then raise exception 'no_profile'; end if;
  if p.referred_by is not null then return jsonb_build_object('ok', false, 'error', 'already_used'); end if;
  if p.created_at < now() - interval '7 days' then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  select id into v_ref from profiles where referral_code = upper(btrim(p_code)) and id <> me;
  if v_ref is null then return jsonb_build_object('ok', false, 'error', 'invalid_code'); end if;
  update profiles set referred_by = v_ref where id = me;
  return jsonb_build_object('ok', true);
end $$;

-- Selfie verification: app uploads to the private bucket, a moderator approves.
create or replace function public.request_verification(p_selfie_path text) returns void
language sql security definer set search_path = public as $$
  update profiles set verification_status = 'pending', verification_selfie = p_selfie_path
   where id = auth.uid()
     and verification_status in ('none','rejected')
     and p_selfie_path like auth.uid()::text || '/%'
$$;

-- ---------- Events ----------

create or replace function public.event_card(e events, me uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(e) || jsonb_build_object(
    'going_count', (select count(*) from event_attendees a where a.event_id = e.id and a.status = 'going'),
    'i_am_going', exists (select 1 from event_attendees a where a.event_id = e.id and a.profile_id = me and a.status = 'going'),
    'i_checked_in', exists (select 1 from event_attendees a where a.event_id = e.id and a.profile_id = me and a.checked_in_at is not null),
    'host', case when e.host_id is null then null
                 else (select jsonb_build_object('id', h.id, 'name', h.name, 'photo', h.photos[1])
                         from profiles h where h.id = e.host_id) end
  )
$$;
revoke execute on function public.event_card(events, uuid) from public, anon, authenticated;

-- Upcoming events in my city, current-season sports first.
create or replace function public.upcoming_events(p_city text default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(event_card(e, auth.uid())
                            order by (s.season in (current_season(), 'all')) desc, e.starts_at), '[]'::jsonb)
  from events e join sports s on s.code = e.sport_code
  where not e.cancelled
    and e.starts_at > now() - make_interval(mins => e.duration_min)
    and e.starts_at < now() + interval '45 days'
    and e.city = coalesce(p_city, (select city from profiles where id = auth.uid()))
$$;

create or replace function public.get_event(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select event_card(e, auth.uid()) from events e where e.id = p_id
$$;

create or replace function public.join_event(p_event uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  e events%rowtype;
  v_going int;
begin
  if not exists (select 1 from profiles where id = me and not banned) then raise exception 'no_profile'; end if;
  select * into e from events where id = p_event for update;
  if not found or e.cancelled then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if e.starts_at < now() then return jsonb_build_object('ok', false, 'error', 'started'); end if;
  select count(*) into v_going from event_attendees where event_id = p_event and status = 'going' and profile_id <> me;
  if v_going >= e.capacity then return jsonb_build_object('ok', false, 'error', 'full'); end if;
  insert into event_attendees (event_id, profile_id, status) values (p_event, me, 'going')
  on conflict (event_id, profile_id) do update set status = 'going';
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.leave_event(p_event uuid) returns void
language sql security definer set search_path = public as $$
  update event_attendees set status = 'cancelled'
   where event_id = p_event and profile_id = auth.uid() and checked_in_at is null
$$;

-- Self check-in from 30 min before start until the end. Counts toward the
-- "events attended" badge, which doubles as a real-life verification signal.
create or replace function public.check_in(p_event uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e events%rowtype;
begin
  select * into e from events where id = p_event;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if now() < e.starts_at - interval '30 minutes'
     or now() > e.starts_at + make_interval(mins => e.duration_min) then
    return jsonb_build_object('ok', false, 'error', 'not_now');
  end if;
  update event_attendees set checked_in_at = coalesce(checked_in_at, now())
   where event_id = p_event and profile_id = auth.uid() and status = 'going';
  if not found then return jsonb_build_object('ok', false, 'error', 'not_going'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Who else is going (visible once you've joined, so strangers can't scout lists).
-- After the event this becomes "people you met", with your swipe on each.
create or replace function public.event_people(p_event uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(profile_card(a.profile_id)
                            || jsonb_build_object('my_swipe', (select w.kind from swipes w
                                                               where w.swiper_id = auth.uid() and w.target_id = a.profile_id),
                                                  'checked_in', a.checked_in_at is not null)
                            order by a.checked_in_at nulls last, a.created_at), '[]'::jsonb)
  from event_attendees a join profiles p on p.id = a.profile_id
  where a.event_id = p_event and a.status = 'going'
    and a.profile_id <> auth.uid()
    and not p.banned and not p.hidden
    and not blocked_between(auth.uid(), a.profile_id)
    and exists (select 1 from event_attendees mine
                where mine.event_id = p_event and mine.profile_id = auth.uid() and mine.status = 'going')
$$;

-- Hosts: create an event (RLS also checks is_host).
create or replace function public.my_hosted_events() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(event_card(e, auth.uid()) order by e.starts_at desc), '[]'::jsonb)
  from events e where e.host_id = auth.uid()
$$;

-- ---------- Account ----------

-- App Store rule: users must be able to delete their account in-app.
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from auth.users where id = auth.uid();
end $$;

-- =====================================================================
-- Purchases: RevenueCat webhook → this function (service role only)
-- Product ids must match what you create in App Store Connect / Play Console.
-- =====================================================================
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

  v_is_pro_product := v_product like 'qadam_pro_%'
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
    case v_product
      when 'qadam_boost_1'  then update profiles set boost_credits = boost_credits + 1  where id = v_user;
      when 'qadam_boost_5'  then update profiles set boost_credits = boost_credits + 5  where id = v_user;
      when 'qadam_super_5'  then update profiles set super_like_credits = super_like_credits + 5  where id = v_user;
      when 'qadam_super_25' then update profiles set super_like_credits = super_like_credits + 25 where id = v_user;
      else v_result := 'ignored:unknown_product';
    end case;
    v_result := coalesce(v_result, 'credited:' || v_product);

  else
    v_result := 'noop:' || v_type;
  end if;

  update purchase_events set result = v_result where id = v_id;
  return v_result;
end $$;

-- =====================================================================
-- Function privileges
-- =====================================================================
revoke execute on function public.apply_revenuecat_event(jsonb) from public, anon, authenticated;
grant execute on function public.apply_revenuecat_event(jsonb) to service_role;

-- Nothing is callable without signing in.
revoke execute on function
  public.get_profile(uuid), public.discover(int), public.swipe(uuid, text), public.my_limits(),
  public.likes_received(), public.my_matches(), public.mark_read(uuid), public.unmatch(uuid),
  public.activate_boost(), public.record_activity(), public.redeem_referral(text),
  public.request_verification(text), public.upcoming_events(text), public.get_event(uuid),
  public.join_event(uuid), public.leave_event(uuid), public.check_in(uuid),
  public.event_people(uuid), public.my_hosted_events(), public.delete_account(),
  public.is_pro(uuid), public.blocked_between(uuid, uuid)
from public, anon;

grant execute on function
  public.get_profile(uuid), public.discover(int), public.swipe(uuid, text), public.my_limits(),
  public.likes_received(), public.my_matches(), public.mark_read(uuid), public.unmatch(uuid),
  public.activate_boost(), public.record_activity(), public.redeem_referral(text),
  public.request_verification(text), public.upcoming_events(text), public.get_event(uuid),
  public.join_event(uuid), public.leave_event(uuid), public.check_in(uuid),
  public.event_people(uuid), public.my_hosted_events(), public.delete_account(),
  public.blocked_between(uuid, uuid)   -- used by the messages RLS policy
to authenticated;

-- is_pro() is internal: users see their own status through my_limits().
revoke execute on function public.is_pro(uuid) from authenticated;

-- =====================================================================
-- Seed: sports (reference data — part of the schema, not demo data)
-- =====================================================================
insert into public.sports (code, season, emoji, name_kk, name_ru, name_en, sort) values
  ('running',      'summer', '🏃', 'Жүгіру',            'Бег',                 'Running',            10),
  ('trail',        'summer', '⛰️', 'Трейл',             'Трейл',               'Trail running',      12),
  ('hiking',       'summer', '🥾', 'Тауға шығу',        'Хайкинг',             'Hiking',             14),
  ('cycling',      'summer', '🚴', 'Велоспорт',         'Велоспорт',           'Cycling',            16),
  ('tennis',       'all',    '🎾', 'Теннис',            'Теннис',              'Tennis',             20),
  ('padel',        'all',    '🏓', 'Падел',             'Падел',               'Padel',              22),
  ('football',     'summer', '⚽', 'Футбол',            'Футбол',              'Football',           24),
  ('volleyball',   'summer', '🏐', 'Волейбол',          'Волейбол',            'Volleyball',         26),
  ('swimming',     'all',    '🏊', 'Жүзу',              'Плавание',            'Swimming',           28),
  ('gym',          'all',    '🏋️', 'Жаттығу залы',      'Тренажёрный зал',     'Gym',                30),
  ('yoga',         'all',    '🧘', 'Йога',              'Йога',                'Yoga',               32),
  ('climbing',     'all',    '🧗', 'Скалолазу',         'Скалолазание',        'Climbing',           34),
  ('boxing',       'all',    '🥊', 'Бокс',              'Бокс',                'Boxing',             36),
  ('skiing',       'winter', '⛷️', 'Шаңғы',             'Горные лыжи',         'Skiing',             40),
  ('snowboard',    'winter', '🏂', 'Сноуборд',          'Сноуборд',            'Snowboarding',       42),
  ('xc_skiing',    'winter', '🎿', 'Шаңғы жарысы',      'Беговые лыжи',        'Cross-country ski',  44),
  ('skating',      'winter', '⛸️', 'Коньки',            'Коньки',              'Ice skating',        46),
  ('hockey',       'winter', '🏒', 'Хоккей',            'Хоккей',              'Ice hockey',         48);

-- ===== migrations/20261020000002_storage_realtime.sql =====
-- =====================================================================
-- Qadam — Storage buckets and Realtime
-- Supabase-specific; guarded so the core schema can also be tested on
-- plain Postgres.
-- =====================================================================

do $$
begin
  -- Realtime: chat messages and new matches stream to the app.
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages, public.matches;
  end if;

  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not present; skipping buckets';
    return;
  end if;

  -- Profile photos: public read (random file names), owner-only write.
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('photos', 'photos', true, 8 * 1024 * 1024, array['image/jpeg','image/png','image/webp','image/heic'])
  on conflict (id) do nothing;

  -- Verification selfies: private; only the owner can upload, moderators read in the dashboard.
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('verification', 'verification', false, 8 * 1024 * 1024, array['image/jpeg','image/png'])
  on conflict (id) do nothing;

  -- Event covers: public read, hosts write into their own folder.
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('event-covers', 'event-covers', true, 8 * 1024 * 1024, array['image/jpeg','image/png','image/webp'])
  on conflict (id) do nothing;

  execute $p$
    create policy "photos: owner uploads" on storage.objects for insert to authenticated
      with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  $p$;
  execute $p$
    create policy "photos: owner updates" on storage.objects for update to authenticated
      using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  $p$;
  execute $p$
    create policy "photos: owner deletes" on storage.objects for delete to authenticated
      using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  $p$;
  execute $p$
    create policy "verification: owner uploads" on storage.objects for insert to authenticated
      with check (bucket_id = 'verification' and (storage.foldername(name))[1] = auth.uid()::text)
  $p$;
  execute $p$
    create policy "event covers: hosts upload" on storage.objects for insert to authenticated
      with check (bucket_id = 'event-covers'
                  and (storage.foldername(name))[1] = auth.uid()::text
                  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_host))
  $p$;
end $$;

-- ===== migrations/20261020000003_engagement.sql =====
-- =====================================================================
-- Qadam — engagement: likes with a note, push notifications, event
-- reminders, and "you're both going" for matches.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Like with a note (Hinge-style). On a match the note becomes the
--    first message in the chat, so conversations never start from zero.
-- ---------------------------------------------------------------------
alter table public.swipes
  add column note text check (note is null or char_length(btrim(note)) between 1 and 140);

alter table public.profiles add column last_like_push_at timestamptz;   -- server-managed
alter table public.event_attendees add column reminded_at timestamptz;   -- server-managed

-- ---------------------------------------------------------------------
-- 2. Push notifications via the Expo push service.
--    Tokens are written through register_push_token(); every push is
--    logged in push_outbox (handy for support and for the tests) and sent
--    with pg_net when the extension is available (it is on Supabase).
-- ---------------------------------------------------------------------
create table public.push_tokens (
  token       text primary key check (token ~ '^Expo(nent)?PushToken\[.+\]$'),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  platform    text not null check (platform in ('ios','android')),
  updated_at  timestamptz not null default now()
);
create index on public.push_tokens (profile_id);

create table public.push_outbox (
  id          bigserial primary key,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  kind        text not null check (kind in ('match','message','like','super','event_reminder')),
  title       text not null,
  body        text not null,
  data        jsonb not null default '{}',
  tokens      int not null default 0,
  request_id  bigint,
  created_at  timestamptz not null default now()
);
create index push_outbox_recent_idx on public.push_outbox (profile_id, kind, created_at desc);

alter table public.push_tokens enable row level security;
alter table public.push_outbox enable row level security;
revoke all on public.push_tokens, public.push_outbox from public, anon, authenticated;

-- Notification copy in the recipient's language. Likes never name the person
-- (seeing who liked you is a Pro feature).
create or replace function public.push_text(p_locale text, p_kind text, p_name text, p_extra text default null)
returns table (title text, body text)
language sql immutable set search_path = public as $$
  select
    case p_kind
      when 'match' then case p_locale when 'kk' then 'Жүректер сәйкес келді!' when 'en' then 'Hearts in sync!' else 'Сердца совпали!' end
      when 'message' then p_name
      when 'like' then 'Qadam'
      when 'super' then 'Qadam'
      when 'event_reminder' then coalesce(p_extra, 'Qadam')
    end,
    case p_kind
      when 'match' then case p_locale
        when 'kk' then p_name || ' екеуің бір-біріңді ұнаттыңдар. Бірінші боп жаз.'
        when 'en' then 'You and ' || p_name || ' liked each other. Say hi first.'
        else 'Вы с ' || p_name || ' понравились друг другу. Напишите первым.' end
      when 'message' then case p_locale
        when 'kk' then 'Жаңа хабарлама' when 'en' then 'New message' else 'Новое сообщение' end
      when 'like' then case p_locale
        when 'kk' then 'Біреу сізді ұнатты. Кім екенін көріңіз.'
        when 'en' then 'Someone liked you. See who.'
        else 'Вы кому-то понравились. Посмотрите, кому.' end
      when 'super' then case p_locale
        when 'kk' then 'Біреу сізге супер-лайк басты!'
        when 'en' then 'Someone super liked you!'
        else 'Вам поставили суперлайк!' end
      when 'event_reminder' then case p_locale
        when 'kk' then '2 сағаттан кейін басталады. Кездескенше!'
        when 'en' then 'Starts in 2 hours. See you there!'
        else 'Начало через 2 часа. До встречи!' end
    end
$$;

-- Queue (and, on Supabase, send) one push to every device of a person.
create or replace function public.queue_push(p_profile uuid, p_kind text, p_name text, p_data jsonb,
                                             p_extra text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_locale text;
  v_title text;
  v_body text;
  v_tokens text[];
  v_messages jsonb;
  v_headers jsonb := '{"Content-Type": "application/json", "Accept": "application/json"}';
  v_req bigint;
  v_access text := current_setting('qadam.expo_access_token', true);
begin
  select locale into v_locale from profiles where id = p_profile and not banned;
  if not found then return; end if;
  select t.title, t.body into v_title, v_body from push_text(v_locale, p_kind, p_name, p_extra) t;
  select coalesce(array_agg(token), '{}') into v_tokens from push_tokens where profile_id = p_profile;

  if cardinality(v_tokens) > 0 and exists (select 1 from pg_extension where extname = 'pg_net') then
    select jsonb_agg(jsonb_build_object(
             'to', tok, 'title', v_title, 'body', v_body, 'data', p_data,
             -- plucked-string sound for matches (bundled via the expo-notifications plugin)
             'sound', case when p_kind = 'match' then 'match.wav' else 'default' end,
             'channelId', case p_kind when 'match' then 'matches' when 'message' then 'chats' else 'activity' end,
             'priority', 'high'))
      into v_messages from unnest(v_tokens) tok;
    if coalesce(v_access, '') <> '' then
      v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_access);
    end if;
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      into v_req using 'https://exp.host/--/api/v2/push/send', v_messages, v_headers;
  end if;

  insert into push_outbox (profile_id, kind, title, body, data, tokens, request_id)
  values (p_profile, p_kind, v_title, v_body, coalesce(p_data, '{}'), cardinality(v_tokens), v_req);
end $$;
revoke execute on function public.queue_push(uuid, text, text, jsonb, text) from public, anon, authenticated;
revoke execute on function public.push_text(text, text, text, text) from public, anon, authenticated;

create or replace function public.register_push_token(p_token text, p_platform text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from profiles where id = auth.uid()) then raise exception 'no_profile'; end if;
  -- a device that changes hands moves to the new account
  insert into push_tokens (token, profile_id, platform) values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set profile_id = excluded.profile_id, platform = excluded.platform, updated_at = now();
end $$;

create or replace function public.unregister_push_token(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from push_tokens where token = p_token and profile_id = auth.uid()
$$;

-- New match → both people hear about it.
create or replace function public.on_match_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare a_name text; b_name text;
begin
  select name into a_name from profiles where id = new.user_a;
  select name into b_name from profiles where id = new.user_b;
  perform queue_push(new.user_a, 'match', b_name, jsonb_build_object('url', '/chat/' || new.id));
  perform queue_push(new.user_b, 'match', a_name, jsonb_build_object('url', '/chat/' || new.id));
  return new;
end $$;
create trigger matches_after_insert_push after insert on public.matches
  for each row execute function public.on_match_insert();

-- New message → the other person, at most one push per chat per minute.
-- Notes delivered as opening messages are covered by the match push.
create or replace function public.on_message_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_to uuid; v_name text;
begin
  if current_setting('qadam.mute_message_push', true) = 'on' then return new; end if;
  select case when m.user_a = new.sender_id then m.user_b else m.user_a end into v_to
    from matches m where m.id = new.match_id and m.unmatched_at is null;
  if v_to is null or blocked_between(v_to, new.sender_id) then return new; end if;
  if exists (select 1 from push_outbox o
              where o.profile_id = v_to and o.kind = 'message'
                and o.data->>'match_id' = new.match_id::text
                and o.created_at > now() - interval '1 minute') then
    return new;
  end if;
  select name into v_name from profiles where id = new.sender_id;
  perform queue_push(v_to, 'message', v_name,
                     jsonb_build_object('url', '/chat/' || new.match_id, 'match_id', new.match_id));
  return new;
end $$;
create trigger messages_after_insert_push after insert on public.messages
  for each row execute function public.on_message_push();

revoke execute on function public.on_match_insert(), public.on_message_push() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. swipe() with an optional note, notes → first messages, like pushes
-- ---------------------------------------------------------------------
drop function public.swipe(uuid, text);

create or replace function public.swipe(p_target uuid, p_kind text, p_note text default null) returns jsonb
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
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if p_kind not in ('pass','like','super') then raise exception 'bad_kind'; end if;
  if p_target = me then raise exception 'self_swipe'; end if;
  if p_kind = 'pass' then v_note := null; end if;
  if char_length(v_note) > 140 then return jsonb_build_object('ok', false, 'error', 'note_too_long'); end if;
  if not exists (select 1 from profiles where id = me and not banned) then raise exception 'no_profile'; end if;
  if not exists (select 1 from profiles where id = p_target and not banned and not hidden)
     or blocked_between(me, p_target) then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  -- one swipe at a time per user, so the quota checks can't be raced
  perform pg_advisory_xact_lock(hashtext('swipe:' || me::text));
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

  insert into swipes (swiper_id, target_id, kind, note) values (me, p_target, p_kind, v_note)
  on conflict (swiper_id, target_id) do update set kind = excluded.kind, note = excluded.note, created_at = now();

  update profiles set last_active_at = now() where id = me;

  if p_kind in ('like','super') then
    select * into theirs from swipes where swiper_id = p_target and target_id = me and kind in ('like','super');
    if found then
      insert into matches (user_a, user_b) values (least(me, p_target), greatest(me, p_target))
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
          insert into messages (match_id, sender_id, body, created_at)
          values (v_match_id, p_target, theirs.note, least(theirs.created_at, now() - interval '1 second'));
        end if;
        if v_note is not null then
          insert into messages (match_id, sender_id, body) values (v_match_id, me, v_note);
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

-- Pro sees who liked them, with their notes. Free users see the count only.
create or replace function public.likes_received() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_rows jsonb;
  v_count int;
begin
  with l as (
    select w.swiper_id, w.note, w.kind, w.created_at
      from swipes w join profiles p on p.id = w.swiper_id
     where w.target_id = me and w.kind in ('like','super')
       and not p.hidden and not p.banned
       and not exists (select 1 from swipes mine where mine.swiper_id = me and mine.target_id = w.swiper_id)
       and not blocked_between(me, w.swiper_id)
  )
  select count(*),
         coalesce(jsonb_agg(profile_card(swiper_id)
                              || jsonb_build_object('note', note, 'super_liked_me', kind = 'super')
                            order by (kind = 'super') desc, created_at desc), '[]'::jsonb)
    into v_count, v_rows
    from l;

  return jsonb_build_object(
    'count', v_count,
    'profiles', case when is_pro(me) then v_rows else '[]'::jsonb end
  );
end $$;

-- ---------------------------------------------------------------------
-- 4. "You're both going": upcoming events both people in a match joined
-- ---------------------------------------------------------------------
create or replace function public.shared_events(p_match uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_other uuid;
begin
  select case when user_a = auth.uid() then user_b else user_a end into v_other
    from matches where id = p_match and auth.uid() in (user_a, user_b) and unmatched_at is null;
  if v_other is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(event_card(e, auth.uid()) order by e.starts_at)
      from events e
     where not e.cancelled
       and e.starts_at > now() - make_interval(mins => e.duration_min)
       and exists (select 1 from event_attendees a where a.event_id = e.id and a.profile_id = auth.uid() and a.status = 'going')
       and exists (select 1 from event_attendees a where a.event_id = e.id and a.profile_id = v_other and a.status = 'going')
  ), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 5. Event reminders, two hours before the start (pg_cron, every 10 min)
-- ---------------------------------------------------------------------
create or replace function public.send_event_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    update event_attendees a set reminded_at = now()
      from events e
     where e.id = a.event_id and a.status = 'going' and a.reminded_at is null and not e.cancelled
       and e.starts_at between now() + interval '90 minutes' and now() + interval '2 hours'
    returning a.profile_id, e.id as event_id, e.title
  loop
    perform queue_push(r.profile_id, 'event_reminder', null,
                       jsonb_build_object('url', '/event/' || r.event_id), r.title);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function public.send_event_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('qadam-event-reminders', '*/10 * * * *', 'select public.send_event_reminders()');
  else
    raise notice 'pg_cron not installed; enable it and run: select cron.schedule(''qadam-event-reminders'', ''*/10 * * * *'', ''select public.send_event_reminders()'')';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Privileges for the new and replaced client RPCs
-- ---------------------------------------------------------------------
revoke execute on function
  public.swipe(uuid, text, text), public.likes_received(), public.register_push_token(text, text),
  public.unregister_push_token(text), public.shared_events(uuid)
from public, anon;
grant execute on function
  public.swipe(uuid, text, text), public.likes_received(), public.register_push_token(text, text),
  public.unregister_push_token(text), public.shared_events(uuid)
to authenticated;

-- ===== migrations/20261020000004_dastarkhan.sql =====
-- =====================================================================
-- Qadam — dastarkhan and the card back
-- * events.after_text: what happens after (tea, coffee, a long table)
-- * profile_card gains member_since (month joined) for the felt card back
-- =====================================================================

alter table public.events
  add column after_text text check (after_text is null or char_length(btrim(after_text)) between 2 and 80);

grant insert (after_text) on public.events to authenticated;
grant update (after_text) on public.events to authenticated;

create or replace function public.profile_card(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'member_no', p.member_no,
    'member_since', to_char(p.created_at at time zone 'Asia/Almaty', 'YYYY-MM'),
    'name', p.name,
    'age', age_years(p.birthdate),
    'city', p.city,
    'bio', p.bio,
    'next_challenge', p.next_challenge,
    'photos', to_jsonb(p.photos),
    'verified', p.verification_status = 'approved',
    'is_host', p.is_host,
    'events_attended', (select count(*) from event_attendees a
                        where a.profile_id = p.id and a.checked_in_at is not null),
    'sports', coalesce((select jsonb_agg(jsonb_build_object('code', ps.sport_code, 'level', ps.level)
                                         order by s.sort)
                        from profile_sports ps join sports s on s.code = ps.sport_code
                        where ps.profile_id = p.id), '[]'::jsonb),
    'achievements', coalesce((select jsonb_agg(jsonb_build_object('title', a.title, 'result', a.result,
                                                                  'sport', a.sport_code)
                                               order by a.achieved_on desc nulls last, a.created_at desc)
                              from achievements a where a.profile_id = p.id), '[]'::jsonb)
  )
  from profiles p where p.id = p_id
$$;
revoke execute on function public.profile_card(uuid) from public, anon, authenticated;

-- ===== migrations/20261020000005_clubs_growth.sql =====
-- =====================================================================
-- Qadam — clubs and growth loops (adapted from what works for Ritmo)
-- 1. Clubs: recurring local groups led by organizers (Ritmo's Run Club,
--    for every sport), with membership, a club chat and club events.
--    People apply in the app to start one; a moderator approves.
-- 2. "Open to meet" at events: gold wristband = open to meeting someone,
--    blue = here for the sport. Shown on the attendee list.
-- 3. City launch: a city opens for Discover once enough people joined;
--    until then it shows progress and invites move it faster.
-- =====================================================================

-- ---------------------------------------------------------------------
-- City launch
-- ---------------------------------------------------------------------
create table public.city_launch (
  city              text primary key,
  opens_at_members  int  not null default 0 check (opens_at_members >= 0),  -- 0 = open from day one
  opened_at         timestamptz
);
insert into public.city_launch (city, opens_at_members, opened_at) values
  ('almaty', 0, now()),
  ('astana', 300, null), ('shymkent', 300, null), ('karaganda', 200, null),
  ('aktobe', 200, null), ('atyrau', 150, null), ('oskemen', 150, null);

alter table public.city_launch enable row level security;
revoke all on public.city_launch from public, anon, authenticated;

create or replace function public.city_label(p_city text, p_locale text) returns text
language sql immutable set search_path = public as $$
  select case p_city
    when 'almaty' then case p_locale when 'en' then 'Almaty' else 'Алматы' end
    when 'astana' then case p_locale when 'en' then 'Astana' else 'Астана' end
    when 'shymkent' then case p_locale when 'en' then 'Shymkent' else 'Шымкент' end
    when 'karaganda' then case p_locale when 'en' then 'Karaganda' when 'kk' then 'Қарағанды' else 'Караганда' end
    when 'aktobe' then case p_locale when 'en' then 'Aktobe' when 'kk' then 'Ақтөбе' else 'Актобе' end
    when 'atyrau' then case p_locale when 'en' then 'Atyrau' else 'Атырау' end
    when 'oskemen' then case p_locale when 'en' then 'Oskemen' when 'kk' then 'Өскемен' else 'Усть-Каменогорск' end
    else p_city end
$$;

-- Is my city open? How far along is it, and how many people have I brought?
create or replace function public.city_status(p_city text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_city text := coalesce(p_city, (select city from profiles where id = auth.uid()));
  c city_launch%rowtype;
  v_members int;
begin
  select count(*) into v_members from profiles where city = v_city and not banned;
  select * into c from city_launch where city = v_city;
  if not found then
    -- cities we haven't planned yet behave like waitlisted ones with a default bar
    c.city := v_city; c.opens_at_members := 300; c.opened_at := null;
  end if;
  return jsonb_build_object(
    'city', v_city,
    'open', c.opened_at is not null or c.opens_at_members = 0 or v_members >= c.opens_at_members,
    'members', v_members,
    'needed', c.opens_at_members,
    'my_invites', (select count(*) from profiles where referred_by = auth.uid())
  );
end $$;

-- When a new member tips a city over its threshold: open it and tell everyone there.
create or replace function public.on_profile_city_launch() returns trigger
language plpgsql security definer set search_path = public as $$
declare c city_launch%rowtype; v_members int; r record;
begin
  select * into c from city_launch where city = new.city for update;
  if not found or c.opened_at is not null then return new; end if;
  select count(*) into v_members from profiles where city = new.city and not banned;
  if v_members >= c.opens_at_members then
    update city_launch set opened_at = now() where city = new.city;
    for r in select id from profiles where city = new.city and not banned loop
      perform queue_push(r.id, 'city_open', new.city, jsonb_build_object('url', '/discover'));
    end loop;
  end if;
  return new;
end $$;
create trigger profiles_after_insert_city after insert or update of city on public.profiles
  for each row execute function public.on_profile_city_launch();

-- ---------------------------------------------------------------------
-- Push wording: add city_open and club_event
-- ---------------------------------------------------------------------
alter table public.push_outbox drop constraint push_outbox_kind_check;
alter table public.push_outbox add constraint push_outbox_kind_check
  check (kind in ('match','message','like','super','event_reminder','city_open','club_event'));

create or replace function public.push_text(p_locale text, p_kind text, p_name text, p_extra text default null)
returns table (title text, body text)
language sql immutable set search_path = public as $$
  select
    case p_kind
      when 'match' then case p_locale when 'kk' then 'Жүректер сәйкес келді!' when 'en' then 'Hearts in sync!' else 'Сердца совпали!' end
      when 'message' then p_name
      when 'like' then 'Qadam'
      when 'super' then 'Qadam'
      when 'event_reminder' then coalesce(p_extra, 'Qadam')
      when 'city_open' then 'Qadam'
      when 'club_event' then coalesce(p_extra, 'Qadam')
    end,
    case p_kind
      when 'match' then case p_locale
        when 'kk' then p_name || ' екеуің бір-біріңді ұнаттыңдар. Бірінші боп жаз.'
        when 'en' then 'You and ' || p_name || ' liked each other. Say hi first.'
        else 'Вы с ' || p_name || ' понравились друг другу. Напишите первым.' end
      when 'message' then case p_locale
        when 'kk' then 'Жаңа хабарлама' when 'en' then 'New message' else 'Новое сообщение' end
      when 'like' then case p_locale
        when 'kk' then 'Біреу сізді ұнатты. Кім екенін көріңіз.'
        when 'en' then 'Someone liked you. See who.'
        else 'Вы кому-то понравились. Посмотрите, кому.' end
      when 'super' then case p_locale
        when 'kk' then 'Біреу сізге супер-лайк басты!'
        when 'en' then 'Someone super liked you!'
        else 'Вам поставили суперлайк!' end
      when 'event_reminder' then case p_locale
        when 'kk' then '2 сағаттан кейін басталады. Кездескенше!'
        when 'en' then 'Starts in 2 hours. See you there!'
        else 'Начало через 2 часа. До встречи!' end
      when 'city_open' then case p_locale
        when 'kk' then city_label(p_name, p_locale) || ' ашылды! Анкеталар сізді күтіп тұр.'
        when 'en' then city_label(p_name, p_locale) || ' is open! Start discovering.'
        else city_label(p_name, p_locale) || ' открыт! Анкеты уже ждут.' end
      when 'club_event' then case p_locale
        when 'kk' then p_name || ' клубында жаңа іс-шара. Орын алыңыз.'
        when 'en' then 'New event in ' || p_name || '. Save your spot.'
        else 'Новое событие в клубе ' || p_name || '. Займите место.' end
    end
$$;
revoke execute on function public.push_text(text, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Clubs
-- ---------------------------------------------------------------------
create table public.clubs (
  id            uuid primary key default gen_random_uuid(),
  city          text not null,
  sport_code    text not null references public.sports(code),
  name          text not null check (char_length(btrim(name)) between 3 and 60),
  description   text check (char_length(description) <= 600),
  schedule      text check (char_length(schedule) <= 120),          -- "Saturdays 08:00 · Medeu"
  organizer_id  uuid references public.profiles(id) on delete set null,
  cover_url     text,
  archived      boolean not null default false,
  created_at    timestamptz not null default now()
);
create index clubs_city_idx on public.clubs (city) where not archived;

create table public.club_members (
  club_id     uuid not null references public.clubs(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  role        text not null default 'member' check (role in ('member','organizer')),
  joined_at   timestamptz not null default now(),
  primary key (club_id, profile_id)
);
create index on public.club_members (profile_id);

create table public.club_messages (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  body        text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at  timestamptz not null default now()
);
create index club_messages_idx on public.club_messages (club_id, created_at desc);

create table public.club_applications (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  city        text not null,
  sport_code  text not null references public.sports(code),
  club_name   text not null check (char_length(btrim(club_name)) between 3 and 60),
  about       text not null check (char_length(btrim(about)) between 10 and 600),
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  club_id     uuid references public.clubs(id) on delete set null,
  created_at  timestamptz not null default now()
);
create unique index club_applications_one_pending on public.club_applications (profile_id) where status = 'pending';

alter table public.events add column club_id uuid references public.clubs(id) on delete set null;
grant insert (club_id) on public.events to authenticated;
grant update (club_id) on public.events to authenticated;

alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_messages enable row level security;
alter table public.club_applications enable row level security;
revoke all on public.clubs, public.club_members, public.club_messages, public.club_applications
  from public, anon, authenticated;

-- clubs: readable; organizers edit their description, schedule and cover
grant select on public.clubs to authenticated;
grant update (description, schedule, cover_url) on public.clubs to authenticated;
create policy clubs_read on public.clubs for select using (not archived);
create policy clubs_organizer_update on public.clubs for update
  using (organizer_id = auth.uid()) with check (organizer_id = auth.uid());

create or replace function public.is_club_member(p_club uuid, p_profile uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from club_members where club_id = p_club and profile_id = p_profile)
$$;

-- club_messages: members read and post (also what realtime checks)
grant select on public.club_messages to authenticated;
grant insert (club_id, sender_id, body) on public.club_messages to authenticated;
create policy club_messages_member_read on public.club_messages for select
  using (public.is_club_member(club_id, auth.uid()));
create policy club_messages_member_send on public.club_messages for insert
  with check (sender_id = auth.uid()
              and public.is_club_member(club_id, auth.uid())
              and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.banned));

-- applications: your own
grant select on public.club_applications to authenticated;
create policy club_applications_own on public.club_applications for select using (profile_id = auth.uid());

-- A club event must be created by that club's organizer.
create or replace function public.check_event_club() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.club_id is not null and not exists (
       select 1 from club_members where club_id = new.club_id and profile_id = new.host_id and role = 'organizer') then
    raise exception 'not_club_organizer' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger events_check_club before insert or update of club_id, host_id on public.events
  for each row execute function public.check_event_club();

-- New club event → tell the club's members (except the organizer).
create or replace function public.on_club_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; v_name text;
begin
  if new.club_id is null then return new; end if;
  select name into v_name from clubs where id = new.club_id;
  for r in select profile_id from club_members where club_id = new.club_id and profile_id is distinct from new.host_id loop
    perform queue_push(r.profile_id, 'club_event', v_name, jsonb_build_object('url', '/event/' || new.id), new.title);
  end loop;
  return new;
end $$;
create trigger events_after_insert_club after insert on public.events
  for each row execute function public.on_club_event();

create or replace function public.club_card(c clubs, me uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(c) || jsonb_build_object(
    'member_count', (select count(*) from club_members m where m.club_id = c.id),
    'i_am_member', exists (select 1 from club_members m where m.club_id = c.id and m.profile_id = me),
    'i_am_organizer', c.organizer_id = me,
    'organizer', (select jsonb_build_object('id', p.id, 'name', p.name, 'photo', p.photos[1], 'member_no', p.member_no)
                  from profiles p where p.id = c.organizer_id),
    'next_event', (select jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at)
                   from events e where e.club_id = c.id and not e.cancelled and e.starts_at > now()
                   order by e.starts_at limit 1),
    'faces', coalesce((select jsonb_agg(x.photo) from (
                select p.photos[1] as photo from club_members m join profiles p on p.id = m.profile_id
                 where m.club_id = c.id and not p.banned and not p.hidden and p.photos[1] is not null
                 order by m.joined_at desc limit 5) x), '[]'::jsonb)
  )
$$;

-- Clubs in my city: mine first, then by size.
create or replace function public.clubs_near(p_city text default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(club_card(c, auth.uid())
                            order by exists (select 1 from club_members m where m.club_id = c.id and m.profile_id = auth.uid()) desc,
                                     (select count(*) from club_members m where m.club_id = c.id) desc), '[]'::jsonb)
  from clubs c
  where not c.archived and c.city = coalesce(p_city, (select city from profiles where id = auth.uid()))
$$;

create or replace function public.get_club(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select club_card(c, auth.uid()) || jsonb_build_object(
    'events', coalesce((select jsonb_agg(event_card(e, auth.uid()) order by e.starts_at)
                        from events e where e.club_id = c.id and not e.cancelled
                          and e.starts_at > now() - make_interval(mins => e.duration_min)), '[]'::jsonb))
  from clubs c where c.id = p_id and not c.archived
$$;

create or replace function public.join_club(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and not banned) then raise exception 'no_profile'; end if;
  if not exists (select 1 from clubs where id = p_id and not archived) then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  insert into club_members (club_id, profile_id) values (p_id, auth.uid()) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.leave_club(p_id uuid) returns void
language sql security definer set search_path = public as $$
  delete from club_members where club_id = p_id and profile_id = auth.uid() and role = 'member'
$$;

-- Club chat history, newest first, without people I blocked (or who blocked me).
create or replace function public.club_feed(p_club uuid, p_before timestamptz default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'club_id', x.club_id, 'sender_id', x.sender_id, 'body', x.body, 'created_at', x.created_at,
           'sender', jsonb_build_object('name', p.name, 'photo', p.photos[1], 'member_no', p.member_no))
         order by x.created_at desc), '[]'::jsonb)
  from (select * from club_messages m
         where m.club_id = p_club and (p_before is null or m.created_at < p_before)
         order by m.created_at desc limit 50) x
  join profiles p on p.id = x.sender_id
  where exists (select 1 from club_members cm where cm.club_id = p_club and cm.profile_id = auth.uid())
    and not p.banned
    and not blocked_between(auth.uid(), x.sender_id)
$$;

create or replace function public.apply_club(p_city text, p_sport text, p_name text, p_about text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and not banned) then raise exception 'no_profile'; end if;
  if exists (select 1 from club_applications where profile_id = auth.uid() and status = 'pending') then
    return jsonb_build_object('ok', false, 'error', 'pending_exists');
  end if;
  insert into club_applications (profile_id, city, sport_code, club_name, about)
  values (auth.uid(), p_city, p_sport, btrim(p_name), btrim(p_about));
  return jsonb_build_object('ok', true);
end $$;

-- Moderators (SQL editor / service role): approve → the club exists, the applicant organizes it and can host events.
create or replace function public.approve_club_application(p_id uuid, p_schedule text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare a club_applications%rowtype; v_club uuid;
begin
  select * into a from club_applications where id = p_id and status = 'pending' for update;
  if not found then raise exception 'not_pending'; end if;
  insert into clubs (city, sport_code, name, description, schedule, organizer_id)
  values (a.city, a.sport_code, a.club_name, a.about, p_schedule, a.profile_id) returning id into v_club;
  insert into club_members (club_id, profile_id, role) values (v_club, a.profile_id, 'organizer');
  update profiles set is_host = true where id = a.profile_id;
  update club_applications set status = 'approved', club_id = v_club where id = p_id;
  return v_club;
end $$;

-- ---------------------------------------------------------------------
-- "Open to meet" at events
-- ---------------------------------------------------------------------
alter table public.event_attendees add column open_to_meet boolean not null default true;

drop function public.join_event(uuid);
create or replace function public.join_event(p_event uuid, p_open boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  e events%rowtype;
  v_going int;
begin
  if not exists (select 1 from profiles where id = me and not banned) then raise exception 'no_profile'; end if;
  select * into e from events where id = p_event for update;
  if not found or e.cancelled then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if e.starts_at < now() then return jsonb_build_object('ok', false, 'error', 'started'); end if;
  select count(*) into v_going from event_attendees where event_id = p_event and status = 'going' and profile_id <> me;
  if v_going >= e.capacity then return jsonb_build_object('ok', false, 'error', 'full'); end if;
  insert into event_attendees (event_id, profile_id, status, open_to_meet) values (p_event, me, 'going', p_open)
  on conflict (event_id, profile_id) do update set status = 'going', open_to_meet = excluded.open_to_meet;
  -- joining a club's event makes you a member of the club
  if e.club_id is not null then
    insert into club_members (club_id, profile_id) values (e.club_id, me) on conflict do nothing;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.set_open_to_meet(p_event uuid, p_open boolean) returns void
language sql security definer set search_path = public as $$
  update event_attendees set open_to_meet = p_open where event_id = p_event and profile_id = auth.uid()
$$;

create or replace function public.event_card(e events, me uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(e) || jsonb_build_object(
    'going_count', (select count(*) from event_attendees a where a.event_id = e.id and a.status = 'going'),
    'open_count', (select count(*) from event_attendees a where a.event_id = e.id and a.status = 'going' and a.open_to_meet),
    'i_am_going', exists (select 1 from event_attendees a where a.event_id = e.id and a.profile_id = me and a.status = 'going'),
    'i_checked_in', exists (select 1 from event_attendees a where a.event_id = e.id and a.profile_id = me and a.checked_in_at is not null),
    'i_am_open', (select a.open_to_meet from event_attendees a where a.event_id = e.id and a.profile_id = me and a.status = 'going'),
    'host', case when e.host_id is null then null
                 else (select jsonb_build_object('id', h.id, 'name', h.name, 'photo', h.photos[1])
                         from profiles h where h.id = e.host_id) end,
    'club', case when e.club_id is null then null
                 else (select jsonb_build_object('id', c.id, 'name', c.name) from clubs c where c.id = e.club_id) end
  )
$$;

create or replace function public.event_people(p_event uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(profile_card(a.profile_id)
                            || jsonb_build_object('my_swipe', (select w.kind from swipes w
                                                               where w.swiper_id = auth.uid() and w.target_id = a.profile_id),
                                                  'checked_in', a.checked_in_at is not null,
                                                  'open_to_meet', a.open_to_meet)
                            order by a.open_to_meet desc, a.checked_in_at nulls last, a.created_at), '[]'::jsonb)
  from event_attendees a join profiles p on p.id = a.profile_id
  where a.event_id = p_event and a.status = 'going'
    and a.profile_id <> auth.uid()
    and not p.banned and not p.hidden
    and not blocked_between(auth.uid(), a.profile_id)
    and exists (select 1 from event_attendees mine
                where mine.event_id = p_event and mine.profile_id = auth.uid() and mine.status = 'going')
$$;

-- realtime for club chat
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.club_messages;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------
revoke execute on function
  public.on_profile_city_launch(), public.check_event_club(), public.on_club_event(),
  public.club_card(clubs, uuid), public.approve_club_application(uuid, text), public.city_label(text, text)
from public, anon, authenticated;

revoke execute on function public.is_club_member(uuid, uuid) from public, anon;
grant execute on function public.is_club_member(uuid, uuid) to authenticated;   -- used by the chat policies

revoke execute on function
  public.city_status(text), public.clubs_near(text), public.get_club(uuid), public.join_club(uuid),
  public.leave_club(uuid), public.club_feed(uuid, timestamptz), public.apply_club(text, text, text, text),
  public.join_event(uuid, boolean), public.set_open_to_meet(uuid, boolean)
from public, anon;
grant execute on function
  public.city_status(text), public.clubs_near(text), public.get_club(uuid), public.join_club(uuid),
  public.leave_club(uuid), public.club_feed(uuid, timestamptz), public.apply_club(text, text, text, text),
  public.join_event(uuid, boolean), public.set_open_to_meet(uuid, boolean)
to authenticated;

-- ---------------------------------------------------------------------
-- Pricing: any pack size, and the one-time intro offer
-- (qadam_pro_monthly_intro is a Pro product, so it is recognised by prefix.)
-- ---------------------------------------------------------------------
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

  v_is_pro_product := v_product like 'qadam_pro_%'
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
revoke execute on function public.apply_revenuecat_event(jsonb) from public, anon, authenticated;
grant execute on function public.apply_revenuecat_event(jsonb) to service_role;

-- ===== migrations/20261020000006_social.sql =====
-- =====================================================================
-- Qadam — the best of Tinder, Bumble and Hinge, fitted to Qadam
-- 1. Profile prompts (Hinge) — likes with a note can point at one answer
-- 2. Suggest a date (Bumble "Suggest a Date", Hinge "Direct to Date")
-- 3. Undo the last pass (Tinder Rewind) — Pro
-- 4. Daily picks (Hinge Most Compatible) — five a day, evening push
-- 5. Travel mode (Tinder Passport) — Pro
-- 6. Hide from my contacts (Tinder Block Contacts) — hashes only
-- 7. Chat: replies, photos, voice notes, reactions
-- 8. Training-partner mode (Bumble BFF)
-- 9. Double dates (Tinder / Bumble Double Date)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Profile columns
-- ---------------------------------------------------------------------
alter table public.profiles
  add column mode text not null default 'dating' check (mode in ('dating','buddy','both')),
  add column buddy_with text not null default 'everyone' check (buddy_with in ('women','men','everyone')),
  add column travel_city text,                -- server-managed (set_travel)
  add column travel_until timestamptz;        -- server-managed
grant insert (mode, buddy_with) on public.profiles to authenticated;
grant update (mode, buddy_with) on public.profiles to authenticated;

alter table public.matches add column kind text not null default 'dating' check (kind in ('dating','buddy'));
alter table public.swipes add column note_prompt text;

-- Where someone is looking right now (travel mode moves them for a few days).
create or replace function public.effective_city(p profiles) returns text
language sql stable set search_path = public as $$
  select case when p.travel_until > now() and p.travel_city is not null then p.travel_city else p.city end
$$;

-- One-way preference check: does a want to see b (gender and age)?
create or replace function public.wants(a profiles, b profiles, p_with text) returns boolean
language sql stable set search_path = public as $$
  select age_years(b.birthdate) between a.age_min and a.age_max
     and (p_with = 'everyone' or (p_with = 'women' and b.gender = 'woman') or (p_with = 'men' and b.gender = 'man'))
$$;

create or replace function public.dating_ok(a profiles, b profiles) returns boolean
language sql stable set search_path = public as $$
  select a.mode in ('dating','both') and b.mode in ('dating','both')
     and wants(a, b, a.interested_in) and wants(b, a, b.interested_in)
$$;

create or replace function public.buddy_ok(a profiles, b profiles) returns boolean
language sql stable set search_path = public as $$
  select a.mode in ('buddy','both') and b.mode in ('buddy','both')
     and wants(a, b, a.buddy_with) and wants(b, a, b.buddy_with)
$$;

-- ---------------------------------------------------------------------
-- 6. Hide from my contacts. The app hashes phone numbers and emails from the
--    address book ("qadam:" + normalised value, SHA-256) and uploads only hashes.
--    Each profile's own email hash is added automatically; a phone hash only if
--    the person adds their number for this feature. Hiding works both ways.
-- ---------------------------------------------------------------------
create table public.identity_hashes (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('email','phone')),
  hash       text not null check (hash ~ '^[0-9a-f]{64}$'),
  primary key (profile_id, kind)
);
create index on public.identity_hashes (hash);

create table public.contact_hides (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  hash     text not null check (hash ~ '^[0-9a-f]{64}$'),
  primary key (owner_id, hash)
);
create index on public.contact_hides (hash);

alter table public.identity_hashes enable row level security;
alter table public.contact_hides enable row level security;
revoke all on public.identity_hashes, public.contact_hides from public, anon, authenticated;

create or replace function public.qadam_hash(p_value text) returns text
language sql immutable as $$
  select encode(sha256(convert_to('qadam:' || p_value, 'UTF8')), 'hex')
$$;

create or replace function public.on_profile_identity() returns trigger
language plpgsql security definer set search_path = public, auth as $$
declare v_email text;
begin
  select lower(btrim(email)) into v_email from auth.users where id = new.id;
  if v_email is not null and v_email <> '' then
    insert into identity_hashes (profile_id, kind, hash) values (new.id, 'email', qadam_hash(v_email))
    on conflict (profile_id, kind) do update set hash = excluded.hash;
  end if;
  return new;
end $$;
create trigger profiles_after_insert_identity after insert on public.profiles
  for each row execute function public.on_profile_identity();

create or replace function public.hidden_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from contact_hides h join identity_hashes i on i.hash = h.hash
                  where (h.owner_id = a and i.profile_id = b) or (h.owner_id = b and i.profile_id = a))
$$;

-- Replace my uploaded contact hashes (an empty array turns the feature off).
create or replace function public.set_contact_hides(p_hashes text[]) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if coalesce(cardinality(p_hashes), 0) > 5000 then raise exception 'too_many'; end if;
  delete from contact_hides where owner_id = auth.uid();
  insert into contact_hides (owner_id, hash)
  select distinct auth.uid(), lower(h) from unnest(coalesce(p_hashes, '{}')) h where lower(h) ~ '^[0-9a-f]{64}$'
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- So people who have my number can hide me too (optional).
create or replace function public.set_phone_hash(p_hash text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_hash is null then
    delete from identity_hashes where profile_id = auth.uid() and kind = 'phone';
    return;
  end if;
  insert into identity_hashes (profile_id, kind, hash) values (auth.uid(), 'phone', lower(p_hash))
  on conflict (profile_id, kind) do update set hash = excluded.hash;
end $$;

create or replace function public.contact_hides_count() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from contact_hides where owner_id = auth.uid()
$$;

-- ---------------------------------------------------------------------
-- 1. Profile prompts
-- ---------------------------------------------------------------------
create table public.profile_prompts (
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  position    smallint not null check (position between 0 and 2),
  prompt_key  text not null check (prompt_key in (
                'perfect_sunday','slow_down_for','after_finish','proudest_finish','teach_me',
                'green_flag','season_love','first_date_idea','training_secret')),
  answer      text not null check (char_length(btrim(answer)) between 2 and 150),
  primary key (profile_id, position)
);
alter table public.profile_prompts enable row level security;
revoke all on public.profile_prompts from public, anon, authenticated;
grant select, insert, update, delete on public.profile_prompts to authenticated;
create policy prompts_own on public.profile_prompts for all
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- The prompt a note was about, carried into the opening message ("Re: My perfect Sunday…").
create or replace function public.prompt_context(p_owner uuid, p_key text) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when p_key is null then null else
    (select jsonb_build_object('prompt', jsonb_build_object('key', q.prompt_key, 'answer', q.answer))
       from profile_prompts q where q.profile_id = p_owner and q.prompt_key = p_key limit 1) end
$$;

create or replace function public.profile_card(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'member_no', p.member_no,
    'member_since', to_char(p.created_at at time zone 'Asia/Almaty', 'YYYY-MM'),
    'mode', p.mode,
    'travel_city', case when p.travel_until > now() then p.travel_city end,
    'prompts', coalesce((select jsonb_agg(jsonb_build_object('key', q.prompt_key, 'answer', q.answer) order by q.position)
                         from profile_prompts q where q.profile_id = p.id), '[]'::jsonb),
    'name', p.name,
    'age', age_years(p.birthdate),
    'city', p.city,
    'bio', p.bio,
    'next_challenge', p.next_challenge,
    'photos', to_jsonb(p.photos),
    'verified', p.verification_status = 'approved',
    'is_host', p.is_host,
    'events_attended', (select count(*) from event_attendees a
                        where a.profile_id = p.id and a.checked_in_at is not null),
    'sports', coalesce((select jsonb_agg(jsonb_build_object('code', ps.sport_code, 'level', ps.level)
                                         order by s.sort)
                        from profile_sports ps join sports s on s.code = ps.sport_code
                        where ps.profile_id = p.id), '[]'::jsonb),
    'achievements', coalesce((select jsonb_agg(jsonb_build_object('title', a.title, 'result', a.result,
                                                                  'sport', a.sport_code)
                                               order by a.achieved_on desc nulls last, a.created_at desc)
                              from achievements a where a.profile_id = p.id), '[]'::jsonb)
  )
  from profiles p where p.id = p_id
$$;
revoke execute on function public.profile_card(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 7. Chat: kinds, replies, media, reactions
-- ---------------------------------------------------------------------
alter table public.messages
  add column kind       text not null default 'text' check (kind in ('text','photo','voice','date')),
  add column reply_to   uuid references public.messages(id) on delete set null,
  add column media_path text,
  add column media_ms   int check (media_ms is null or media_ms between 0 and 120000),
  add column payload    jsonb,
  add column updated_at timestamptz;
alter table public.messages drop constraint messages_body_check;
alter table public.messages add constraint messages_body_check check (
  char_length(body) <= 2000
  and (kind <> 'text' or char_length(btrim(body)) >= 1)
  and (kind not in ('photo','voice') or media_path is not null)
  and (kind <> 'date' or payload is not null));
grant insert (kind, reply_to, media_path, media_ms) on public.messages to authenticated;
-- payload is not granted: date cards and prompt context are written only by the server.

create or replace function public.is_match_member(p_match uuid, p_profile uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from matches where id = p_match and p_profile in (user_a, user_b))
$$;

-- Media must live in the match's folder; replies must quote this chat.
create or replace function public.check_message() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.media_path is not null and new.media_path not like new.match_id::text || '/%' then
    raise exception 'bad_media_path' using errcode = '42501';
  end if;
  if new.reply_to is not null and not exists (select 1 from messages where id = new.reply_to and match_id = new.match_id) then
    raise exception 'bad_reply' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger messages_check before insert on public.messages
  for each row execute function public.check_message();

create table public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  reaction   text not null check (reaction in ('heart','fire','clap','laugh','thumbsup')),
  created_at timestamptz not null default now(),
  primary key (message_id, profile_id)
);
alter table public.message_reactions enable row level security;
revoke all on public.message_reactions from public, anon, authenticated;

-- One reaction per person per message; the same one again removes it.
-- Touches the message so realtime subscribers refresh.
create or replace function public.react(p_message uuid, p_reaction text) returns void
language plpgsql security definer set search_path = public as $$
declare v_match uuid;
begin
  select match_id into v_match from messages where id = p_message;
  if v_match is null or not is_match_member(v_match, auth.uid()) then raise exception 'not_found'; end if;
  if exists (select 1 from message_reactions where message_id = p_message and profile_id = auth.uid() and reaction = p_reaction) then
    delete from message_reactions where message_id = p_message and profile_id = auth.uid();
  else
    insert into message_reactions (message_id, profile_id, reaction) values (p_message, auth.uid(), p_reaction)
    on conflict (message_id, profile_id) do update set reaction = excluded.reaction, created_at = now();
  end if;
  update messages set updated_at = now() where id = p_message;
end $$;

-- A page of chat, newest first, with reactions and reply previews.
create or replace function public.chat_messages(p_match uuid, p_before timestamptz default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object(
           'reactions', coalesce((select jsonb_agg(jsonb_build_object('profile_id', r.profile_id, 'reaction', r.reaction))
                                  from message_reactions r where r.message_id = m.id), '[]'::jsonb),
           'reply', (select jsonb_build_object('id', q.id, 'body', q.body, 'kind', q.kind, 'sender_id', q.sender_id)
                     from messages q where q.id = m.reply_to))
         order by m.created_at desc), '[]'::jsonb)
  from (select * from messages
         where match_id = p_match and (p_before is null or created_at < p_before)
           and is_match_member(p_match, auth.uid())
         order by created_at desc limit 50) m
$$;

-- ---------------------------------------------------------------------
-- 2. Suggest a date: a card in the chat — sport, time, place (or an event)
-- ---------------------------------------------------------------------
create or replace function public.propose_date(p_match uuid, p_sport text, p_when timestamptz, p_place text,
                                               p_event uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; e events%rowtype;
begin
  if not exists (select 1 from matches m where m.id = p_match and auth.uid() in (m.user_a, m.user_b)
                   and m.unmatched_at is null and not blocked_between(m.user_a, m.user_b)) then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if p_event is not null then
    select * into e from events where id = p_event and not cancelled;
    if not found then return jsonb_build_object('ok', false, 'error', 'bad_event'); end if;
    p_when := e.starts_at; p_place := e.meeting_point; p_sport := e.sport_code;
  end if;
  if p_when is null or p_when < now() or p_when > now() + interval '60 days' then
    return jsonb_build_object('ok', false, 'error', 'bad_time');
  end if;
  if char_length(btrim(coalesce(p_place, ''))) not between 2 and 120 then
    return jsonb_build_object('ok', false, 'error', 'bad_place');
  end if;
  insert into messages (match_id, sender_id, body, kind, payload)
  values (p_match, auth.uid(), '', 'date', jsonb_build_object(
    'sport', p_sport, 'when', p_when, 'place', btrim(p_place), 'event_id', p_event, 'status', 'pending'))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'message_id', v_id);
end $$;

create or replace function public.respond_date(p_message uuid, p_answer text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m messages%rowtype; v_name text;
begin
  if p_answer not in ('accepted','declined') then raise exception 'bad_answer'; end if;
  select * into m from messages where id = p_message and kind = 'date' for update;
  if not found or not is_match_member(m.match_id, auth.uid()) or m.sender_id = auth.uid() then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if m.payload->>'status' <> 'pending' then return jsonb_build_object('ok', false, 'error', 'already_answered'); end if;
  update messages set payload = payload || jsonb_build_object('status', p_answer, 'answered_at', now()), updated_at = now()
   where id = p_message;
  -- saying yes to an event plan also puts you on the list (gold wristband)
  if p_answer = 'accepted' and m.payload->>'event_id' is not null then
    insert into event_attendees (event_id, profile_id) values ((m.payload->>'event_id')::uuid, auth.uid())
    on conflict (event_id, profile_id) do update set status = 'going';
  end if;
  select name into v_name from profiles where id = auth.uid();
  perform queue_push(m.sender_id, 'date_answer', v_name, jsonb_build_object('url', '/chat/' || m.match_id), p_answer);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 3. Undo the last pass (Pro)
-- ---------------------------------------------------------------------
create or replace function public.rewind() returns jsonb
language plpgsql security definer set search_path = public as $$
declare w swipes%rowtype;
begin
  if not is_pro(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'pro_only'); end if;
  select * into w from swipes where swiper_id = auth.uid() order by created_at desc limit 1;
  if not found or w.kind <> 'pass' then return jsonb_build_object('ok', false, 'error', 'nothing_to_undo'); end if;
  delete from swipes where swiper_id = w.swiper_id and target_id = w.target_id;
  return jsonb_build_object('ok', true, 'profile', profile_card(w.target_id));
end $$;

-- ---------------------------------------------------------------------
-- 5. Travel mode (Pro): look in another city for up to 14 days
-- ---------------------------------------------------------------------
create or replace function public.set_travel(p_city text, p_days int) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_pro(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'pro_only'); end if;
  if not exists (select 1 from city_launch where city = p_city) then return jsonb_build_object('ok', false, 'error', 'bad_city'); end if;
  if p_days not between 1 and 14 then return jsonb_build_object('ok', false, 'error', 'bad_days'); end if;
  update profiles set travel_city = p_city, travel_until = now() + make_interval(days => p_days) where id = auth.uid();
  return jsonb_build_object('ok', true, 'until', now() + make_interval(days => p_days));
end $$;

create or replace function public.clear_travel() returns void
language sql security definer set search_path = public as $$
  update profiles set travel_city = null, travel_until = null where id = auth.uid()
$$;

-- ---------------------------------------------------------------------
-- Discover with modes, travel and contact hiding
-- ---------------------------------------------------------------------
drop function public.discover(int);
create or replace function public.discover(p_limit int default 20, p_mode text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_city text;
  v_season text := current_season();
  v_result jsonb;
begin
  select * into me from profiles where id = auth.uid();
  if not found then raise exception 'no_profile'; end if;
  v_city := effective_city(me);

  select coalesce(jsonb_agg(profile_card(c.id)
                              || jsonb_build_object('shared_sports', c.shared, 'super_liked_me', c.super_me,
                                                    'boosted', c.boosted, 'match_mode', c.mm)
                            order by c.boosted desc, c.super_me desc, c.shared_season desc, c.shared desc,
                                     c.last_active_at desc), '[]'::jsonb)
    into v_result
  from (
    select p.id, p.last_active_at,
           coalesce(p.boosted_until > now(), false) as boosted,
           exists (select 1 from swipes w where w.swiper_id = p.id and w.target_id = me.id and w.kind = 'super') as super_me,
           (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
             where a.profile_id = p.id and b.profile_id = me.id)::int as shared,
           (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
                                                 join sports s on s.code = a.sport_code
             where a.profile_id = p.id and b.profile_id = me.id and s.season in (v_season, 'all'))::int as shared_season,
           case when dating_ok(me, p) then 'dating' else 'buddy' end as mm
    from profiles p
    where p.id <> me.id
      and not p.hidden and not p.banned
      and effective_city(p) = v_city
      and coalesce(array_length(p.photos, 1), 0) >= 1
      and case coalesce(p_mode, '')
            when 'dating' then dating_ok(me, p)
            when 'buddy' then buddy_ok(me, p)
            else dating_ok(me, p) or buddy_ok(me, p) end
      and not exists (select 1 from swipes w where w.swiper_id = me.id and w.target_id = p.id)
      and not blocked_between(me.id, p.id)
      and not hidden_between(me.id, p.id)
    order by 3 desc, 4 desc, 6 desc, 5 desc, p.last_active_at desc
    limit least(greatest(p_limit, 1), 50)
  ) c;

  return v_result;
end $$;

-- ---------------------------------------------------------------------
-- swipe(): prompts on notes, dating or training-partner matches
-- ---------------------------------------------------------------------
drop function public.swipe(uuid, text, text);
create or replace function public.swipe(p_target uuid, p_kind text, p_note text default null,
                                        p_prompt text default null) returns jsonb
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

create or replace function public.on_match_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare a_name text; b_name text;
begin
  select name into a_name from profiles where id = new.user_a;
  select name into b_name from profiles where id = new.user_b;
  perform queue_push(new.user_a, case when new.kind = 'buddy' then 'buddy_match' else 'match' end, b_name, jsonb_build_object('url', '/chat/' || new.id));
  perform queue_push(new.user_b, case when new.kind = 'buddy' then 'buddy_match' else 'match' end, a_name, jsonb_build_object('url', '/chat/' || new.id));
  return new;
end $$;

create or replace function public.my_matches() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_data order by sort_at desc), '[]'::jsonb)
  from (
    select coalesce(m.last_message_at, m.created_at) as sort_at,
           jsonb_build_object(
             'match_id', m.id,
             'created_at', m.created_at,
             'kind', m.kind,
             'other', profile_card(case when m.user_a = auth.uid() then m.user_b else m.user_a end),
             'last_message', (select jsonb_build_object('body', x.body, 'sender_id', x.sender_id, 'created_at', x.created_at, 'kind', x.kind)
                              from messages x where x.match_id = m.id order by x.created_at desc limit 1),
             'unread', (select count(*) from messages x
                        where x.match_id = m.id and x.sender_id <> auth.uid() and x.read_at is null)
           ) as row_data
    from matches m
    where auth.uid() in (m.user_a, m.user_b)
      and m.unmatched_at is null
      and not blocked_between(m.user_a, m.user_b)
  ) s
$$;

-- ---------------------------------------------------------------------
-- 4. Daily picks: five people a day, chosen for what you share.
-- ---------------------------------------------------------------------
create table public.daily_picks (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  day        date not null,
  picks      uuid[] not null,
  primary key (profile_id, day)
);
alter table public.daily_picks enable row level security;
revoke all on public.daily_picks from public, anon, authenticated;

create or replace function public.daily_picks() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_ids uuid[];
  v_season text := current_season();
begin
  select * into me from profiles where id = auth.uid();
  if not found then raise exception 'no_profile'; end if;
  select picks into v_ids from daily_picks where profile_id = me.id and day = local_today();
  if v_ids is null then
    select coalesce(array_agg(id order by score desc, last_active_at desc), '{}') into v_ids from (
      select p.id, p.last_active_at,
             3 * (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
                                                     join sports s on s.code = a.sport_code
                   where a.profile_id = p.id and b.profile_id = me.id and s.season in (v_season, 'all'))
           + 1 * (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
                   where a.profile_id = p.id and b.profile_id = me.id)
           + 4 * (select count(*) from event_attendees x join event_attendees y on x.event_id = y.event_id
                   where x.profile_id = p.id and y.profile_id = me.id and x.status = 'going' and y.status = 'going')
           + 3 * (select count(*) from club_members x join club_members y on x.club_id = y.club_id
                   where x.profile_id = p.id and y.profile_id = me.id)
           + case when p.verification_status = 'approved' then 2 else 0 end
           + case when p.last_active_at > now() - interval '3 days' then 2 else 0 end as score
        from profiles p
       where p.id <> me.id and not p.hidden and not p.banned
         and effective_city(p) = effective_city(me)
         and coalesce(array_length(p.photos, 1), 0) >= 1
         and (dating_ok(me, p) or buddy_ok(me, p))
         and not exists (select 1 from swipes w where w.swiper_id = me.id and w.target_id = p.id)
         and not blocked_between(me.id, p.id)
         and not hidden_between(me.id, p.id)
       order by score desc, p.last_active_at desc
       limit 5) s;
    insert into daily_picks (profile_id, day, picks) values (me.id, local_today(), v_ids)
    on conflict (profile_id, day) do nothing;
  end if;
  return coalesce((
    select jsonb_agg(profile_card(x) || jsonb_build_object(
             'my_swipe', (select w.kind from swipes w where w.swiper_id = me.id and w.target_id = x),
             'match_mode', (select case when dating_ok(me, q) then 'dating' else 'buddy' end from profiles q where q.id = x))
           order by o)
      from unnest(v_ids) with ordinality as t(x, o)
      join profiles p on p.id = t.x
     where not p.banned and not blocked_between(me.id, x)), '[]'::jsonb);
end $$;

-- Evening nudge at 19:00 Almaty to people active in the last two weeks.
create or replace function public.send_picks_push() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from profiles where not banned and not hidden and last_active_at > now() - interval '14 days' loop
    perform queue_push(r.id, 'picks', null, jsonb_build_object('url', '/picks'));
    n := n + 1;
  end loop;
  return n;
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('qadam-daily-picks', '0 14 * * *', 'select public.send_picks_push()');  -- 14:00 UTC = 19:00 Almaty
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 9. Double dates: two friends team up as a duo and match with another duo.
-- ---------------------------------------------------------------------
create table public.duos (
  id          uuid primary key default gen_random_uuid(),
  a           uuid not null references public.profiles(id) on delete cascade,   -- who invited
  b           uuid not null references public.profiles(id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending','active','ended')),
  created_at  timestamptz not null default now(),
  check (a <> b)
);
create index on public.duos (a) where status <> 'ended';
create index on public.duos (b) where status <> 'ended';

create table public.duo_swipes (
  from_duo   uuid not null references public.duos(id) on delete cascade,
  to_duo     uuid not null references public.duos(id) on delete cascade,
  by_profile uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('like','pass')),
  created_at timestamptz not null default now(),
  primary key (from_duo, to_duo)
);

create table public.duo_matches (
  id         uuid primary key default gen_random_uuid(),
  duo_a      uuid not null references public.duos(id) on delete cascade,
  duo_b      uuid not null references public.duos(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (duo_a < duo_b),
  unique (duo_a, duo_b)
);

create table public.duo_messages (
  id            uuid primary key default gen_random_uuid(),
  duo_match_id  uuid not null references public.duo_matches(id) on delete cascade,
  sender_id     uuid not null references public.profiles(id) on delete cascade,
  body          text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at    timestamptz not null default now()
);
create index on public.duo_messages (duo_match_id, created_at desc);

alter table public.duos enable row level security;
alter table public.duo_swipes enable row level security;
alter table public.duo_matches enable row level security;
alter table public.duo_messages enable row level security;
revoke all on public.duos, public.duo_swipes, public.duo_matches, public.duo_messages from public, anon, authenticated;

create or replace function public.my_duo_id(p_profile uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select id from duos where status = 'active' and p_profile in (a, b) limit 1
$$;

create or replace function public.is_duo_match_member(p_match uuid, p_profile uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from duo_matches m join duos d on d.id in (m.duo_a, m.duo_b)
                  where m.id = p_match and p_profile in (d.a, d.b))
$$;

grant select on public.duo_messages to authenticated;
grant insert (duo_match_id, sender_id, body) on public.duo_messages to authenticated;
create policy duo_messages_read on public.duo_messages for select using (public.is_duo_match_member(duo_match_id, auth.uid()));
create policy duo_messages_send on public.duo_messages for insert
  with check (sender_id = auth.uid() and public.is_duo_match_member(duo_match_id, auth.uid()));

-- Invite a friend by their member number (№0042).
create or replace function public.duo_invite(p_member_no int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_friend uuid; v_name text;
begin
  if not exists (select 1 from profiles where id = auth.uid() and not banned) then raise exception 'no_profile'; end if;
  if exists (select 1 from duos where status in ('pending','active') and auth.uid() in (a, b)) then
    return jsonb_build_object('ok', false, 'error', 'already_in_duo');
  end if;
  select id into v_friend from profiles where member_no = p_member_no and not banned and id <> auth.uid();
  if v_friend is null or blocked_between(auth.uid(), v_friend) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if exists (select 1 from duos where status = 'active' and v_friend in (a, b)) then
    return jsonb_build_object('ok', false, 'error', 'friend_busy');
  end if;
  insert into duos (a, b) values (auth.uid(), v_friend);
  select name into v_name from profiles where id = auth.uid();
  perform queue_push(v_friend, 'duo_invite', v_name, jsonb_build_object('url', '/duo'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.duo_respond(p_duo uuid, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from duos where id = p_duo and b = auth.uid() and status = 'pending') then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if p_accept and exists (select 1 from duos where status = 'active' and auth.uid() in (a, b)) then
    return jsonb_build_object('ok', false, 'error', 'already_in_duo');
  end if;
  update duos set status = case when p_accept then 'active' else 'ended' end where id = p_duo;
  if p_accept then
    -- other pending invites to me lapse
    update duos set status = 'ended' where status = 'pending' and b = auth.uid() and id <> p_duo;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.duo_leave() returns void
language sql security definer set search_path = public as $$
  update duos set status = 'ended' where status in ('pending','active') and auth.uid() in (a, b)
$$;

create or replace function public.duo_members(p_duo uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_array(profile_card(d.a), profile_card(d.b)) from duos d where d.id = p_duo
$$;

-- My duo, invites waiting for me, and our double-date chats.
create or replace function public.my_duo() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'duo', (select jsonb_build_object('id', d.id, 'status', d.status, 'i_invited', d.a = auth.uid(),
                                      'partner', profile_card(case when d.a = auth.uid() then d.b else d.a end))
              from duos d where d.status in ('pending','active') and auth.uid() in (d.a, d.b)
              order by d.status = 'active' desc, d.created_at desc limit 1),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'from', profile_card(d.a)) order by d.created_at desc)
                         from duos d where d.status = 'pending' and d.b = auth.uid()), '[]'::jsonb),
    'matches', coalesce((select jsonb_agg(jsonb_build_object(
                           'id', m.id, 'created_at', m.created_at,
                           'other', duo_members(case when m.duo_a in (select id from duos where auth.uid() in (a, b)) then m.duo_b else m.duo_a end),
                           'last_message', (select jsonb_build_object('body', x.body, 'created_at', x.created_at, 'sender_id', x.sender_id)
                                            from duo_messages x where x.duo_match_id = m.id order by x.created_at desc limit 1))
                         order by m.created_at desc)
                         from duo_matches m where is_duo_match_member(m.id, auth.uid())), '[]'::jsonb)
  )
$$;

-- Other duos in my city where the pairs fit each other's preferences.
create or replace function public.duo_discover() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_duo uuid := my_duo_id(auth.uid()); m1 profiles%rowtype; m2 profiles%rowtype; d duos%rowtype;
begin
  if v_duo is null then return '[]'::jsonb; end if;
  select * into d from duos where id = v_duo;
  select * into m1 from profiles where id = d.a;
  select * into m2 from profiles where id = d.b;
  return coalesce((
    select jsonb_agg(jsonb_build_object('duo_id', o.id, 'members', duo_members(o.id)) order by o.created_at desc)
      from duos o
      join profiles o1 on o1.id = o.a
      join profiles o2 on o2.id = o.b
     where o.status = 'active' and o.id <> v_duo
       and effective_city(o1) = effective_city(m1)
       and not o1.banned and not o2.banned and not o1.hidden and not o2.hidden
       and not exists (select 1 from duo_swipes s where s.from_duo = v_duo and s.to_duo = o.id)
       and not blocked_between(m1.id, o1.id) and not blocked_between(m1.id, o2.id)
       and not blocked_between(m2.id, o1.id) and not blocked_between(m2.id, o2.id)
       and not hidden_between(m1.id, o1.id) and not hidden_between(m1.id, o2.id)
       and not hidden_between(m2.id, o1.id) and not hidden_between(m2.id, o2.id)
       and ((dating_ok(m1, o1) and dating_ok(m2, o2)) or (dating_ok(m1, o2) and dating_ok(m2, o1)))
     limit 20), '[]'::jsonb);
end $$;

-- Either friend can decide for the duo; a match needs a like from each side.
create or replace function public.duo_swipe(p_duo uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_duo uuid := my_duo_id(auth.uid()); v_match uuid; r record;
begin
  if v_duo is null then return jsonb_build_object('ok', false, 'error', 'no_duo'); end if;
  if p_kind not in ('like','pass') or p_duo = v_duo then raise exception 'bad_swipe'; end if;
  if not exists (select 1 from duos where id = p_duo and status = 'active') then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  insert into duo_swipes (from_duo, to_duo, by_profile, kind) values (v_duo, p_duo, auth.uid(), p_kind)
  on conflict (from_duo, to_duo) do update set kind = excluded.kind, by_profile = excluded.by_profile, created_at = now();
  if p_kind = 'like' and exists (select 1 from duo_swipes where from_duo = p_duo and to_duo = v_duo and kind = 'like') then
    insert into duo_matches (duo_a, duo_b) values (least(v_duo, p_duo), greatest(v_duo, p_duo))
    on conflict (duo_a, duo_b) do nothing returning id into v_match;
    if v_match is not null then
      for r in select unnest(array[d.a, d.b]) as pid from duos d where d.id in (v_duo, p_duo) loop
        perform queue_push(r.pid, 'duo_match', null, jsonb_build_object('url', '/duo/chat/' || v_match));
      end loop;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'match_id', v_match);
end $$;

create or replace function public.duo_feed(p_match uuid, p_before timestamptz default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'sender_id', x.sender_id, 'body', x.body, 'created_at', x.created_at,
           'sender', jsonb_build_object('name', p.name, 'photo', p.photos[1], 'member_no', p.member_no))
         order by x.created_at desc), '[]'::jsonb)
  from (select * from duo_messages m
         where m.duo_match_id = p_match and (p_before is null or m.created_at < p_before)
           and is_duo_match_member(p_match, auth.uid())
         order by m.created_at desc limit 50) x
  join profiles p on p.id = x.sender_id
  where not blocked_between(auth.uid(), x.sender_id)
$$;

-- ---------------------------------------------------------------------
-- Push kinds, storage, realtime
-- ---------------------------------------------------------------------
alter table public.push_outbox drop constraint push_outbox_kind_check;
alter table public.push_outbox add constraint push_outbox_kind_check
  check (kind in ('match','message','like','super','event_reminder','city_open','club_event',
                  'date_answer','picks','buddy_match','duo_invite','duo_match'));

create or replace function public.push_text(p_locale text, p_kind text, p_name text, p_extra text default null)
returns table (title text, body text)
language sql immutable set search_path = public as $$
  select
    case p_kind
      when 'match' then case p_locale when 'kk' then 'Жүректер сәйкес келді!' when 'en' then 'Hearts in sync!' else 'Сердца совпали!' end
      when 'message' then p_name
      when 'like' then 'Qadam'
      when 'super' then 'Qadam'
      when 'event_reminder' then coalesce(p_extra, 'Qadam')
      when 'city_open' then 'Qadam'
      when 'club_event' then coalesce(p_extra, 'Qadam')
      when 'date_answer' then p_name
      when 'picks' then 'Qadam'
      when 'buddy_match' then case p_locale when 'kk' then 'Серіктес табылды!' when 'en' then 'Training partner found!' else 'Напарник найден!' end
      when 'duo_invite' then p_name
      when 'duo_match' then case p_locale when 'kk' then 'Қос кездесу!' when 'en' then 'Double date!' else 'Двойное свидание!' end
    end,
    case p_kind
      when 'match' then case p_locale
        when 'kk' then p_name || ' екеуің бір-біріңді ұнаттыңдар. Бірінші боп жаз.'
        when 'en' then 'You and ' || p_name || ' liked each other. Say hi first.'
        else 'Вы с ' || p_name || ' понравились друг другу. Напишите первым.' end
      when 'message' then case p_locale
        when 'kk' then 'Жаңа хабарлама' when 'en' then 'New message' else 'Новое сообщение' end
      when 'like' then case p_locale
        when 'kk' then 'Біреу сізді ұнатты. Кім екенін көріңіз.'
        when 'en' then 'Someone liked you. See who.'
        else 'Вы кому-то понравились. Посмотрите, кому.' end
      when 'super' then case p_locale
        when 'kk' then 'Біреу сізге супер-лайк басты!'
        when 'en' then 'Someone super liked you!'
        else 'Вам поставили суперлайк!' end
      when 'event_reminder' then case p_locale
        when 'kk' then '2 сағаттан кейін басталады. Кездескенше!'
        when 'en' then 'Starts in 2 hours. See you there!'
        else 'Начало через 2 часа. До встречи!' end
      when 'city_open' then case p_locale
        when 'kk' then city_label(p_name, p_locale) || ' ашылды! Анкеталар сізді күтіп тұр.'
        when 'en' then city_label(p_name, p_locale) || ' is open! Start discovering.'
        else city_label(p_name, p_locale) || ' открыт! Анкеты уже ждут.' end
      when 'club_event' then case p_locale
        when 'kk' then p_name || ' клубында жаңа іс-шара. Орын алыңыз.'
        when 'en' then 'New event in ' || p_name || '. Save your spot.'
        else 'Новое событие в клубе ' || p_name || '. Займите место.' end
      when 'date_answer' then case
        when p_extra = 'accepted' then case p_locale when 'kk' then 'Кездесуге келісті!' when 'en' then 'Said yes to your plan!' else 'Согласен(на) на встречу!' end
        else case p_locale when 'kk' then 'Бұл уақыт ыңғайсыз. Басқасын ұсыныңыз.' when 'en' then 'That time doesn''t work. Suggest another?' else 'Это время не подходит. Предложите другое?' end end
      when 'picks' then case p_locale
        when 'kk' then 'Бүгінгі 5 таңдау дайын.' when 'en' then 'Today''s 5 picks are ready.' else 'Сегодняшние 5 рекомендаций готовы.' end
      when 'buddy_match' then case p_locale
        when 'kk' then p_name || ' бірге жаттығуға дайын.' when 'en' then p_name || ' wants to train together.' else p_name || ' хочет тренироваться вместе.' end
      when 'duo_invite' then case p_locale
        when 'kk' then 'Қос кездесуге шақырды.' when 'en' then 'Invited you to team up for double dates.' else 'Зовёт вас в пару для двойных свиданий.' end
      when 'duo_match' then case p_locale
        when 'kk' then 'Екі жұп бір-бірін ұнатты. Төртеуіңіз чатта.' when 'en' then 'Both pairs liked each other. The four of you have a chat.' else 'Обе пары понравились друг другу. У вас общий чат.' end
    end
$$;
revoke execute on function public.push_text(text, text, text, text) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.duo_messages;
  end if;

  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not present; skipping chat-media bucket';
    return;
  end if;
  -- Chat photos and voice notes: private; only the two people in the match can read or add files
  -- in the match's folder (<match_id>/<file>).
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('chat-media', 'chat-media', false, 10 * 1024 * 1024,
          array['image/jpeg','image/png','image/webp','image/heic','audio/m4a','audio/mp4','audio/aac','audio/x-m4a'])
  on conflict (id) do nothing;
  execute $p$create policy chat_media_read on storage.objects for select to authenticated
    using (bucket_id = 'chat-media' and public.is_match_member(((storage.foldername(name))[1])::uuid, auth.uid()))$p$;
  execute $p$create policy chat_media_write on storage.objects for insert to authenticated
    with check (bucket_id = 'chat-media' and public.is_match_member(((storage.foldername(name))[1])::uuid, auth.uid()))$p$;
end $$;

-- ---------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------
revoke execute on function
  public.effective_city(profiles), public.wants(profiles, profiles, text), public.dating_ok(profiles, profiles),
  public.buddy_ok(profiles, profiles), public.qadam_hash(text), public.on_profile_identity(),
  public.prompt_context(uuid, text), public.check_message(), public.send_picks_push(),
  public.duo_members(uuid), public.my_duo_id(uuid)
from public, anon, authenticated;

revoke execute on function public.hidden_between(uuid, uuid), public.is_match_member(uuid, uuid),
  public.is_duo_match_member(uuid, uuid) from public, anon;
grant execute on function public.hidden_between(uuid, uuid), public.is_match_member(uuid, uuid),
  public.is_duo_match_member(uuid, uuid) to authenticated;   -- used by policies

revoke execute on function
  public.discover(int, text), public.swipe(uuid, text, text, text), public.set_contact_hides(text[]),
  public.set_phone_hash(text), public.contact_hides_count(), public.react(uuid, text),
  public.chat_messages(uuid, timestamptz), public.propose_date(uuid, text, timestamptz, text, uuid),
  public.respond_date(uuid, text), public.rewind(), public.set_travel(text, int), public.clear_travel(),
  public.daily_picks(), public.duo_invite(int), public.duo_respond(uuid, boolean), public.duo_leave(),
  public.my_duo(), public.duo_discover(), public.duo_swipe(uuid, text), public.duo_feed(uuid, timestamptz)
from public, anon;
grant execute on function
  public.discover(int, text), public.swipe(uuid, text, text, text), public.set_contact_hides(text[]),
  public.set_phone_hash(text), public.contact_hides_count(), public.react(uuid, text),
  public.chat_messages(uuid, timestamptz), public.propose_date(uuid, text, timestamptz, text, uuid),
  public.respond_date(uuid, text), public.rewind(), public.set_travel(text, int), public.clear_travel(),
  public.daily_picks(), public.duo_invite(int), public.duo_respond(uuid, boolean), public.duo_leave(),
  public.my_duo(), public.duo_discover(), public.duo_swipe(uuid, text), public.duo_feed(uuid, timestamptz)
to authenticated;

-- ===== migrations/20261021000007_nationwide.sql =====
-- Nationwide launch: every city is open from day one.
-- (The city-launch mechanism stays: set opens_at_members > 0 and opened_at = null
-- on a future city to gate it again.)
update public.city_launch
   set opens_at_members = 0,
       opened_at = coalesce(opened_at, now());

-- ===== migrations/20261021000008_photo_safety.sql =====
-- Photo safety: no photos from strangers. A photo can be sent in a chat only
-- after both people have written at least one text message there (the opening
-- note on a like counts). Voice notes and date cards are unaffected.
create or replace function public.check_message() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.media_path is not null and new.media_path not like new.match_id::text || '/%' then
    raise exception 'bad_media_path' using errcode = '42501';
  end if;
  if new.reply_to is not null and not exists (select 1 from messages where id = new.reply_to and match_id = new.match_id) then
    raise exception 'bad_reply' using errcode = '42501';
  end if;
  if new.kind = 'photo' and not (
       exists (select 1 from messages where match_id = new.match_id and sender_id = new.sender_id and kind = 'text')
   and exists (select 1 from messages where match_id = new.match_id and sender_id <> new.sender_id and kind = 'text')
  ) then
    raise exception 'photo_too_soon' using errcode = '42501';
  end if;
  return new;
end $$;

-- ===== migrations/20261021000009_fair_exposure.sql =====
-- Fair exposure: likes shouldn't pile up on a few profiles while everyone else
-- goes unseen. No photo or attractiveness score is involved. The only signal is
-- how many likes a person has waiting that they haven't answered yet:
--   * 10+ unanswered likes in the last 14 days → shown after people with fewer
--   * 25+                                      → shown after those
-- Answering likes (yes or no) brings someone straight back. New members
-- (first 3 days, fewer than 5 likes so far) are shown a little earlier so they
-- get a fair start. Paid boosts and "super liked you" still come first.

create or replace function public.cfg(key text) returns int
language sql immutable as $$
  select case key
    when 'free_daily_likes'      then 30
    when 'free_daily_supers'     then 1
    when 'pro_daily_supers'      then 5
    when 'boost_minutes'         then 30
    when 'streak_days_for_boost' then 7
    when 'referrals_for_bonus'   then 2
    when 'referral_bonus_days'   then 7
    when 'reports_to_autohide'   then 3
    when 'exposure_soft_cap'     then 10   -- unanswered likes before someone is shown later
    when 'exposure_hard_cap'     then 25   -- … and later still
    when 'exposure_window_days'  then 14
    when 'newcomer_days'         then 3
    when 'newcomer_max_likes'    then 5
  end
$$;

create index if not exists swipes_target_time_idx on public.swipes (target_id, created_at);

/** Likes and super likes received recently that this person hasn't answered. */
create or replace function public.pending_likes(p_id uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int
    from swipes w
    join profiles s on s.id = w.swiper_id and not s.banned
   where w.target_id = p_id
     and w.kind in ('like', 'super')
     and w.created_at > now() - make_interval(days => cfg('exposure_window_days'))
     and not exists (select 1 from swipes r where r.swiper_id = p_id and r.target_id = w.swiper_id)
$$;

/** 0 = normal, 1 = shown later, 2 = shown last. */
create or replace function public.exposure_tier(p_id uuid) returns int
language sql stable security definer set search_path = public as $$
  select case
    when n >= cfg('exposure_hard_cap') then 2
    when n >= cfg('exposure_soft_cap') then 1
    else 0 end
  from (select pending_likes(p_id) as n) x
$$;

create or replace function public.is_newcomer(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.created_at > now() - make_interval(days => cfg('newcomer_days'))
       and (select count(*) from swipes w where w.target_id = p.id and w.kind in ('like', 'super')) < cfg('newcomer_max_likes')
      from profiles p where p.id = p_id), false)
$$;

create or replace function public.discover(p_limit int default 20, p_mode text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_city text;
  v_season text := current_season();
  v_result jsonb;
begin
  select * into me from profiles where id = auth.uid();
  if not found then raise exception 'no_profile'; end if;
  v_city := effective_city(me);

  select coalesce(jsonb_agg(profile_card(c.id)
                              || jsonb_build_object('shared_sports', c.shared, 'super_liked_me', c.super_me,
                                                    'boosted', c.boosted, 'match_mode', c.mm)
                            order by c.boosted desc, c.super_me desc, c.tier asc, c.newcomer desc,
                                     c.shared_season desc, c.shared desc, c.last_active_at desc), '[]'::jsonb)
    into v_result
  from (
    select q.* from (
      select p.id, p.last_active_at,
             coalesce(p.boosted_until > now(), false) as boosted,
             exists (select 1 from swipes w where w.swiper_id = p.id and w.target_id = me.id and w.kind = 'super') as super_me,
             (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
               where a.profile_id = p.id and b.profile_id = me.id)::int as shared,
             (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
                                                   join sports s on s.code = a.sport_code
               where a.profile_id = p.id and b.profile_id = me.id and s.season in (v_season, 'all'))::int as shared_season,
             case when dating_ok(me, p) then 'dating' else 'buddy' end as mm,
             exposure_tier(p.id) as tier,
             is_newcomer(p.id) as newcomer
      from profiles p
      where p.id <> me.id
        and not p.hidden and not p.banned
        and effective_city(p) = v_city
        and coalesce(array_length(p.photos, 1), 0) >= 1
        and case coalesce(p_mode, '')
              when 'dating' then dating_ok(me, p)
              when 'buddy' then buddy_ok(me, p)
              else dating_ok(me, p) or buddy_ok(me, p) end
        and not exists (select 1 from swipes w where w.swiper_id = me.id and w.target_id = p.id)
        and not blocked_between(me.id, p.id)
        and not hidden_between(me.id, p.id)
    ) q
    order by q.boosted desc, q.super_me desc, q.tier asc, q.newcomer desc,
             q.shared_season desc, q.shared desc, q.last_active_at desc
    limit least(greatest(p_limit, 1), 50)
  ) c;

  return v_result;
end $$;

create or replace function public.daily_picks() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_ids uuid[];
  v_season text := current_season();
begin
  select * into me from profiles where id = auth.uid();
  if not found then raise exception 'no_profile'; end if;
  select picks into v_ids from daily_picks where profile_id = me.id and day = local_today();
  if v_ids is null then
    select coalesce(array_agg(id order by score desc, last_active_at desc), '{}') into v_ids from (
      select p.id, p.last_active_at,
             3 * (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
                                                     join sports s on s.code = a.sport_code
                   where a.profile_id = p.id and b.profile_id = me.id and s.season in (v_season, 'all'))
           + 1 * (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
                   where a.profile_id = p.id and b.profile_id = me.id)
           + 4 * (select count(*) from event_attendees x join event_attendees y on x.event_id = y.event_id
                   where x.profile_id = p.id and y.profile_id = me.id and x.status = 'going' and y.status = 'going')
           + 3 * (select count(*) from club_members x join club_members y on x.club_id = y.club_id
                   where x.profile_id = p.id and y.profile_id = me.id)
           + case when p.verification_status = 'approved' then 2 else 0 end
           + case when p.last_active_at > now() - interval '3 days' then 2 else 0 end
           + case when is_newcomer(p.id) then 2 else 0 end
           - 4 * exposure_tier(p.id) as score
        from profiles p
       where p.id <> me.id and not p.hidden and not p.banned
         and effective_city(p) = effective_city(me)
         and coalesce(array_length(p.photos, 1), 0) >= 1
         and (dating_ok(me, p) or buddy_ok(me, p))
         and not exists (select 1 from swipes w where w.swiper_id = me.id and w.target_id = p.id)
         and not blocked_between(me.id, p.id)
         and not hidden_between(me.id, p.id)
       order by score desc, p.last_active_at desc
       limit 5) s;
    insert into daily_picks (profile_id, day, picks) values (me.id, local_today(), v_ids)
    on conflict (profile_id, day) do nothing;
  end if;
  return coalesce((
    select jsonb_agg(profile_card(x) || jsonb_build_object(
             'my_swipe', (select w.kind from swipes w where w.swiper_id = me.id and w.target_id = x),
             'match_mode', (select case when dating_ok(me, q) then 'dating' else 'buddy' end from profiles q where q.id = x))
           order by o)
      from unnest(v_ids) with ordinality as t(x, o)
      join profiles p on p.id = t.x
     where not p.banned and not blocked_between(me.id, x)), '[]'::jsonb);
end $$;

-- Internal signals: never callable from the app.
revoke all on function public.pending_likes(uuid), public.exposure_tier(uuid), public.is_newcomer(uuid)
  from public, anon, authenticated;

-- ===== migrations/20261021000010_member_events_badges.sql =====
-- Member-hosted events, honest check-in, badges, founding numbers and a Pro gift.
--
-- 1. Hosting: any verified member (selfie approved) can create an event, as well
--    as approved hosts. Member events are free, at most 50 people, start within
--    60 days, and one member can have at most 3 upcoming events at a time.
-- 2. Check-in needs the host's code, which changes every minute, so the
--    "Showed up" and "Regular" badges can't be earned from the sofa.
-- 3. Badges are computed from what people did, never from likes received, and
--    can't be bought.
-- 4. Founding members: each city numbers its members as they join; the first
--    1,000 in a city keep a Founding badge for good.
-- 5. Gift a week of Pro: a Pro member can create one gift code every 30 days;
--    someone who isn't Pro redeems it for 7 days of Pro, once ever.

-- ---------------------------------------------------------------------
-- 1. Hosting
-- ---------------------------------------------------------------------
create or replace function public.can_host(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p where p.id = uid and not p.banned
                 and (p.is_host or p.verification_status = 'approved'))
$$;

drop policy if exists events_host_insert on public.events;
create policy events_host_insert on public.events for insert
  with check (host_id = auth.uid() and public.can_host(auth.uid()));

create or replace function public.check_member_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_official boolean;
begin
  if new.host_id is null then return new; end if;  -- system / imported events
  select is_host into v_official from profiles where id = new.host_id;
  if coalesce(v_official, false) then return new; end if;  -- approved hosts and clubs keep their limits
  if new.price_kzt <> 0 then raise exception 'member_events_are_free' using errcode = '42501'; end if;
  if new.capacity > 50 then raise exception 'capacity_too_large' using errcode = '42501'; end if;
  if (tg_op = 'INSERT' or new.starts_at is distinct from old.starts_at)
     and (new.starts_at < now() or new.starts_at > now() + interval '60 days') then
    raise exception 'bad_start_time' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and (select count(*) from events e
       where e.host_id = new.host_id and not e.cancelled and e.starts_at > now()) >= 3 then
    raise exception 'too_many_upcoming' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists events_member_check on public.events;
create trigger events_member_check before insert or update of price_kzt, capacity, starts_at on public.events
  for each row execute function public.check_member_event();

-- The host goes to their own event.
create or replace function public.on_event_insert_host() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.host_id is not null then
    insert into event_attendees (event_id, profile_id) values (new.id, new.host_id) on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists events_host_attends on public.events;
create trigger events_host_attends after insert on public.events
  for each row execute function public.on_event_insert_host();

-- ---------------------------------------------------------------------
-- 2. Check-in codes
-- ---------------------------------------------------------------------
create table public.event_secrets (
  event_id uuid primary key references public.events(id) on delete cascade,
  secret   uuid not null default gen_random_uuid()
);
alter table public.event_secrets enable row level security;
revoke all on public.event_secrets from public, anon, authenticated;
insert into public.event_secrets (event_id) select id from public.events on conflict do nothing;

create or replace function public.on_event_secret() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into event_secrets (event_id) values (new.id) on conflict do nothing;
  return new;
end $$;
drop trigger if exists events_secret on public.events;
create trigger events_secret after insert on public.events
  for each row execute function public.on_event_secret();

/** The 4-digit code for a given minute (internal). */
create or replace function public.checkin_code(p_event uuid, p_at timestamptz) returns text
language sql stable security definer set search_path = public as $$
  select lpad((abs(hashtext(s.secret::text || ':' || floor(extract(epoch from p_at) / 60)::bigint::text)) % 10000)::text, 4, '0')
    from event_secrets s where s.event_id = p_event
$$;

/** For the host's screen: the current code and how many seconds it stays valid. */
create or replace function public.host_checkin_code(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e events%rowtype;
begin
  select * into e from events where id = p_event;
  if not found or e.host_id is distinct from auth.uid() then return jsonb_build_object('ok', false, 'error', 'not_host'); end if;
  return jsonb_build_object('ok', true, 'code', checkin_code(p_event, now()),
                            'seconds_left', 60 - floor(extract(epoch from now()))::bigint % 60);
end $$;

drop function if exists public.check_in(uuid);
create or replace function public.check_in(p_event uuid, p_code text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e events%rowtype;
begin
  select * into e from events where id = p_event;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if now() < e.starts_at - interval '30 minutes'
     or now() > e.starts_at + make_interval(mins => e.duration_min) then
    return jsonb_build_object('ok', false, 'error', 'not_now');
  end if;
  -- The host checks in without a code; everyone else needs this minute's or the previous one's.
  if e.host_id is distinct from auth.uid()
     and coalesce(p_code, '') not in (checkin_code(p_event, now()), checkin_code(p_event, now() - interval '1 minute')) then
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;
  update event_attendees set checked_in_at = coalesce(checked_in_at, now())
   where event_id = p_event and profile_id = auth.uid() and status = 'going';
  if not found then return jsonb_build_object('ok', false, 'error', 'not_going'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. Founding numbers per city (before badges, which use them)
-- ---------------------------------------------------------------------
create table public.city_counters (city text primary key, last_no int not null default 0);
alter table public.city_counters enable row level security;
revoke all on public.city_counters from public, anon, authenticated;

alter table public.profiles add column if not exists city_no int;
alter table public.profiles add column if not exists city_no_city text;

create or replace function public.assign_city_no() returns trigger
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  insert into city_counters (city, last_no) values (new.city, 1)
  on conflict (city) do update set last_no = city_counters.last_no + 1
  returning last_no into v;
  new.city_no := v;
  new.city_no_city := new.city;
  return new;
end $$;
drop trigger if exists profiles_city_no on public.profiles;
create trigger profiles_city_no before insert on public.profiles
  for each row execute function public.assign_city_no();

-- existing members, in join order
with ranked as (
  select id, city, row_number() over (partition by city order by created_at, member_no) as n from profiles
)
update profiles p set city_no = r.n, city_no_city = r.city from ranked r where r.id = p.id and p.city_no is null;
insert into city_counters (city, last_no)
  select city_no_city, max(city_no) from profiles where city_no is not null group by city_no_city
on conflict (city) do update set last_no = greatest(city_counters.last_no, excluded.last_no);

-- ---------------------------------------------------------------------
-- 3. Badges
-- ---------------------------------------------------------------------
create or replace function public.profile_badges(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with p as (select * from profiles where id = p_id),
  att as (
    select e.id, e.host_id, s.season
      from event_attendees a join events e on e.id = a.event_id join sports s on s.code = e.sport_code
     where a.profile_id = p_id and a.checked_in_at is not null
  )
  select coalesce(jsonb_agg(b order by o), '[]'::jsonb) from (
    select 'founding' as b, 1 as o from p where p.city_no <= 1000
    union all select 'verified', 2 from p where p.verification_status = 'approved'
    union all select 'first_step', 3 where exists (
      select 1 from messages m where m.sender_id = p_id and m.kind = 'date' and m.payload->>'status' = 'accepted')
    union all select 'showed_up', 4 where (select count(*) from att) >= 1
    union all select 'regular', 5 where (select count(*) from att) >= 5
    union all select 'host', 6 where (
      select count(*) from events e
       where e.host_id = p_id and not e.cancelled
         and (select count(*) from event_attendees a
               where a.event_id = e.id and a.profile_id <> p_id and a.checked_in_at is not null) >= 3) >= 3
    union all select 'winter', 7 where exists (select 1 from att where att.season = 'winter')
    union all select 'summer', 8 where exists (select 1 from att where att.season = 'summer')
  ) x
$$;

alter function public.profile_card(uuid) rename to profile_card_base;
create or replace function public.profile_card(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.profile_card_base(p_id)
      || jsonb_build_object('badges', public.profile_badges(p_id),
                            'city_no', (select city_no from profiles where id = p_id))
$$;
revoke execute on function public.profile_card(uuid), public.profile_card_base(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Gift a week of Pro
-- ---------------------------------------------------------------------
create table public.pro_gifts (
  code         text primary key,
  giver_id     uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  redeemed_by  uuid unique references public.profiles(id) on delete set null,
  redeemed_at  timestamptz
);
alter table public.pro_gifts enable row level security;
revoke all on public.pro_gifts from public, anon, authenticated;

create or replace function public.create_pro_gift() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_code text; v_last timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if not is_pro(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'pro_only'); end if;
  select max(created_at) into v_last from pro_gifts where giver_id = auth.uid();
  if v_last > now() - interval '30 days' then
    -- the unredeemed code from this month, if any, is handed back
    select code into v_code from pro_gifts where giver_id = auth.uid() and created_at = v_last and redeemed_by is null;
    if v_code is not null then return jsonb_build_object('ok', true, 'code', v_code); end if;
    return jsonb_build_object('ok', false, 'error', 'once_a_month', 'next_at', v_last + interval '30 days');
  end if;
  loop
    v_code := substr(translate(upper(encode(gen_random_bytes(9), 'base64')), '+/=OI01L', ''), 1, 8);
    exit when length(v_code) = 8 and not exists (select 1 from pro_gifts where code = v_code);
  end loop;
  insert into pro_gifts (code, giver_id) values (v_code, auth.uid());
  return jsonb_build_object('ok', true, 'code', v_code);
end $$;

create or replace function public.redeem_pro_gift(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g pro_gifts%rowtype;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into g from pro_gifts where code = upper(btrim(p_code)) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if g.redeemed_by is not null then return jsonb_build_object('ok', false, 'error', 'used'); end if;
  if g.giver_id = auth.uid() then return jsonb_build_object('ok', false, 'error', 'own_gift'); end if;
  if is_pro(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'already_pro'); end if;
  if exists (select 1 from pro_gifts where redeemed_by = auth.uid()) then
    return jsonb_build_object('ok', false, 'error', 'already_redeemed');
  end if;
  update pro_gifts set redeemed_by = auth.uid(), redeemed_at = now() where code = g.code;
  update profiles set bonus_pro_until = greatest(coalesce(bonus_pro_until, now()), now()) + interval '7 days'
   where id = auth.uid();
  return jsonb_build_object('ok', true, 'days', 7);
end $$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke all on function public.checkin_code(uuid, timestamptz), public.profile_badges(uuid),
  public.check_member_event(), public.on_event_insert_host(), public.on_event_secret(), public.assign_city_no()
  from public, anon, authenticated;
revoke all on function public.can_host(uuid), public.host_checkin_code(uuid), public.check_in(uuid, text),
  public.create_pro_gift(), public.redeem_pro_gift(text) from public, anon;
grant execute on function public.can_host(uuid), public.host_checkin_code(uuid), public.check_in(uuid, text),
  public.create_pro_gift(), public.redeem_pro_gift(text) to authenticated;

-- ===== migrations/20261021000011_rename_jur.sql =====
-- The brand is now JÜR (from Qadam). Push notification titles use the new name.
create or replace function public.push_text(p_locale text, p_kind text, p_name text, p_extra text default null)
returns table (title text, body text)
language sql immutable set search_path = public as $$
  select
    case p_kind
      when 'match' then case p_locale when 'kk' then 'Жүректер сәйкес келді!' when 'en' then 'Hearts in sync!' else 'Сердца совпали!' end
      when 'message' then p_name
      when 'like' then 'JÜR'
      when 'super' then 'JÜR'
      when 'event_reminder' then coalesce(p_extra, 'JÜR')
      when 'city_open' then 'JÜR'
      when 'club_event' then coalesce(p_extra, 'JÜR')
      when 'date_answer' then p_name
      when 'picks' then 'JÜR'
      when 'buddy_match' then case p_locale when 'kk' then 'Серіктес табылды!' when 'en' then 'Training partner found!' else 'Напарник найден!' end
      when 'duo_invite' then p_name
      when 'duo_match' then case p_locale when 'kk' then 'Қос кездесу!' when 'en' then 'Double date!' else 'Двойное свидание!' end
    end,
    case p_kind
      when 'match' then case p_locale
        when 'kk' then p_name || ' екеуің бір-біріңді ұнаттыңдар. Бірінші боп жаз.'
        when 'en' then 'You and ' || p_name || ' liked each other. Say hi first.'
        else 'Вы с ' || p_name || ' понравились друг другу. Напишите первым.' end
      when 'message' then case p_locale
        when 'kk' then 'Жаңа хабарлама' when 'en' then 'New message' else 'Новое сообщение' end
      when 'like' then case p_locale
        when 'kk' then 'Біреу сізді ұнатты. Кім екенін көріңіз.'
        when 'en' then 'Someone liked you. See who.'
        else 'Вы кому-то понравились. Посмотрите, кому.' end
      when 'super' then case p_locale
        when 'kk' then 'Біреу сізге супер-лайк басты!'
        when 'en' then 'Someone super liked you!'
        else 'Вам поставили суперлайк!' end
      when 'event_reminder' then case p_locale
        when 'kk' then '2 сағаттан кейін басталады. Кездескенше!'
        when 'en' then 'Starts in 2 hours. See you there!'
        else 'Начало через 2 часа. До встречи!' end
      when 'city_open' then case p_locale
        when 'kk' then city_label(p_name, p_locale) || ' ашылды! Анкеталар сізді күтіп тұр.'
        when 'en' then city_label(p_name, p_locale) || ' is open! Start discovering.'
        else city_label(p_name, p_locale) || ' открыт! Анкеты уже ждут.' end
      when 'club_event' then case p_locale
        when 'kk' then p_name || ' клубында жаңа іс-шара. Орын алыңыз.'
        when 'en' then 'New event in ' || p_name || '. Save your spot.'
        else 'Новое событие в клубе ' || p_name || '. Займите место.' end
      when 'date_answer' then case
        when p_extra = 'accepted' then case p_locale when 'kk' then 'Кездесуге келісті!' when 'en' then 'Said yes to your plan!' else 'Согласен(на) на встречу!' end
        else case p_locale when 'kk' then 'Бұл уақыт ыңғайсыз. Басқасын ұсыныңыз.' when 'en' then 'That time doesn''t work. Suggest another?' else 'Это время не подходит. Предложите другое?' end end
      when 'picks' then case p_locale
        when 'kk' then 'Бүгінгі 5 таңдау дайын.' when 'en' then 'Today''s 5 picks are ready.' else 'Сегодняшние 5 рекомендаций готовы.' end
      when 'buddy_match' then case p_locale
        when 'kk' then p_name || ' бірге жаттығуға дайын.' when 'en' then p_name || ' wants to train together.' else p_name || ' хочет тренироваться вместе.' end
      when 'duo_invite' then case p_locale
        when 'kk' then 'Қос кездесуге шақырды.' when 'en' then 'Invited you to team up for double dates.' else 'Зовёт вас в пару для двойных свиданий.' end
      when 'duo_match' then case p_locale
        when 'kk' then 'Екі жұп бір-бірін ұнатты. Төртеуіңіз чатта.' when 'en' then 'Both pairs liked each other. The four of you have a chat.' else 'Обе пары понравились друг другу. У вас общий чат.' end
    end
$$;

-- ===== migrations/20261021000012_native_push.sql =====
-- Native iOS push. The SwiftUI app registers raw APNs device tokens (hex), which
-- Expo's push service can't deliver to. queue_push now sends those through the
-- "apns" Edge Function (Apple's HTTP/2 API with the team's .p8 key); Expo tokens
-- from the old prototype keep going to Expo.
--
-- Settings (set once per project, e.g. in the SQL editor):
--   alter database postgres set jur.apns_function_url = 'https://<ref>.functions.supabase.co/apns';
--   alter database postgres set jur.apns_secret = '<same value as the function's PUSH_SECRET>';

alter table public.push_tokens drop constraint if exists push_tokens_token_check;
alter table public.push_tokens add constraint push_tokens_token_check
  check (token ~ '^Expo(nent)?PushToken\[.+\]$' or token ~ '^[0-9a-f]{64,200}$');

create or replace function public.queue_push(p_profile uuid, p_kind text, p_name text, p_data jsonb,
                                             p_extra text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_locale text;
  v_title text;
  v_body text;
  v_expo text[];
  v_apns text[];
  v_messages jsonb;
  v_headers jsonb := '{"Content-Type": "application/json", "Accept": "application/json"}';
  v_req bigint;
  v_access text := current_setting('qadam.expo_access_token', true);
  v_apns_url text := current_setting('jur.apns_function_url', true);
  v_apns_secret text := current_setting('jur.apns_secret', true);
  v_has_net boolean := exists (select 1 from pg_extension where extname = 'pg_net');
begin
  select locale into v_locale from profiles where id = p_profile and not banned;
  if not found then return; end if;
  select t.title, t.body into v_title, v_body from push_text(v_locale, p_kind, p_name, p_extra) t;
  select coalesce(array_agg(token) filter (where token like 'Expo%'), '{}'),
         coalesce(array_agg(token) filter (where token not like 'Expo%'), '{}')
    into v_expo, v_apns
    from push_tokens where profile_id = p_profile;

  -- Old prototype builds: Expo
  if cardinality(v_expo) > 0 and v_has_net then
    select jsonb_agg(jsonb_build_object(
             'to', tok, 'title', v_title, 'body', v_body, 'data', p_data,
             'sound', case when p_kind = 'match' then 'match.wav' else 'default' end,
             'channelId', case p_kind when 'match' then 'matches' when 'message' then 'chats' else 'activity' end,
             'priority', 'high'))
      into v_messages from unnest(v_expo) tok;
    if coalesce(v_access, '') <> '' then
      v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_access);
    end if;
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      into v_req using 'https://exp.host/--/api/v2/push/send', v_messages, v_headers;
  end if;

  -- The native app: APNs through the Edge Function
  if cardinality(v_apns) > 0 and v_has_net and coalesce(v_apns_url, '') <> '' then
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      into v_req using v_apns_url,
        jsonb_build_object(
          'tokens', to_jsonb(v_apns), 'title', v_title, 'body', v_body,
          'sound', case when p_kind = 'match' then 'match.wav' else 'default' end,
          'thread', p_kind, 'data', coalesce(p_data, '{}')),
        jsonb_build_object('Content-Type', 'application/json',
                           'Authorization', 'Bearer ' || coalesce(v_apns_secret, ''));
  end if;

  insert into push_outbox (profile_id, kind, title, body, data, tokens, request_id)
  values (p_profile, p_kind, v_title, v_body, coalesce(p_data, '{}'),
          cardinality(v_expo) + cardinality(v_apns), v_req);
end $$;
revoke execute on function public.queue_push(uuid, text, text, jsonb, text) from public, anon, authenticated;

-- A token that Apple says is gone (app deleted) is removed by the function through this.
create or replace function public.drop_push_token(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from push_tokens where token = p_token
$$;
revoke all on function public.drop_push_token(text) from public, anon, authenticated;
grant execute on function public.drop_push_token(text) to service_role;

-- ===== migrations/20261021000013_jur_products.sql =====
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

-- ===== migrations/20261022000014_likes_sent.sql =====
-- How many people you've liked (likes and super likes), for the empty Matches screen:
-- "Your likes so far: 4". Only the total: it never says who passed on you.
create or replace function public.my_likes_sent() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from swipes
   where swiper_id = auth.uid() and kind in ('like', 'super')
$$;

revoke all on function public.my_likes_sent() from public, anon;
grant execute on function public.my_likes_sent() to authenticated;

-- ===== migrations/20261022000015_pause_invites.sql =====
-- Pause and invites for the Me tab.

-- ---------------------------------------------------------------------
-- 1. Pause my profile. `hidden` used to mean both "I paused" and "auto-hidden
--    by reports", so a pause switch could have undone moderation. Now:
--      paused: the person's own choice (set_paused)
--      held:   hidden by reports until a moderator clears it
--      hidden = paused or held or banned (everything else keeps reading `hidden`)
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists paused boolean not null default false,
  add column if not exists held   boolean not null default false;

-- Nobody could pause before this, so anyone hidden today was hidden by reports or a ban.
update public.profiles set held = true where hidden and not banned and not held;

-- The app no longer writes `hidden` directly.
revoke update (hidden) on public.profiles from authenticated;

create or replace function public.set_paused(p_paused boolean) returns void
language sql security definer set search_path = public as $$
  update profiles set paused = p_paused, hidden = p_paused or held or banned
   where id = auth.uid()
$$;
revoke all on function public.set_paused(boolean) from public, anon;
grant execute on function public.set_paused(boolean) to authenticated;

create or replace function public.on_report_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(distinct reporter_id) from reports
      where reported_id = new.reported_id and status = 'open') >= cfg('reports_to_autohide') then
    update profiles set held = true, hidden = true where id = new.reported_id;
  end if;
  -- reporting also blocks, so the reporter never sees them again
  insert into blocks (blocker_id, blocked_id) values (new.reporter_id, new.reported_id)
    on conflict do nothing;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- 2. Invites: how many friends joined with your code, and how many more
--    until the next free Pro week (every cfg('referrals_for_bonus') friends).
-- ---------------------------------------------------------------------
create or replace function public.my_referrals() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_count int;
  v_every int := cfg('referrals_for_bonus');
begin
  select count(*) into v_count from profiles where referred_by = auth.uid();
  return jsonb_build_object(
    'count', v_count,
    'every', v_every,
    'toNext', v_every - (v_count % v_every),
    'bonusDays', cfg('referral_bonus_days'));
end $$;
revoke all on function public.my_referrals() from public, anon;
grant execute on function public.my_referrals() to authenticated;

-- ===== migrations/20261022000016_app_settings.sql =====
-- Server settings in a private table. Supabase no longer lets the project owner run
-- `alter database postgres set jur.… = …`, so the push settings live here instead:
--
--   insert into public.app_settings (key, value) values
--     ('jur.apns_function_url', 'https://<ref>.supabase.co/functions/v1/apns'),
--     ('jur.apns_secret', '<same value as the apns function's PUSH_SECRET>')
--   on conflict (key) do update set value = excluded.value;
--
-- Nobody can read the table through the API (RLS on, no policies, no grants); only
-- security-definer functions inside the database use it.
create table if not exists public.app_settings (
  key   text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from public, anon, authenticated;

-- A database-level setting still wins if one exists (older projects set them that way).
create or replace function public.app_setting(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(current_setting(p_key, true), ''),
                  (select value from app_settings where key = p_key))
$$;
revoke all on function public.app_setting(text) from public, anon, authenticated;

create or replace function public.queue_push(p_profile uuid, p_kind text, p_name text, p_data jsonb,
                                             p_extra text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_locale text;
  v_title text;
  v_body text;
  v_expo text[];
  v_apns text[];
  v_messages jsonb;
  v_headers jsonb := '{"Content-Type": "application/json", "Accept": "application/json"}';
  v_req bigint;
  v_access text := app_setting('qadam.expo_access_token');
  v_apns_url text := app_setting('jur.apns_function_url');
  v_apns_secret text := app_setting('jur.apns_secret');
  v_has_net boolean := exists (select 1 from pg_extension where extname = 'pg_net');
begin
  select locale into v_locale from profiles where id = p_profile and not banned;
  if not found then return; end if;
  select t.title, t.body into v_title, v_body from push_text(v_locale, p_kind, p_name, p_extra) t;
  select coalesce(array_agg(token) filter (where token like 'Expo%'), '{}'),
         coalesce(array_agg(token) filter (where token not like 'Expo%'), '{}')
    into v_expo, v_apns
    from push_tokens where profile_id = p_profile;

  -- Old prototype builds: Expo
  if cardinality(v_expo) > 0 and v_has_net then
    select jsonb_agg(jsonb_build_object(
             'to', tok, 'title', v_title, 'body', v_body, 'data', p_data,
             'sound', case when p_kind = 'match' then 'match.wav' else 'default' end,
             'channelId', case p_kind when 'match' then 'matches' when 'message' then 'chats' else 'activity' end,
             'priority', 'high'))
      into v_messages from unnest(v_expo) tok;
    if coalesce(v_access, '') <> '' then
      v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_access);
    end if;
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      into v_req using 'https://exp.host/--/api/v2/push/send', v_messages, v_headers;
  end if;

  -- The native app: APNs through the Edge Function
  if cardinality(v_apns) > 0 and v_has_net and coalesce(v_apns_url, '') <> '' then
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      into v_req using v_apns_url,
        jsonb_build_object(
          'tokens', to_jsonb(v_apns), 'title', v_title, 'body', v_body,
          'sound', case when p_kind = 'match' then 'match.wav' else 'default' end,
          'thread', p_kind, 'data', coalesce(p_data, '{}')),
        jsonb_build_object('Content-Type', 'application/json',
                           'Authorization', 'Bearer ' || coalesce(v_apns_secret, ''));
  end if;

  insert into push_outbox (profile_id, kind, title, body, data, tokens, request_id)
  values (p_profile, p_kind, v_title, v_body, coalesce(p_data, '{}'),
          cardinality(v_expo) + cardinality(v_apns), v_req);
end $$;
revoke execute on function public.queue_push(uuid, text, text, jsonb, text) from public, anon, authenticated;

-- ===== migrations/20261022000017_push_copy.sql =====
-- Push wording, aligned with the app (copy audit, 22 Oct 2026):
--   match: "Same pace!" instead of "Hearts in sync!", and the body suggests meeting;
--   date accepted: "Jür! It's on." (no "Согласен(на)"); picks: "Today's picks are in";
--   Kazakh speaks to the person as сіз, like the app.
create or replace function public.push_text(p_locale text, p_kind text, p_name text, p_extra text default null)
returns table (title text, body text)
language sql immutable set search_path = public as $$
  select
    case p_kind
      when 'match' then case p_locale when 'kk' then 'Бір қарқында!' when 'en' then 'Same pace!' else 'В одном темпе!' end
      when 'message' then p_name
      when 'like' then 'JÜR'
      when 'super' then 'JÜR'
      when 'event_reminder' then coalesce(p_extra, 'JÜR')
      when 'city_open' then 'JÜR'
      when 'club_event' then coalesce(p_extra, 'JÜR')
      when 'date_answer' then p_name
      when 'picks' then 'JÜR'
      when 'buddy_match' then case p_locale when 'kk' then 'Серіктес табылды!' when 'en' then 'Training partner found!' else 'Напарник найден!' end
      when 'duo_invite' then p_name
      when 'duo_match' then case p_locale when 'kk' then 'Қос кездесу!' when 'en' then 'Double date!' else 'Двойное свидание!' end
    end,
    case p_kind
      when 'match' then case p_locale
        when 'kk' then 'Сіз бен ' || p_name || ' бір-біріңізге ұнадыңыздар. Кездесу ұсыныңыз.'
        when 'en' then 'You and ' || p_name || ' liked each other. Suggest a meetup.'
        else 'Вы с ' || p_name || ' понравились друг другу. Предложите встречу.' end
      when 'message' then case p_locale
        when 'kk' then 'Жаңа хабарлама' when 'en' then 'New message' else 'Новое сообщение' end
      when 'like' then case p_locale
        when 'kk' then 'Біреу сізді ұнатты. Кім екенін көріңіз.'
        when 'en' then 'Someone liked you. See who.'
        else 'Вы кому-то понравились. Посмотрите, кому.' end
      when 'super' then case p_locale
        when 'kk' then 'Біреу сізге суперлайк басты!'
        when 'en' then 'Someone super liked you!'
        else 'Вам поставили суперлайк!' end
      when 'event_reminder' then case p_locale
        when 'kk' then '2 сағаттан кейін басталады. Кездескенше!'
        when 'en' then 'Starts in 2 hours. See you there!'
        else 'Начало через 2 часа. До встречи!' end
      when 'city_open' then case p_locale
        when 'kk' then city_label(p_name, p_locale) || ' ашылды! Анкеталар сізді күтіп тұр.'
        when 'en' then city_label(p_name, p_locale) || ' is open! Start discovering.'
        else city_label(p_name, p_locale) || ' открыт! Анкеты уже ждут.' end
      when 'club_event' then case p_locale
        when 'kk' then p_name || ' клубында жаңа іс-шара. Орын алыңыз.'
        when 'en' then 'New event in ' || p_name || '. Save your spot.'
        else 'Новое событие в клубе ' || p_name || '. Займите место.' end
      when 'date_answer' then case
        when p_extra = 'accepted' then case p_locale when 'kk' then 'Жүр! Кездесу күшінде.' when 'en' then 'Jür! It''s on.' else 'Жүр! Встреча в силе.' end
        else case p_locale when 'kk' then 'Бұл уақыт ыңғайсыз. Басқасын ұсыныңыз.' when 'en' then 'That time doesn''t work. Suggest another?' else 'Это время не подходит. Предложите другое?' end end
      when 'picks' then case p_locale
        when 'kk' then 'Күн таңдауы дайын: сізге 5 адам.' when 'en' then 'Today''s picks are in: 5 people for you.' else 'Выбор дня готов: 5 человек для вас.' end
      when 'buddy_match' then case p_locale
        when 'kk' then p_name || ' бірге жаттығуға дайын.' when 'en' then p_name || ' wants to train together.' else p_name || ' хочет тренироваться вместе.' end
      when 'duo_invite' then case p_locale
        when 'kk' then 'Қос кездесуге шақырды.' when 'en' then 'Invited you to team up for double dates.' else 'Зовёт вас в пару для двойных свиданий.' end
      when 'duo_match' then case p_locale
        when 'kk' then 'Екі жұп бір-бірін ұнатты. Төртеуіңіз чатта.' when 'en' then 'Both pairs liked each other. The four of you have a chat.' else 'Обе пары понравились друг другу. У вас общий чат.' end
    end
$$;

-- ===== migrations/20261023000018_discover_filters.sql =====
-- Discover filters: the sheet behind the button at the top right of Discover.
-- Who to show and the age range already live on the profile (and stay two-way: you only
-- see people whose own preferences include you). This adds:
--   * sports       — only people who do one of these (empty = any)
--   * verified     — only people whose selfie was checked
--   * attended     — only people who have checked in at an event at least once
--   * active days  — only people active in the last N days (Pro; 1 or 7)
-- One check, discover_filters_ok, is shared by the deck and by the live count on the
-- sheet's button, so the number shown is the number you get.

alter table public.profiles
  add column if not exists filter_sports text[] not null default '{}',
  add column if not exists filter_verified boolean not null default false,
  add column if not exists filter_attended boolean not null default false,
  add column if not exists filter_active_days int check (filter_active_days in (1, 7));

create or replace function public.discover_filters_ok(me profiles, p profiles) returns boolean
language sql stable set search_path = public as $$
  select (cardinality(me.filter_sports) = 0
            or exists (select 1 from profile_sports ps
                       where ps.profile_id = p.id and ps.sport_code = any (me.filter_sports)))
     and (not me.filter_verified or p.verification_status = 'approved')
     and (not me.filter_attended
            or exists (select 1 from event_attendees a where a.profile_id = p.id and a.checked_in_at is not null))
     and (me.filter_active_days is null or not is_pro(me.id)
            or p.last_active_at > now() - make_interval(days => me.filter_active_days))
$$;

-- Everyone Discover could show me right now (before ordering and paging).
create or replace function public.discover_pool(me profiles, p_mode text default null) returns setof profiles
language sql stable set search_path = public as $$
  select p.* from profiles p
  where p.id <> me.id
    and not p.hidden and not p.banned
    and effective_city(p) = effective_city(me)
    and coalesce(array_length(p.photos, 1), 0) >= 1
    and case coalesce(p_mode, '')
          when 'dating' then dating_ok(me, p)
          when 'buddy' then buddy_ok(me, p)
          else dating_ok(me, p) or buddy_ok(me, p) end
    and discover_filters_ok(me, p)
    and not exists (select 1 from swipes w where w.swiper_id = me.id and w.target_id = p.id)
    and not blocked_between(me.id, p.id)
    and not hidden_between(me.id, p.id)
$$;

create or replace function public.discover(p_limit int default 20, p_mode text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_season text := current_season();
  v_result jsonb;
begin
  select * into me from profiles where id = auth.uid();
  if not found then raise exception 'no_profile'; end if;

  select coalesce(jsonb_agg(profile_card(c.id)
                              || jsonb_build_object('shared_sports', c.shared, 'super_liked_me', c.super_me,
                                                    'boosted', c.boosted, 'match_mode', c.mm)
                            order by c.boosted desc, c.super_me desc, c.tier asc, c.newcomer desc,
                                     c.shared_season desc, c.shared desc, c.last_active_at desc), '[]'::jsonb)
    into v_result
  from (
    select q.* from (
      select p.id, p.last_active_at,
             coalesce(p.boosted_until > now(), false) as boosted,
             exists (select 1 from swipes w where w.swiper_id = p.id and w.target_id = me.id and w.kind = 'super') as super_me,
             (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
               where a.profile_id = p.id and b.profile_id = me.id)::int as shared,
             (select count(*) from profile_sports a join profile_sports b on a.sport_code = b.sport_code
                                                   join sports s on s.code = a.sport_code
               where a.profile_id = p.id and b.profile_id = me.id and s.season in (v_season, 'all'))::int as shared_season,
             case when dating_ok(me, p) then 'dating' else 'buddy' end as mm,
             exposure_tier(p.id) as tier,
             is_newcomer(p.id) as newcomer
      from discover_pool(me, p_mode) p
    ) q
    order by q.boosted desc, q.super_me desc, q.tier asc, q.newcomer desc,
             q.shared_season desc, q.shared desc, q.last_active_at desc
    limit least(greatest(p_limit, 1), 50)
  ) c;

  return v_result;
end $$;

-- The sheet's live count: "Показать 48 анкет". Optional arguments preview a change
-- before it's saved; anything left null uses the saved value. Capped at 999.
create or replace function public.discover_count(
  p_interested text default null, p_age_min int default null, p_age_max int default null,
  p_sports text[] default null, p_verified boolean default null, p_attended boolean default null,
  p_active_days int default null, p_clear_active boolean default false
) returns int
language plpgsql stable security definer set search_path = public as $$
declare
  me profiles%rowtype;
begin
  select * into me from profiles where id = auth.uid();
  if not found then return 0; end if;
  me.interested_in     := coalesce(p_interested, me.interested_in);
  me.age_min           := greatest(18, coalesce(p_age_min, me.age_min));
  me.age_max           := least(99, coalesce(p_age_max, me.age_max));
  me.filter_sports     := coalesce(p_sports, me.filter_sports);
  me.filter_verified   := coalesce(p_verified, me.filter_verified);
  me.filter_attended   := coalesce(p_attended, me.filter_attended);
  me.filter_active_days := case when p_clear_active then null else coalesce(p_active_days, me.filter_active_days) end;
  return (select least(count(*), 999)::int from (select 1 from discover_pool(me) limit 1000) x);
end $$;

-- Saves the sheet. "Active recently" is Pro: for everyone else it's stored as off.
create or replace function public.set_discover_filters(
  p_interested text, p_age_min int, p_age_max int, p_sports text[],
  p_verified boolean, p_attended boolean, p_active_days int
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_min int := greatest(18, least(coalesce(p_age_min, 18), 99));
  v_max int := greatest(18, least(coalesce(p_age_max, 99), 99));
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'auth'); end if;
  if p_interested not in ('women', 'men', 'everyone') then
    return jsonb_build_object('ok', false, 'error', 'bad_interested');
  end if;
  if v_min > v_max then v_min := v_max; end if;
  update profiles set
    interested_in = p_interested,
    age_min = v_min, age_max = v_max,
    filter_sports = coalesce((select array_agg(distinct s) from unnest(p_sports) s
                              where s in (select code from sports)), '{}'),
    filter_verified = coalesce(p_verified, false),
    filter_attended = coalesce(p_attended, false),
    filter_active_days = case when p_active_days in (1, 7) and is_pro(auth.uid()) then p_active_days end
  where id = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.discover_filters_ok(profiles, profiles) from public, anon, authenticated;
revoke execute on function public.discover_pool(profiles, text) from public, anon, authenticated;
grant execute on function public.discover_count(text, int, int, text[], boolean, boolean, int, boolean) to authenticated;
grant execute on function public.set_discover_filters(text, int, int, text[], boolean, boolean, int) to authenticated;

-- ===== migrations/20261023000019_paywall_proof.sql =====
-- The paywall's one line of social proof: "В Алматы с Pro уже 1 240 человек".
-- Only real numbers, and only once they mean something: below 100 it returns null and
-- the paywall shows nothing. Rounded down to tens so it doesn't tick in front of people.

create or replace function public.pro_members_in_city() returns int
language plpgsql stable security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_n int;
begin
  select * into me from profiles where id = auth.uid();
  if not found then return null; end if;
  select count(*) into v_n from profiles p
   where effective_city(p) = effective_city(me) and not p.banned and is_pro(p.id);
  if v_n < 100 then return null; end if;
  return (v_n / 10) * 10;
end $$;

grant execute on function public.pro_members_in_city() to authenticated;

-- ===== migrations/20261023000020_audit_fixes.sql =====
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

-- ===== migrations/20261023000021_safety_tools.sql =====
-- Safety screen tools: the people you blocked (and unblocking them), and your upcoming
-- accepted dates, so the plan can be sent to a friend in one tap.

-- Who you blocked: name and first photo only, newest first.
-- (Profiles aren't readable directly, and get_profile hides blocked people, so this is
-- the one place they appear.)
create or replace function public.my_blocked() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'name', p.name, 'photo', p.photos[1], 'blocked_at', b.created_at)
         order by b.created_at desc), '[]'::jsonb)
  from blocks b join profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
$$;
revoke all on function public.my_blocked() from public, anon;
grant execute on function public.my_blocked() to authenticated;

-- Unblock. An unmatch also blocks; unblocking doesn't bring the match back, it only lets
-- you see each other again in Discover and at events.
create or replace function public.unblock(p_profile uuid) returns void
language sql security definer set search_path = public as $$
  delete from blocks where blocker_id = auth.uid() and blocked_id = p_profile
$$;
revoke all on function public.unblock(uuid) from public, anon;
grant execute on function public.unblock(uuid) to authenticated;

-- Accepted dates still ahead, in active matches: who, what, when, where.
create or replace function public.my_upcoming_dates() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'message_id', m.id, 'match_id', m.match_id,
           'name', o.name, 'sport', m.payload->>'sport',
           'when', m.payload->>'when', 'place', m.payload->>'place')
         order by (m.payload->>'when')::timestamptz), '[]'::jsonb)
  from messages m
  join matches x on x.id = m.match_id
  join profiles o on o.id = case when x.user_a = auth.uid() then x.user_b else x.user_a end
  where m.kind = 'date' and m.payload->>'status' = 'accepted'
    and auth.uid() in (x.user_a, x.user_b) and x.unmatched_at is null
    and (m.payload->>'when')::timestamptz > now() - interval '3 hours'
$$;
revoke all on function public.my_upcoming_dates() from public, anon;
grant execute on function public.my_upcoming_dates() to authenticated;

-- ===== migrations/20261024000022_honest_pushes.sql =====
-- No promises the app can't keep (24 Oct 2026).
--
-- 1. The 19:00 "Today's picks: 5 people for you" push went to everyone active in the
--    last two weeks, even when nobody was there to pick. Now it goes only to people who
--    really have someone new today, says how many, and skips anyone who has already
--    opened today's picks or paused their profile.
-- 2. The demo host and events from seed.sql (local testing only) are taken out of sight
--    if they ever reached this database: the account is hidden and banned, its events
--    cancelled. Nothing is deleted; on a database without them this does nothing.

-- How many people today's picks would show `me` (0 to 5): the same rules as daily_picks().
create or replace function public.pick_candidates(me profiles) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from (
    select 1 from profiles p
     where p.id <> me.id and not p.hidden and not p.banned
       and effective_city(p) = effective_city(me)
       and coalesce(array_length(p.photos, 1), 0) >= 1
       and (dating_ok(me, p) or buddy_ok(me, p))
       and not exists (select 1 from swipes w where w.swiper_id = me.id and w.target_id = p.id)
       and not blocked_between(me.id, p.id)
       and not hidden_between(me.id, p.id)
     limit 5) s
$$;
revoke all on function public.pick_candidates(profiles) from public, anon, authenticated;

-- Evening nudge at 19:00 Almaty, only when there's really someone to see.
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

create or replace function public.push_text(p_locale text, p_kind text, p_name text, p_extra text default null)
returns table (title text, body text)
language sql immutable set search_path = public as $$
  select
    case p_kind
      when 'match' then case p_locale when 'kk' then 'Бір қарқында!' when 'en' then 'Same pace!' else 'В одном темпе!' end
      when 'message' then p_name
      when 'like' then 'JÜR'
      when 'super' then 'JÜR'
      when 'event_reminder' then coalesce(p_extra, 'JÜR')
      when 'city_open' then 'JÜR'
      when 'club_event' then coalesce(p_extra, 'JÜR')
      when 'date_answer' then p_name
      when 'picks' then 'JÜR'
      when 'buddy_match' then case p_locale when 'kk' then 'Серіктес табылды!' when 'en' then 'Training partner found!' else 'Напарник найден!' end
      when 'duo_invite' then p_name
      when 'duo_match' then case p_locale when 'kk' then 'Қос кездесу!' when 'en' then 'Double date!' else 'Двойное свидание!' end
    end,
    case p_kind
      when 'match' then case p_locale
        when 'kk' then 'Сіз бен ' || p_name || ' бір-біріңізге ұнадыңыздар. Кездесу ұсыныңыз.'
        when 'en' then 'You and ' || p_name || ' liked each other. Suggest a meetup.'
        else 'Вы с ' || p_name || ' понравились друг другу. Предложите встречу.' end
      when 'message' then case p_locale
        when 'kk' then 'Жаңа хабарлама' when 'en' then 'New message' else 'Новое сообщение' end
      when 'like' then case p_locale
        when 'kk' then 'Біреу сізді ұнатты. Кім екенін көріңіз.'
        when 'en' then 'Someone liked you. See who.'
        else 'Вы кому-то понравились. Посмотрите, кому.' end
      when 'super' then case p_locale
        when 'kk' then 'Біреу сізге суперлайк басты!'
        when 'en' then 'Someone super liked you!'
        else 'Вам поставили суперлайк!' end
      when 'event_reminder' then case p_locale
        when 'kk' then '2 сағаттан кейін басталады. Кездескенше!'
        when 'en' then 'Starts in 2 hours. See you there!'
        else 'Начало через 2 часа. До встречи!' end
      when 'city_open' then case p_locale
        when 'kk' then city_label(p_name, p_locale) || ' ашылды! Анкеталар сізді күтіп тұр.'
        when 'en' then city_label(p_name, p_locale) || ' is open! Start discovering.'
        else city_label(p_name, p_locale) || ' открыт! Анкеты уже ждут.' end
      when 'club_event' then case p_locale
        when 'kk' then p_name || ' клубында жаңа іс-шара. Орын алыңыз.'
        when 'en' then 'New event in ' || p_name || '. Save your spot.'
        else 'Новое событие в клубе ' || p_name || '. Займите место.' end
      when 'date_answer' then case
        when p_extra = 'accepted' then case p_locale when 'kk' then 'Жүр! Кездесу күшінде.' when 'en' then 'Jür! It''s on.' else 'Жүр! Встреча в силе.' end
        else case p_locale when 'kk' then 'Бұл уақыт ыңғайсыз. Басқасын ұсыныңыз.' when 'en' then 'That time doesn''t work. Suggest another?' else 'Это время не подходит. Предложите другое?' end end
      -- p_extra is how many people are really in today's picks (1 to 5).
      when 'picks' then case p_locale
        when 'kk' then 'Күн таңдауы дайын: сізге ' || coalesce(p_extra, '1') || ' адам.'
        when 'en' then 'Today''s picks are in: ' || coalesce(p_extra, '1')
                       || case when coalesce(p_extra, '1') = '1' then ' person' else ' people' end || ' for you.'
        else 'Выбор дня готов: ' || coalesce(p_extra, '1')
             || case when coalesce(p_extra, '1') in ('2', '3', '4') then ' человека' else ' человек' end || ' для вас.' end
      when 'buddy_match' then case p_locale
        when 'kk' then p_name || ' бірге жаттығуға дайын.' when 'en' then p_name || ' wants to train together.' else p_name || ' хочет тренироваться вместе.' end
      when 'duo_invite' then case p_locale
        when 'kk' then 'Қос кездесуге шақырды.' when 'en' then 'Invited you to team up for double dates.' else 'Зовёт вас в пару для двойных свиданий.' end
      when 'duo_match' then case p_locale
        when 'kk' then 'Екі жұп бір-бірін ұнатты. Төртеуіңіз чатта.' when 'en' then 'Both pairs liked each other. The four of you have a chat.' else 'Обе пары понравились друг другу. У вас общий чат.' end
    end
$$;

-- Demo data from seed.sql, if it was ever loaded here.
update public.profiles set hidden = true, banned = true
 where id = '00000000-0000-4000-a000-000000000001';
update public.events set cancelled = true
 where host_id = '00000000-0000-4000-a000-000000000001' and not cancelled;
