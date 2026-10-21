-- Nationwide launch: every city is open from day one.
-- (The city-launch mechanism stays: set opens_at_members > 0 and opened_at = null
-- on a future city to gate it again.)
update public.city_launch
   set opens_at_members = 0,
       opened_at = coalesce(opened_at, now());
