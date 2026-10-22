-- How many people you've liked (likes and super likes), for the empty Matches screen:
-- "Your likes so far: 4". Only the total: it never says who passed on you.
create or replace function public.my_likes_sent() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from swipes
   where swiper_id = auth.uid() and kind in ('like', 'super')
$$;

revoke all on function public.my_likes_sent() from public, anon;
grant execute on function public.my_likes_sent() to authenticated;
