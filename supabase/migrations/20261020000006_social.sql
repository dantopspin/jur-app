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
