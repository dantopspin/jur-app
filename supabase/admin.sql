-- JÜR moderation toolkit. Run pieces in the Supabase SQL editor (it runs as the
-- service role, so RLS doesn't apply). Replace the placeholders in <angle brackets>.

-- 1. Verification queue: who is waiting, with a 10-minute link to the selfie.
--    Open each selfie next to the person's profile photos and decide.
select p.id, p.member_no, p.name, p.city, p.photos[1] as main_photo, p.verification_selfie,
       p.created_at
  from profiles p
 where p.verification_status = 'pending'
 order by p.created_at;
-- Signed URL for a selfie (Storage → verification → the path above → "Get URL"), or:
-- select storage.sign_url('verification', '<selfie path>', 600);   -- if your project has a helper

-- Approve / reject (the person sees "Verified" or "try again" in Me):
update profiles set verification_status = 'approved' where id = '<profile id>';
update profiles set verification_status = 'rejected' where id = '<profile id>';

-- 2. Open reports, most-reported first. Three reporters auto-hide a profile.
select r.reported_id, p.name, p.member_no, p.hidden, p.banned,
       count(*) as reports, array_agg(distinct r.reason) as reasons,
       array_agg(r.details) filter (where r.details is not null) as details,
       max(r.created_at) as last_report
  from reports r join profiles p on p.id = r.reported_id
 where r.status = 'open'
 group by r.reported_id, p.name, p.member_no, p.hidden, p.banned
 order by reports desc, last_report desc;

-- Their recent messages to the reporters (context for harassment/scam reports):
select m.created_at, m.sender_id, m.kind, m.body
  from messages m join matches x on x.id = m.match_id
 where m.sender_id = '<reported id>'
 order by m.created_at desc limit 50;

-- Ban (hidden everywhere, signed-in app shows "suspended"), and close their reports:
update profiles set banned = true, hidden = true where id = '<reported id>';
update reports set status = 'actioned' where reported_id = '<reported id>' and status = 'open';

-- Dismiss (no action), and un-hide if the auto-hide was wrong:
update reports set status = 'dismissed' where reported_id = '<reported id>' and status = 'open';
update profiles set hidden = false where id = '<reported id>' and not banned;

-- 3. Hosts: official hosts (clubs, partners) skip the member-event limits.
update profiles set is_host = true where member_no = <member number>;

-- 4. Pushes that went out in the last hour (debugging notifications):
select created_at, profile_id, kind, title, body, tokens, request_id
  from push_outbox where created_at > now() - interval '1 hour' order by created_at desc;
