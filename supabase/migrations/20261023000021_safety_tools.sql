-- Safety screen tools: the people you blocked (and unblocking them), and your upcoming
-- accepted dates, so the plan can be sent to a friend in one tap.

-- Who you blocked: name and first photo only, newest first.
-- (Profiles aren't readable directly, and get_profile hides blocked people, so this is
-- the one place they appear.)
create or replace function public.my_blocked() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'name', p.name, 'photo', p.photos[1], 'blocked_at', b.created_at)
         order by b.created_at desc), '[]'::jsonb)
  from blocks b join profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
$$;
revoke all on function public.my_blocked() from public, anon;
grant execute on function public.my_blocked() to authenticated;

-- Unblock. An unmatch also blocks; unblocking doesn't bring the match back, it only lets
-- you see each other again in Discover and at events.
create or replace function public.unblock(p_profile uuid) returns void
language sql security definer set search_path = public as $$
  delete from blocks where blocker_id = auth.uid() and blocked_id = p_profile
$$;
revoke all on function public.unblock(uuid) from public, anon;
grant execute on function public.unblock(uuid) to authenticated;

-- Accepted dates still ahead, in active matches: who, what, when, where.
create or replace function public.my_upcoming_dates() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'message_id', m.id, 'match_id', m.match_id,
           'name', o.name, 'sport', m.payload->>'sport',
           'when', m.payload->>'when', 'place', m.payload->>'place')
         order by (m.payload->>'when')::timestamptz), '[]'::jsonb)
  from messages m
  join matches x on x.id = m.match_id
  join profiles o on o.id = case when x.user_a = auth.uid() then x.user_b else x.user_a end
  where m.kind = 'date' and m.payload->>'status' = 'accepted'
    and auth.uid() in (x.user_a, x.user_b) and x.unmatched_at is null
    and (m.payload->>'when')::timestamptz > now() - interval '3 hours'
$$;
revoke all on function public.my_upcoming_dates() from public, anon;
grant execute on function public.my_upcoming_dates() to authenticated;
