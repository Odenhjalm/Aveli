-- Canonical runtime media reference layer.
-- Phase 1: backfill lesson-backed runtime rows only.

begin;

create table if not exists app.runtime_media (
  id uuid primary key default gen_random_uuid(),

  reference_type text not null
    check (reference_type in ('lesson_media', 'home_player_upload')),

  auth_scope text not null
    check (auth_scope in ('lesson_course', 'home_teacher_library')),

  fallback_policy text not null
    check (fallback_policy in ('never', 'if_no_ready_asset', 'legacy_only')),

  lesson_media_id uuid unique
    references app.lesson_media(id) on delete cascade,
  home_player_upload_id uuid unique
    references app.home_player_uploads(id) on delete cascade,

  teacher_id uuid references app.profiles(user_id) on delete set null,
  course_id uuid references app.courses(id) on delete set null,
  lesson_id uuid references app.lessons(id) on delete set null,

  media_asset_id uuid references app.media_assets(id) on delete set null,
  media_object_id uuid references app.media_objects(id) on delete set null,

  legacy_storage_bucket text,
  legacy_storage_path text,

  kind text not null
    check (kind in ('audio', 'video', 'image', 'document', 'other')),

  active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint runtime_media_one_origin check (
    ((lesson_media_id is not null)::int + (home_player_upload_id is not null)::int) = 1
  ),

  constraint runtime_media_legacy_storage_pair check (
    legacy_storage_path is null or legacy_storage_bucket is not null
  ),

  constraint runtime_media_auth_shape check (
    (
      auth_scope = 'lesson_course'
      and lesson_media_id is not null
      and course_id is not null
      and lesson_id is not null
    )
    or
    (
      auth_scope = 'home_teacher_library'
      and home_player_upload_id is not null
    )
  )
);

create index if not exists idx_runtime_media_teacher_active
  on app.runtime_media(teacher_id, active);

create index if not exists idx_runtime_media_course
  on app.runtime_media(course_id);

create index if not exists idx_runtime_media_lesson
  on app.runtime_media(lesson_id);

create index if not exists idx_runtime_media_asset
  on app.runtime_media(media_asset_id);

create index if not exists idx_runtime_media_object
  on app.runtime_media(media_object_id);

alter table app.runtime_media
  drop constraint if exists runtime_media_teacher_id_fkey;

alter table app.runtime_media
  add constraint runtime_media_teacher_id_fkey
  foreign key (teacher_id) references app.profiles(user_id) on delete set null;

create or replace function app.normalize_runtime_media_kind(raw_kind text)
returns text
language sql
immutable
as $$
  select case lower(coalesce(trim(raw_kind), 'other'))
    when 'audio' then 'audio'
    when 'video' then 'video'
    when 'image' then 'image'
    when 'pdf' then 'document'
    when 'document' then 'document'
    else 'other'
  end
$$;

create or replace function app.runtime_media_lesson_fallback_policy(
  lesson_kind text,
  media_asset_id uuid,
  media_object_id uuid,
  legacy_storage_path text
)
returns text
language sql
immutable
as $$
  select case
    when media_asset_id is null then 'legacy_only'
    when lower(coalesce(trim(lesson_kind), '')) = 'audio' then 'never'
    when media_object_id is not null then 'if_no_ready_asset'
    when nullif(trim(legacy_storage_path), '') is not null then 'if_no_ready_asset'
    else 'never'
  end
$$;

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
$$;

create or replace function app.sync_runtime_media_lesson_media_trigger()
returns trigger
language plpgsql
as $$
begin
  perform app.upsert_runtime_media_for_lesson_media(new.id);
  return new;
end;
$$;

drop trigger if exists trg_runtime_media_sync_lesson_media on app.lesson_media;
create trigger trg_runtime_media_sync_lesson_media
after insert or update of lesson_id, kind, media_id, storage_path, storage_bucket, media_asset_id
on app.lesson_media
for each row execute procedure app.sync_runtime_media_lesson_media_trigger();

create or replace function app.sync_runtime_media_lesson_context_trigger()
returns trigger
language plpgsql
as $$
begin
  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm
  where lm.lesson_id = new.id;
  return new;
end;
$$;

drop trigger if exists trg_runtime_media_sync_lesson_context on app.lessons;
create trigger trg_runtime_media_sync_lesson_context
after update of course_id
on app.lessons
for each row execute procedure app.sync_runtime_media_lesson_context_trigger();

create or replace function app.sync_runtime_media_course_context_trigger()
returns trigger
language plpgsql
as $$
begin
  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  where l.course_id = new.id;
  return new;
end;
$$;

drop trigger if exists trg_runtime_media_sync_course_context on app.courses;
create trigger trg_runtime_media_sync_course_context
after update of created_by
on app.courses
for each row execute procedure app.sync_runtime_media_course_context_trigger();

drop trigger if exists trg_runtime_media_touch on app.runtime_media;
create trigger trg_runtime_media_touch
before update on app.runtime_media
for each row execute procedure app.set_updated_at();

do $$
declare
  lesson_count bigint;
  runtime_lesson_count bigint;
  duplicate_lesson_runtime_count bigint;
  synced_rows bigint;
begin
  select count(*) into lesson_count from app.lesson_media;

  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm;
  get diagnostics synced_rows = row_count;

  select count(*) into runtime_lesson_count
  from app.runtime_media
  where lesson_media_id is not null;

  select count(*) into duplicate_lesson_runtime_count
  from (
    select lesson_media_id
    from app.runtime_media
    where lesson_media_id is not null
    group by lesson_media_id
    having count(*) > 1
  ) duplicates;

  raise notice
    'runtime_media lesson backfill synced_rows=%, lesson_media_rows=%, runtime_rows=%, duplicate_rows=%',
    synced_rows,
    lesson_count,
    runtime_lesson_count,
    duplicate_lesson_runtime_count;

  if runtime_lesson_count <> lesson_count then
    raise exception
      'runtime_media lesson backfill mismatch: lesson_media_rows=% runtime_rows=%',
      lesson_count,
      runtime_lesson_count;
  end if;

  if duplicate_lesson_runtime_count <> 0 then
    raise exception
      'runtime_media lesson backfill produced duplicate lesson_media mappings: duplicate_rows=%',
      duplicate_lesson_runtime_count;
  end if;
end;
$$;

commit;
