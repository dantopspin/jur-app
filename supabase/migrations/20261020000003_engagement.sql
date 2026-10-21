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
