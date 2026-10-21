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
