-- Undoes 20261026000023_scale_and_limits.sql: Discover goes back to the previous (slower,
-- same results) version, rate limits come off, referral codes go back to the old default.
-- Run by hand (psql or the SQL editor) only if 023 causes trouble; then also remove
-- the 023 row from supabase_migrations.schema_migrations so a later `db push` re-applies
-- a fixed version. Tested: apply all migrations, run 024's rollback then this one, and
-- the test suite before 023 passes.
begin;

drop trigger if exists messages_rate on public.messages;
drop trigger if exists club_messages_rate on public.club_messages;
drop trigger if exists duo_messages_rate on public.duo_messages;
drop trigger if exists reactions_rate on public.message_reactions;
drop trigger if exists reports_rate on public.reports;
drop trigger if exists blocks_rate on public.blocks;
drop trigger if exists swipes_rate on public.swipes;
drop trigger if exists profiles_referral_code on public.profiles;
alter table public.profiles alter column referral_code set default upper(substr(md5(gen_random_uuid()::text), 1, 6));

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('jur-prune-rate-counters');
  end if;
exception when others then null;
end $$;

alter function public.effective_city(profiles) set search_path = public;
alter function public.wants(profiles, profiles, text) set search_path = public;
alter function public.dating_ok(profiles, profiles) set search_path = public;
alter function public.buddy_ok(profiles, profiles) set search_path = public;
alter function public.discover_filters_ok(profiles, profiles) set search_path = public;

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
revoke execute on function public.discover_pool(profiles, text) from public, anon, authenticated;
grant execute on function public.discover_count(text, int, int, text[], boolean, boolean, int, boolean) to authenticated;

drop function if exists public.prune_rate_counters();
drop function if exists public.rate_guard();
drop function if exists public.ensure_referral_code();
drop function if exists public.rate_ok(text, int, interval);
drop function if exists public.new_referral_code();
drop table if exists public.rate_counters;
drop index if exists public.profiles_travel_city_idx;

commit;
