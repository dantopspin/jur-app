-- Pause and invites for the Me tab.

-- ---------------------------------------------------------------------
-- 1. Pause my profile. `hidden` used to mean both "I paused" and "auto-hidden
--    by reports", so a pause switch could have undone moderation. Now:
--      paused: the person's own choice (set_paused)
--      held:   hidden by reports until a moderator clears it
--      hidden = paused or held or banned (everything else keeps reading `hidden`)
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists paused boolean not null default false,
  add column if not exists held   boolean not null default false;

-- Nobody could pause before this, so anyone hidden today was hidden by reports or a ban.
update public.profiles set held = true where hidden and not banned and not held;

-- The app no longer writes `hidden` directly.
revoke update (hidden) on public.profiles from authenticated;

create or replace function public.set_paused(p_paused boolean) returns void
language sql security definer set search_path = public as $$
  update profiles set paused = p_paused, hidden = p_paused or held or banned
   where id = auth.uid()
$$;
revoke all on function public.set_paused(boolean) from public, anon;
grant execute on function public.set_paused(boolean) to authenticated;

create or replace function public.on_report_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(distinct reporter_id) from reports
      where reported_id = new.reported_id and status = 'open') >= cfg('reports_to_autohide') then
    update profiles set held = true, hidden = true where id = new.reported_id;
  end if;
  -- reporting also blocks, so the reporter never sees them again
  insert into blocks (blocker_id, blocked_id) values (new.reporter_id, new.reported_id)
    on conflict do nothing;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- 2. Invites: how many friends joined with your code, and how many more
--    until the next free Pro week (every cfg('referrals_for_bonus') friends).
-- ---------------------------------------------------------------------
create or replace function public.my_referrals() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_count int;
  v_every int := cfg('referrals_for_bonus');
begin
  select count(*) into v_count from profiles where referred_by = auth.uid();
  return jsonb_build_object(
    'count', v_count,
    'every', v_every,
    'toNext', v_every - (v_count % v_every),
    'bonusDays', cfg('referral_bonus_days'));
end $$;
revoke all on function public.my_referrals() from public, anon;
grant execute on function public.my_referrals() to authenticated;
