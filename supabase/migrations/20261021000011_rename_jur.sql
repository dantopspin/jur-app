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
