-- 0007_storage.sql
-- Storage buckets and storage.objects policies for the v2 migration chain.

insert into storage.buckets (id, name, public)
values
  ('public-media', 'public-media', true),
  ('course-media', 'course-media', false),
  ('lesson-media', 'lesson-media', false),
  ('audio_private', 'audio_private', false),
  ('brand', 'brand', false),
  ('welcome-cards', 'welcome-cards', false)
on conflict (id) do update
  set name = excluded.name,
      public = excluded.public;

alter table storage.objects enable row level security;

drop policy if exists storage_service_role_full_access on storage.objects;
create policy storage_service_role_full_access on storage.objects
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists storage_owner_private_rw on storage.objects;
create policy storage_owner_private_rw on storage.objects
  for all to authenticated
  using (
    bucket_id in ('course-media', 'lesson-media', 'audio_private', 'brand', 'welcome-cards')
    and owner = auth.uid()
  )
  with check (
    bucket_id in ('course-media', 'lesson-media', 'audio_private', 'brand', 'welcome-cards')
    and owner = auth.uid()
  );

drop policy if exists storage_public_read_avatars_thumbnails on storage.objects;
create policy storage_public_read_avatars_thumbnails on storage.objects
  for select to public
  using (
    bucket_id = 'public-media'
    and (
      name like 'avatars/%'
      or name like 'thumbnails/%'
    )
  );

drop policy if exists storage_signed_private_read on storage.objects;
create policy storage_signed_private_read on storage.objects
  for select to authenticated
  using (bucket_id in ('course-media', 'lesson-media', 'audio_private', 'brand', 'welcome-cards'));
