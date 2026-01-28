-- Ensure required Supabase Storage buckets exist for media flows.
begin;

do $$
declare
  has_public boolean;
begin
  select exists(
    select 1
    from information_schema.columns
    where table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'public'
  ) into has_public;

  if has_public then
    execute $sql$
      insert into storage.buckets (id, name, public)
      values ('public-media', 'public-media', true)
      on conflict (id) do nothing
    $sql$;
    execute $sql$
      insert into storage.buckets (id, name, public)
      values ('course-media', 'course-media', false)
      on conflict (id) do nothing
    $sql$;
    execute $sql$
      insert into storage.buckets (id, name, public)
      values ('lesson-media', 'lesson-media', false)
      on conflict (id) do nothing
    $sql$;
  else
    execute $sql$
      insert into storage.buckets (id, name)
      values ('public-media', 'public-media')
      on conflict (id) do nothing
    $sql$;
    execute $sql$
      insert into storage.buckets (id, name)
      values ('course-media', 'course-media')
      on conflict (id) do nothing
    $sql$;
    execute $sql$
      insert into storage.buckets (id, name)
      values ('lesson-media', 'lesson-media')
      on conflict (id) do nothing
    $sql$;
  end if;
end$$;

commit;
