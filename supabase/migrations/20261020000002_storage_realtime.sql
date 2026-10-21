-- =====================================================================
-- Qadam — Storage buckets and Realtime
-- Supabase-specific; guarded so the core schema can also be tested on
-- plain Postgres.
-- =====================================================================

do $$
begin
  -- Realtime: chat messages and new matches stream to the app.
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages, public.matches;
  end if;

  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not present; skipping buckets';
    return;
  end if;

  -- Profile photos: public read (random file names), owner-only write.
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('photos', 'photos', true, 8 * 1024 * 1024, array['image/jpeg','image/png','image/webp','image/heic'])
  on conflict (id) do nothing;

  -- Verification selfies: private; only the owner can upload, moderators read in the dashboard.
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('verification', 'verification', false, 8 * 1024 * 1024, array['image/jpeg','image/png'])
  on conflict (id) do nothing;

  -- Event covers: public read, hosts write into their own folder.
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('event-covers', 'event-covers', true, 8 * 1024 * 1024, array['image/jpeg','image/png','image/webp'])
  on conflict (id) do nothing;

  execute $p$
    create policy "photos: owner uploads" on storage.objects for insert to authenticated
      with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  $p$;
  execute $p$
    create policy "photos: owner updates" on storage.objects for update to authenticated
      using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  $p$;
  execute $p$
    create policy "photos: owner deletes" on storage.objects for delete to authenticated
      using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  $p$;
  execute $p$
    create policy "verification: owner uploads" on storage.objects for insert to authenticated
      with check (bucket_id = 'verification' and (storage.foldername(name))[1] = auth.uid()::text)
  $p$;
  execute $p$
    create policy "event covers: hosts upload" on storage.objects for insert to authenticated
      with check (bucket_id = 'event-covers'
                  and (storage.foldername(name))[1] = auth.uid()::text
                  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_host))
  $p$;
end $$;
