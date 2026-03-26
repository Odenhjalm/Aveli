do $$
declare
  duplicate_lesson_runtime_count bigint;
  duplicate_lesson_runtime_sample text;
  synced_rows bigint;
begin
  select
    count(*),
    string_agg(lesson_media_id::text, ', ' order by lesson_media_id::text)
  into
    duplicate_lesson_runtime_count,
    duplicate_lesson_runtime_sample
  from (
    select lesson_media_id
    from app.runtime_media
    where lesson_media_id is not null
    group by lesson_media_id
    having count(*) > 1
    order by lesson_media_id
    limit 10
  ) duplicates;

  if duplicate_lesson_runtime_count <> 0 then
    raise exception
      'runtime_media lesson backfill halted: duplicate lesson_media mappings detected (count=%, sample_lesson_media_ids=%)',
      duplicate_lesson_runtime_count,
      coalesce(duplicate_lesson_runtime_sample, '<none>')
      using errcode = '23514';
  end if;

  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm;
  get diagnostics synced_rows = row_count;

  select count(*)
  into duplicate_lesson_runtime_count
  from (
    select lesson_media_id
    from app.runtime_media
    where lesson_media_id is not null
    group by lesson_media_id
    having count(*) > 1
  ) duplicates;

  if duplicate_lesson_runtime_count <> 0 then
    raise exception
      'runtime_media lesson backfill created duplicate lesson_media mappings (count=%)',
      duplicate_lesson_runtime_count
      using errcode = '23514';
  end if;

  raise notice
    'runtime_media lesson backfill completed: synced_rows=%',
    synced_rows;
end;
$$;
