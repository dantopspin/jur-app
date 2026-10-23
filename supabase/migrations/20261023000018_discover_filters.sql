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
