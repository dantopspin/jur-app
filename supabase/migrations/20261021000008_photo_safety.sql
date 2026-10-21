-- Photo safety: no photos from strangers. A photo can be sent in a chat only
-- after both people have written at least one text message there (the opening
-- note on a like counts). Voice notes and date cards are unaffected.
create or replace function public.check_message() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.media_path is not null and new.media_path not like new.match_id::text || '/%' then
    raise exception 'bad_media_path' using errcode = '42501';
  end if;
  if new.reply_to is not null and not exists (select 1 from messages where id = new.reply_to and match_id = new.match_id) then
    raise exception 'bad_reply' using errcode = '42501';
  end if;
  if new.kind = 'photo' and not (
       exists (select 1 from messages where match_id = new.match_id and sender_id = new.sender_id and kind = 'text')
   and exists (select 1 from messages where match_id = new.match_id and sender_id <> new.sender_id and kind = 'text')
  ) then
    raise exception 'photo_too_soon' using errcode = '42501';
  end if;
  return new;
end $$;
