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
