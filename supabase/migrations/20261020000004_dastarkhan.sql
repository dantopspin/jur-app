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
