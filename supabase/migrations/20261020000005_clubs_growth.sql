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
