-- Nationwide launch: all seven cities are open and Discover is not gated.
\set ON_ERROR_STOP 1
do $$
declare v int; r jsonb;
begin
  select count(*) into v from public.city_launch where opened_at is null;
  if v <> 0 then raise exception 'closed cities left: %', v; end if;
  raise notice 'ok - every city open';
  select count(*) into v from public.city_launch;
  if v <> 7 then raise exception 'expected 7 cities, got %', v; end if;
  raise notice 'ok - seven cities';
  r := public.city_status('astana');
  if not coalesce((r->>'open')::boolean, false) then raise exception 'astana not open: %', r; end if;
  raise notice 'ok - astana reports open';
end $$;
\echo 'LAUNCH TESTS PASSED'
