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
