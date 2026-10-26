-- Scale and abuse limits (load-tested on 1 000 / 5 000 / 20 000 members).
--
--  1. Discover: the same people in the same order, much faster.
--     Every helper Discover used carried `set search_path`, and Postgres never inlines a
--     function with a SET clause, so each candidate cost several separate function calls.
--     The pure helpers lose the clause (they only ever run inside functions that set it),
--     block and contact-hide checks become plain anti-joins, the pool reads one city
--     through the index instead of every profile, and the ranking (likes waiting, shared
--     sports, newcomers) is counted once for the whole pool instead of once per person.
--     Ties now break on id, so the order is stable between two loads.
--  2. Rate limits: messages, reactions, reports, blocks, swipes and Discover itself.
--     Generous for people, a wall for scripts.
--  3. Referral codes can't collide: six characters gave a failed sign-up about once in
--     every few hundred at 50 000 members.

-- ---------------------------------------------------------------
-- 1. Discover
-- ---------------------------------------------------------------
alter function public.effective_city(profiles) reset search_path;
alter function public.wants(profiles, profiles, text) reset search_path;
alter function public.dating_ok(profiles, profiles) reset search_path;
alter function public.buddy_ok(profiles, profiles) reset search_path;
alter function public.discover_filters_ok(profiles, profiles) reset search_path;

-- Travellers are found by the city they're visiting.
create index if not exists profiles_travel_city_idx on public.profiles (travel_city)
  where travel_city is not null and not hidden and not banned;

-- Same rules as before. Only callable from the definer functions below (Discover,
-- the live count). It keeps its own SET clause on purpose: that stops Postgres from
-- inlining the pool itself (the helpers inside it still inline), so callers plan against
-- `rows 1000` instead of a guess of one row — which made the ranking below re-count
-- shared sports once per candidate (8 000 × 2 761 rows at 20 000 members).
create or replace function public.discover_pool(me profiles, p_mode text default null) returns setof profiles
language sql stable set search_path = public rows 1000 as $$
  select p.* from public.profiles p
  where (p.city = public.effective_city(me) or p.travel_city = public.effective_city(me))
    and public.effective_city(p) = public.effective_city(me)
    and p.id <> me.id
    and not p.hidden and not p.banned
    and coalesce(array_length(p.photos, 1), 0) >= 1
    and case coalesce(p_mode, '')
          when 'dating' then public.dating_ok(me, p)
          when 'buddy' then public.buddy_ok(me, p)
          else public.dating_ok(me, p) or public.buddy_ok(me, p) end
    and public.discover_filters_ok(me, p)
    and not exists (select 1 from public.swipes w where w.swiper_id = me.id and w.target_id = p.id)
    and not exists (select 1 from public.blocks k
                     where (k.blocker_id = me.id and k.blocked_id = p.id) or (k.blocker_id = p.id and k.blocked_id = me.id))
    and not exists (select 1 from public.contact_hides h join public.identity_hashes i on i.hash = h.hash
                     where (h.owner_id = me.id and i.profile_id = p.id) or (h.owner_id = p.id and i.profile_id = me.id))
$$;
revoke execute on function public.discover_pool(profiles, text) from public, anon, authenticated;

-- The deck. Ordering unchanged: boosted, super-liked you, fewer unanswered likes first
-- (fair exposure), newcomers, shared in-season sports, shared sports, recently active.
create or replace function public.discover(p_limit int default 20, p_mode text default null) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_season text := current_season();
  v_result jsonb;
begin
  select * into me from profiles where id = auth.uid();
  if not found then raise exception 'no_profile'; end if;
  if not rate_ok('discover:' || me.id, 40, interval '1 minute') then
    raise exception 'rate_limited' using errcode = 'P0001', hint = 'discover';
  end if;

  with pool as (
    select p.* from discover_pool(me, p_mode) p
  ),
  mine as (
    select ps.sport_code, s.season from profile_sports ps join sports s on s.code = ps.sport_code
     where ps.profile_id = me.id
  ),
  shared as (
    select ps.profile_id as id, count(*) as n,
           count(*) filter (where m.season in (v_season, 'all')) as n_season
      from profile_sports ps
      join pool on pool.id = ps.profile_id
      join mine m on m.sport_code = ps.sport_code
     group by ps.profile_id
  ),
  ranked as (
    select pool.id, pool.last_active_at,
           coalesce(pool.boosted_until > now(), false) as boosted,
           exists (select 1 from swipes w where w.swiper_id = pool.id and w.target_id = me.id and w.kind = 'super') as super_me,
           coalesce(sh.n, 0)::int as shared,
           coalesce(sh.n_season, 0)::int as shared_season,
           case when dating_ok(me, pool) then 'dating' else 'buddy' end as mm,
           case when pe.n >= cfg('exposure_hard_cap') then 2
                when pe.n >= cfg('exposure_soft_cap') then 1
                else 0 end as tier,
           (pool.created_at > now() - make_interval(days => cfg('newcomer_days'))
              and rc.n < cfg('newcomer_max_likes')) as newcomer
      from pool
      -- Likes waiting for an answer (last N days, from people who aren't banned) and all
      -- likes ever received (the newcomer head start ends after a few): one index lookup
      -- per candidate, so the cost follows the pool, never the size of the swipes table.
      cross join lateral (
        select count(*) as n
          from swipes w join profiles s on s.id = w.swiper_id and not s.banned
         where w.target_id = pool.id and w.kind in ('like', 'super')
           and w.created_at > now() - make_interval(days => cfg('exposure_window_days'))
           and not exists (select 1 from swipes r where r.swiper_id = pool.id and r.target_id = w.swiper_id)
      ) pe
      cross join lateral (
        select count(*) as n from swipes w where w.target_id = pool.id and w.kind in ('like', 'super')
      ) rc
      left join shared sh on sh.id = pool.id
     order by boosted desc, super_me desc, tier asc, newcomer desc,
              shared_season desc, shared desc, pool.last_active_at desc, pool.id
     limit least(greatest(p_limit, 1), 50)
  )
  select coalesce(jsonb_agg(profile_card(r.id)
                              || jsonb_build_object('shared_sports', r.shared, 'super_liked_me', r.super_me,
                                                    'boosted', r.boosted, 'match_mode', r.mm)
                            order by r.boosted desc, r.super_me desc, r.tier asc, r.newcomer desc,
                                     r.shared_season desc, r.shared desc, r.last_active_at desc, r.id), '[]'::jsonb)
    into v_result
    from ranked r;

  return v_result;
end $$;
grant execute on function public.discover(int, text) to authenticated;

-- ---------------------------------------------------------------
-- 2. Rate limits
-- ---------------------------------------------------------------
-- Fixed windows per key. Unlogged: counters needn't survive a crash or sit in backups.
create unlogged table if not exists public.rate_counters (
  key          text not null,
  window_start timestamptz not null,
  n            int not null default 0,
  primary key (key, window_start)
);
alter table public.rate_counters enable row level security;
revoke all on public.rate_counters from public, anon, authenticated;

/** Counts one use of `p_key`; false once more than `p_max` in the current window. */
create or replace function public.rate_ok(p_key text, p_max int, p_window interval) returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare v_n int;
begin
  insert into rate_counters (key, window_start, n)
  values (p_key, date_bin(p_window, now(), timestamptz '2000-01-01'), 1)
  on conflict (key, window_start) do update set n = rate_counters.n + 1
  returning n into v_n;
  return v_n <= p_max;
end $$;
revoke execute on function public.rate_ok(text, int, interval) from public, anon, authenticated;

/** Row trigger: TG_ARGV = (name, per minute, per day). Skips server-side inserts (no
    signed-in user, or the notes swipe() turns into first messages). */
create or replace function public.rate_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null or current_setting('qadam.mute_message_push', true) = 'on' then return new; end if;
  if not rate_ok(TG_ARGV[0] || ':m:' || me, TG_ARGV[1]::int, interval '1 minute')
     or not rate_ok(TG_ARGV[0] || ':d:' || me, TG_ARGV[2]::int, interval '1 day') then
    raise exception 'rate_limited' using errcode = 'P0001', hint = TG_ARGV[0];
  end if;
  return new;
end $$;
revoke execute on function public.rate_guard() from public, anon, authenticated;

-- A fast typist sends ~10 a minute; nobody honest sends 30, or 1 500 in a day.
create trigger messages_rate before insert on public.messages
  for each row execute function public.rate_guard('msg', '30', '1500');
create trigger club_messages_rate before insert on public.club_messages
  for each row execute function public.rate_guard('msg', '30', '1500');
create trigger duo_messages_rate before insert on public.duo_messages
  for each row execute function public.rate_guard('msg', '30', '1500');
create trigger reactions_rate before insert on public.message_reactions
  for each row execute function public.rate_guard('react', '60', '2000');
create trigger reports_rate before insert on public.reports
  for each row execute function public.rate_guard('report', '5', '20');
create trigger blocks_rate before insert on public.blocks
  for each row execute function public.rate_guard('block', '10', '100');
-- Likes already have a daily quota; this stops a script from passing on everyone.
create trigger swipes_rate before insert on public.swipes
  for each row execute function public.rate_guard('swipe', '90', '3000');

-- The live count on the filter sheet asks again after every change (300 ms debounce).
create or replace function public.discover_count(
  p_interested text default null, p_age_min int default null, p_age_max int default null,
  p_sports text[] default null, p_verified boolean default null, p_attended boolean default null,
  p_active_days int default null, p_clear_active boolean default false
) returns int
language plpgsql volatile security definer set search_path = public as $$
declare
  me profiles%rowtype;
begin
  select * into me from profiles where id = auth.uid();
  if not found then return 0; end if;
  if not rate_ok('count:' || me.id, 90, interval '1 minute') then
    raise exception 'rate_limited' using errcode = 'P0001', hint = 'count';
  end if;
  me.interested_in      := coalesce(p_interested, me.interested_in);
  me.age_min            := greatest(18, coalesce(p_age_min, me.age_min));
  me.age_max            := least(99, coalesce(p_age_max, me.age_max));
  me.filter_sports      := coalesce(p_sports, me.filter_sports);
  me.filter_verified    := coalesce(p_verified, me.filter_verified);
  me.filter_attended    := coalesce(p_attended, me.filter_attended);
  me.filter_active_days := case when p_clear_active then null else coalesce(p_active_days, me.filter_active_days) end;
  return (select least(count(*), 999)::int from (select 1 from discover_pool(me) limit 1000) x);
end $$;
grant execute on function public.discover_count(text, int, int, text[], boolean, boolean, int, boolean) to authenticated;

create or replace function public.prune_rate_counters() returns int
language sql security definer set search_path = public as $$
  with d as (delete from rate_counters where window_start < now() - interval '2 days' returning 1)
  select count(*)::int from d
$$;
revoke execute on function public.prune_rate_counters() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('jur-prune-rate-counters', '17 * * * *', 'select public.prune_rate_counters()');
  end if;
end $$;

-- ---------------------------------------------------------------
-- 3. Referral codes never collide
-- ---------------------------------------------------------------
-- Still six characters (the invite screen and share card are sized for six), now
-- re-drawn until unused, from an alphabet without 0/O and 1/I so codes read aloud well.
-- Security definer: it has to see everyone's codes, which a member's own access hides.
create or replace function public.new_referral_code() returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  for attempt in 1..20 loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '') into v_code
      from generate_series(1, 6);
    exit when not exists (select 1 from profiles where referral_code = v_code);
  end loop;
  return v_code;
end $$;

create or replace function public.ensure_referral_code() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.referral_code is null or exists (select 1 from profiles where referral_code = new.referral_code and id <> new.id) then
    new.referral_code := new_referral_code();
  end if;
  return new;
end $$;
revoke execute on function public.ensure_referral_code() from public, anon, authenticated;

alter table public.profiles alter column referral_code set default public.new_referral_code();
create trigger profiles_referral_code before insert on public.profiles
  for each row execute function public.ensure_referral_code();
