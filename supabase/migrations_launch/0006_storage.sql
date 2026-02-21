-- 0006_storage.sql
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

do $$
declare
  owner_role text;
begin
  select r.rolname
    into owner_role
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_roles r on r.oid = c.relowner
   where n.nspname = 'storage'
     and c.relname = 'objects';

  if owner_role is null then
    raise notice 'Skipping storage.objects policies: table missing';
    return;
  end if;

  if owner_role <> current_user then
    raise notice 'Skipping storage.objects policies: owner=%', owner_role;
    return;
  end if;

  alter table storage.objects enable row level security;

  drop policy if exists storage_service_role_full_access on storage.objects;
  create policy storage_service_role_full_access on storage.objects
    for all using (auth.role() = 'service_role')
    with check (auth.role() = 'service_role');

  drop policy if exists storage_public_read on storage.objects;
  create policy storage_public_read on storage.objects
    for select to public
    using (bucket_id = 'public-media');
end $$;

commit;
