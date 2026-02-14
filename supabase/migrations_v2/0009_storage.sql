-- 0009_storage.sql
-- Storage buckets and policies.

begin;

insert into storage.buckets (id, name, public)
values ('public-media', 'public-media', true)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('course-media', 'course-media', false)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('lesson-media', 'lesson-media', false)
on conflict (id) do update set public = excluded.public;

alter table storage.objects enable row level security;

drop policy if exists storage_service_role_full_access on storage.objects;
create policy storage_service_role_full_access on storage.objects
  for all using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

drop policy if exists storage_public_read on storage.objects;
create policy storage_public_read on storage.objects
  for select to public
  using (bucket_id = 'public-media');

commit;
