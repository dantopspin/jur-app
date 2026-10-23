-- The paywall's one line of social proof: "В Алматы с Pro уже 1 240 человек".
-- Only real numbers, and only once they mean something: below 100 it returns null and
-- the paywall shows nothing. Rounded down to tens so it doesn't tick in front of people.

create or replace function public.pro_members_in_city() returns int
language plpgsql stable security definer set search_path = public as $$
declare
  me profiles%rowtype;
  v_n int;
begin
  select * into me from profiles where id = auth.uid();
  if not found then return null; end if;
  select count(*) into v_n from profiles p
   where effective_city(p) = effective_city(me) and not p.banned and is_pro(p.id);
  if v_n < 100 then return null; end if;
  return (v_n / 10) * 10;
end $$;

grant execute on function public.pro_members_in_city() to authenticated;
