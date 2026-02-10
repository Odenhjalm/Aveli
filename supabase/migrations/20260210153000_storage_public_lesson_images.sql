-- Ensure lesson images in public-media are publicly readable.
begin;

do $$
begin
  if exists(
    select 1
    from information_schema.tables
    where table_schema = 'storage'
      and table_name = 'objects'
  ) then
    execute $sql$
      drop policy if exists storage_public_read_lesson_images on storage.objects
    $sql$;
    execute $sql$
      create policy storage_public_read_lesson_images
      on storage.objects
      for select
      to public
      using (
        bucket_id = 'public-media'
        and name like 'lessons/%/images/%'
      )
    $sql$;
  end if;
end
$$;

commit;
