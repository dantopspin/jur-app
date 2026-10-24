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
