-- 20260102113600_storage_public_media.sql
-- Align storage bucket visibility for public media.

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
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    insert into supabase_migrations.schema_migrations (version, name)
    values ('20260102113600', 'storage_public_media')
    on conflict (version) do nothing;
  end if;
end $$;

commit;
