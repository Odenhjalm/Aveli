begin;

alter table app.runtime_media
  drop constraint if exists runtime_media_lesson_media_id_key;

alter table app.runtime_media
  drop constraint if exists runtime_media_course_id_fkey;

alter table app.runtime_media
  add constraint runtime_media_course_id_fkey
  foreign key (course_id) references app.courses(id) on delete cascade;

alter table app.runtime_media
  drop constraint if exists runtime_media_lesson_id_fkey;

alter table app.runtime_media
  add constraint runtime_media_lesson_id_fkey
  foreign key (lesson_id) references app.lessons(id) on delete cascade;

create unique index if not exists idx_runtime_media_lesson_media_active_unique
  on app.runtime_media(lesson_media_id)
  where lesson_media_id is not null and active = true;

create or replace function app.upsert_runtime_media_for_lesson_media(target_lesson_media_id uuid)
returns uuid
language plpgsql
as $$
declare
  runtime_id uuid;
begin
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
  on conflict (lesson_media_id) where active = true do update
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
$$;

commit;
