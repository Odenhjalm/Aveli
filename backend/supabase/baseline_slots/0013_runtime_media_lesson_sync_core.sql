create or replace function app.normalize_runtime_media_kind(raw_kind text)
returns text
language sql
immutable
as $function$
  select case lower(coalesce(trim(raw_kind), 'other'))
    when 'audio' then 'audio'
    when 'video' then 'video'
    when 'image' then 'image'
    when 'pdf' then 'document'
    when 'document' then 'document'
    else 'other'
  end
$function$;


create or replace function app.runtime_media_lesson_fallback_policy(
  lesson_kind text,
  media_asset_id uuid,
  media_object_id uuid,
  legacy_storage_path text
)
returns text
language sql
immutable
as $function$
  select case
    when media_asset_id is null then 'legacy_only'
    when lower(coalesce(trim(lesson_kind), '')) = 'audio' then 'never'
    when media_object_id is not null then 'if_no_ready_asset'
    when nullif(trim(legacy_storage_path), '') is not null then 'if_no_ready_asset'
    else 'never'
  end
$function$;


create or replace function app.runtime_media_kind_is_playback_capable(raw_kind text)
returns boolean
language sql
immutable
as $function$
  select app.normalize_runtime_media_kind(raw_kind) in ('audio', 'video', 'image')
$function$;


create or replace function app.retire_runtime_media_for_lesson_media(target_lesson_media_id uuid)
returns uuid
language plpgsql
as $function$
declare
  runtime_id uuid;
  source_row record;
begin
  select
    lm.id as lesson_media_id,
    'lesson_media'::text as reference_type,
    'lesson_course'::text as auth_scope,
    app.runtime_media_lesson_fallback_policy(
      lm.kind,
      lm.media_asset_id,
      lm.media_id,
      lm.storage_path
    ) as fallback_policy,
    coalesce(c.created_by, ma.owner_id, mo.owner_id) as teacher_id,
    l.course_id,
    lm.lesson_id,
    lm.media_asset_id,
    lm.media_id as media_object_id,
    case
      when nullif(trim(lm.storage_path), '') is not null
        then coalesce(nullif(trim(lm.storage_bucket), ''), 'lesson-media')
      else null
    end as legacy_storage_bucket,
    nullif(trim(lm.storage_path), '') as legacy_storage_path,
    app.normalize_runtime_media_kind(lm.kind) as kind,
    coalesce(lm.created_at, now()) as created_at
  into source_row
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  join app.courses c on c.id = l.course_id
  left join app.media_objects mo on mo.id = lm.media_id
  left join app.media_assets ma on ma.id = lm.media_asset_id
  where lm.id = target_lesson_media_id;

  if not found then
    return null;
  end if;

  if app.runtime_media_kind_is_playback_capable(source_row.kind) then
    raise exception
      'lesson_media % remains playback-capable and cannot be retired from runtime_media',
      target_lesson_media_id
      using errcode = '23514';
  end if;

  insert into app.runtime_media (
    reference_type,
    auth_scope,
    fallback_policy,
    lesson_media_id,
    teacher_id,
    course_id,
    lesson_id,
    media_asset_id,
    media_object_id,
    legacy_storage_bucket,
    legacy_storage_path,
    kind,
    active,
    created_at,
    updated_at
  )
  values (
    source_row.reference_type,
    source_row.auth_scope,
    source_row.fallback_policy,
    source_row.lesson_media_id,
    source_row.teacher_id,
    source_row.course_id,
    source_row.lesson_id,
    source_row.media_asset_id,
    source_row.media_object_id,
    source_row.legacy_storage_bucket,
    source_row.legacy_storage_path,
    source_row.kind,
    false,
    source_row.created_at,
    now()
  )
  on conflict (lesson_media_id) do update
    set reference_type = excluded.reference_type,
        auth_scope = excluded.auth_scope,
        fallback_policy = excluded.fallback_policy,
        teacher_id = excluded.teacher_id,
        course_id = excluded.course_id,
        lesson_id = excluded.lesson_id,
        media_asset_id = excluded.media_asset_id,
        media_object_id = excluded.media_object_id,
        legacy_storage_bucket = excluded.legacy_storage_bucket,
        legacy_storage_path = excluded.legacy_storage_path,
        kind = excluded.kind,
        active = false,
        updated_at = now()
  returning id into runtime_id;

  return runtime_id;
end;
$function$;


create or replace function app.upsert_runtime_media_for_lesson_media(target_lesson_media_id uuid)
returns uuid
language plpgsql
as $function$
declare
  runtime_id uuid;
  normalized_kind text;
begin
  select app.normalize_runtime_media_kind(lm.kind)
  into normalized_kind
  from app.lesson_media lm
  where lm.id = target_lesson_media_id;

  if normalized_kind is null then
    return null;
  end if;

  if not app.runtime_media_kind_is_playback_capable(normalized_kind) then
    return app.retire_runtime_media_for_lesson_media(target_lesson_media_id);
  end if;

  insert into app.runtime_media (
    reference_type,
    auth_scope,
    fallback_policy,
    lesson_media_id,
    teacher_id,
    course_id,
    lesson_id,
    media_asset_id,
    media_object_id,
    legacy_storage_bucket,
    legacy_storage_path,
    kind,
    active,
    created_at,
    updated_at
  )
  select
    'lesson_media',
    'lesson_course',
    app.runtime_media_lesson_fallback_policy(
      lm.kind,
      lm.media_asset_id,
      lm.media_id,
      lm.storage_path
    ),
    lm.id,
    coalesce(c.created_by, ma.owner_id, mo.owner_id),
    l.course_id,
    lm.lesson_id,
    lm.media_asset_id,
    lm.media_id,
    case
      when nullif(trim(lm.storage_path), '') is not null
        then coalesce(nullif(trim(lm.storage_bucket), ''), 'lesson-media')
      else null
    end,
    nullif(trim(lm.storage_path), ''),
    app.normalize_runtime_media_kind(lm.kind),
    true,
    coalesce(lm.created_at, now()),
    now()
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  join app.courses c on c.id = l.course_id
  left join app.media_objects mo on mo.id = lm.media_id
  left join app.media_assets ma on ma.id = lm.media_asset_id
  where lm.id = target_lesson_media_id
  on conflict (lesson_media_id) do update
    set reference_type = excluded.reference_type,
        auth_scope = excluded.auth_scope,
        fallback_policy = excluded.fallback_policy,
        teacher_id = excluded.teacher_id,
        course_id = excluded.course_id,
        lesson_id = excluded.lesson_id,
        media_asset_id = excluded.media_asset_id,
        media_object_id = excluded.media_object_id,
        legacy_storage_bucket = excluded.legacy_storage_bucket,
        legacy_storage_path = excluded.legacy_storage_path,
        kind = excluded.kind,
        active = excluded.active,
        updated_at = now()
  returning id into runtime_id;

  return runtime_id;
end;
$function$;


create or replace function app.sync_runtime_media_lesson_media_trigger()
returns trigger
language plpgsql
as $function$
begin
  perform app.upsert_runtime_media_for_lesson_media(new.id);
  return new;
end;
$function$;


create trigger trg_runtime_media_sync_lesson_media
after insert or update of lesson_id, kind, media_id, storage_path, storage_bucket, media_asset_id
on app.lesson_media
for each row
execute function app.sync_runtime_media_lesson_media_trigger();
