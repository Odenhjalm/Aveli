-- 021_storage_policies.sql
-- Storage policies for public media and service role access.

begin;

do $$
begin
  execute 'alter table storage.objects enable row level security';
exception
  when insufficient_privilege then
    raise notice 'Skipping storage.objects RLS enable; insufficient privileges.';
end $$;

do $$
begin
  execute 'drop policy if exists storage_service_role_all on storage.objects';
  execute 'create policy storage_service_role_all on storage.objects for all using (current_setting(''request.jwt.claim.role'', true) = ''service_role'') with check (current_setting(''request.jwt.claim.role'', true) = ''service_role'')';
exception
  when insufficient_privilege then
    raise notice 'Skipping storage_service_role_all policy; insufficient privileges.';
end $$;

do $$
begin
  execute 'drop policy if exists storage_public_read on storage.objects';
  execute 'create policy storage_public_read on storage.objects for select to public using (bucket_id = ''public-media'')';
exception
  when insufficient_privilege then
    raise notice 'Skipping storage_public_read policy; insufficient privileges.';
end $$;

commit;
