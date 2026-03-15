begin;

create or replace function app.upsert_runtime_media_for_home_player_upload(
  target_home_player_upload_id uuid
)
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
    home_player_upload_id,
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
    'home_player_upload',
    'home_teacher_library',
    'if_no_ready_asset',
    null,
    hpu.id,
    hpu.teacher_id,
    null,
    null,
    hpu.media_asset_id,
    hpu.media_id,
    case
      when nullif(trim(mo.storage_path), '') is not null
        then coalesce(nullif(trim(mo.storage_bucket), ''), 'course-media')
      else null
    end,
    nullif(trim(mo.storage_path), ''),
    app.normalize_runtime_media_kind(hpu.kind),
    hpu.active,
    coalesce(hpu.created_at, now()),
    now()
  from app.home_player_uploads hpu
  left join app.media_objects mo on mo.id = hpu.media_id
  where hpu.id = target_home_player_upload_id
  on conflict (home_player_upload_id) do update
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

create or replace function app.sync_runtime_media_home_player_upload_trigger()
returns trigger
language plpgsql
as $$
begin
  perform app.upsert_runtime_media_for_home_player_upload(new.id);
  return new;
end;
$$;

drop trigger if exists trg_runtime_media_sync_home_player_upload on app.home_player_uploads;
create trigger trg_runtime_media_sync_home_player_upload
after insert or update of teacher_id, media_id, media_asset_id, kind, active
on app.home_player_uploads
for each row execute procedure app.sync_runtime_media_home_player_upload_trigger();

do $$
declare
  upload_count bigint;
  runtime_upload_count bigint;
  duplicate_runtime_count bigint;
begin
  select count(*) into upload_count from app.home_player_uploads;

  perform app.upsert_runtime_media_for_home_player_upload(hpu.id)
  from app.home_player_uploads hpu;

  select count(*) into runtime_upload_count
  from app.runtime_media
  where home_player_upload_id is not null;

  select count(*) into duplicate_runtime_count
  from (
    select home_player_upload_id
    from app.runtime_media
    where home_player_upload_id is not null
    group by home_player_upload_id
    having count(*) > 1
  ) duplicates;

  raise notice
    'runtime_media home upload backfill upload_rows=%, runtime_rows=%, duplicate_rows=%',
    upload_count,
    runtime_upload_count,
    duplicate_runtime_count;
end;
$$;

commit;
