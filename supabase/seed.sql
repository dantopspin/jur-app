-- Demo data for a local or staging project ONLY (supabase db reset loads it).
-- Creates one host and a week of mixed-season events in Almaty and Astana,
-- so the Events tab isn't empty while you test. Do not run on production.

insert into auth.users (id, email)
values ('00000000-0000-4000-a000-000000000001', 'host@qadam.test')
on conflict (id) do nothing;

insert into public.profiles (id, name, birthdate, gender, interested_in, city, photos, bio)
values ('00000000-0000-4000-a000-000000000001', 'Qadam Club', '1990-01-01', 'man', 'women', 'almaty',
        '{}', 'Official Qadam club account')
on conflict (id) do nothing;
update public.profiles set is_host = true, hidden = true where id = '00000000-0000-4000-a000-000000000001';

insert into public.events (host_id, city, sport_code, title, description, meeting_point, starts_at, duration_min, capacity, level, price_kzt)
values
  ('00000000-0000-4000-a000-000000000001', 'almaty', 'running',  'Saturday singles 5K',
   'Easy pace, two groups. Coffee after at the finish.', 'Gorky Park, main gate',
   date_trunc('day', now()) + interval '3 days 9 hours', 90, 40, 'all', 0),
  ('00000000-0000-4000-a000-000000000001', 'almaty', 'skiing',   'Shymbulak ski day',
   'Meet at the lower station, ride up together, lunch at the top.', 'Medeu cable car station',
   date_trunc('day', now()) + interval '4 days 10 hours', 360, 24, 'casual', 0),
  ('00000000-0000-4000-a000-000000000001', 'almaty', 'padel',    'Padel mixer',
   'Rotating pairs, 20-minute games. Rackets available.', 'Padel club, Al-Farabi Ave',
   date_trunc('day', now()) + interval '2 days 19 hours', 120, 16, 'beginner', 5000),
  ('00000000-0000-4000-a000-000000000001', 'almaty', 'skating',  'Evening skate at Medeu',
   'Two hours on the ice, then tea.', 'Medeu rink entrance',
   date_trunc('day', now()) + interval '5 days 18 hours', 120, 30, 'all', 0),
  ('00000000-0000-4000-a000-000000000001', 'astana', 'running',  'Embankment 7K',
   'Along the Esil embankment, two pace groups.', 'Khan Shatyr, south side',
   date_trunc('day', now()) + interval '3 days 10 hours', 90, 40, 'all', 0),
  ('00000000-0000-4000-a000-000000000001', 'astana', 'climbing', 'Bouldering night',
   'Beginners welcome, instructor on site.', 'Climbing gym, Turan Ave',
   date_trunc('day', now()) + interval '2 days 19 hours', 120, 20, 'beginner', 4000);

-- Demo clubs (staging). The demo host organizes them so club events can be added.
insert into public.clubs (id, city, sport_code, name, description, schedule, organizer_id) values
  ('00000000-0000-4000-c000-000000000001', 'almaty', 'running', 'Medeu Morning Runners',
   'Easy 6K every Saturday, two pace groups, tea at the long table after.', 'Saturdays 08:00 · Medeu gate',
   '00000000-0000-4000-a000-000000000001'),
  ('00000000-0000-4000-c000-000000000002', 'almaty', 'padel', 'Padel After Work',
   'Rotating pairs for every level. Rackets available.', 'Wednesdays 19:30 · Al-Farabi',
   '00000000-0000-4000-a000-000000000001'),
  ('00000000-0000-4000-c000-000000000003', 'almaty', 'skiing', 'Shymbulak Weekend Crew',
   'Carpool from the city, ride together, lunch at the top.', 'Sundays 09:00 · Medeu cable car',
   '00000000-0000-4000-a000-000000000001')
on conflict (id) do nothing;
insert into public.club_members (club_id, profile_id, role)
select id, organizer_id, 'organizer' from public.clubs where id::text like '00000000-0000-4000-c000-%'
on conflict do nothing;
