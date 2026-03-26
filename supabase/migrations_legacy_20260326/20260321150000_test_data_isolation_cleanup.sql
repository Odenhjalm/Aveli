begin;

alter table app.courses
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

alter table app.lessons
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

alter table app.lesson_media
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

alter table app.media_assets
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

alter table app.runtime_media
  add column if not exists is_test boolean not null default false,
  add column if not exists test_session_id uuid;

create index if not exists idx_courses_test_session
  on app.courses (test_session_id)
  where is_test = true;

create index if not exists idx_lessons_test_session
  on app.lessons (test_session_id)
  where is_test = true;

create index if not exists idx_lesson_media_test_session
  on app.lesson_media (test_session_id)
  where is_test = true;

create index if not exists idx_media_assets_test_session
  on app.media_assets (test_session_id)
  where is_test = true;

create index if not exists idx_runtime_media_test_session
  on app.runtime_media (test_session_id)
  where is_test = true;

alter table app.courses
  drop constraint if exists courses_test_session_consistency;
alter table app.courses
  add constraint courses_test_session_consistency
  check (
    (
      coalesce(is_test, false) = false
      and test_session_id is null
    )
    or
    (
      coalesce(is_test, false) = true
      and test_session_id is not null
    )
  ) not valid;
alter table app.courses
  validate constraint courses_test_session_consistency;

alter table app.lessons
  drop constraint if exists lessons_test_session_consistency;
alter table app.lessons
  add constraint lessons_test_session_consistency
  check (
    (
      coalesce(is_test, false) = false
      and test_session_id is null
    )
    or
    (
      coalesce(is_test, false) = true
      and test_session_id is not null
    )
  ) not valid;
alter table app.lessons
  validate constraint lessons_test_session_consistency;

alter table app.lesson_media
  drop constraint if exists lesson_media_test_session_consistency;
alter table app.lesson_media
  add constraint lesson_media_test_session_consistency
  check (
    (
      coalesce(is_test, false) = false
      and test_session_id is null
    )
    or
    (
      coalesce(is_test, false) = true
      and test_session_id is not null
    )
  ) not valid;
alter table app.lesson_media
  validate constraint lesson_media_test_session_consistency;

alter table app.media_assets
  drop constraint if exists media_assets_test_session_consistency;
alter table app.media_assets
  add constraint media_assets_test_session_consistency
  check (
    (
      coalesce(is_test, false) = false
      and test_session_id is null
    )
    or
    (
      coalesce(is_test, false) = true
      and test_session_id is not null
    )
  ) not valid;
alter table app.media_assets
  validate constraint media_assets_test_session_consistency;

alter table app.runtime_media
  drop constraint if exists runtime_media_test_session_consistency;
alter table app.runtime_media
  add constraint runtime_media_test_session_consistency
  check (
    (
      coalesce(is_test, false) = false
      and test_session_id is null
    )
    or
    (
      coalesce(is_test, false) = true
      and test_session_id is not null
    )
  ) not valid;
alter table app.runtime_media
  validate constraint runtime_media_test_session_consistency;

create or replace function app.current_test_session_id()
returns uuid
language plpgsql
stable
as $$
declare
  raw_value text;
begin
  raw_value := nullif(current_setting('app.test_session_id', true), '');
  if raw_value is null then
    return null;
  end if;

  return raw_value::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

create or replace function app.is_test_row_visible(
  row_is_test boolean,
  row_test_session_id uuid
)
returns boolean
language sql
stable
as $$
  select
    coalesce(row_is_test, false) = false
    or row_test_session_id = app.current_test_session_id()
$$;

create or replace function app.apply_test_row_defaults()
returns trigger
language plpgsql
as $$
declare
  current_session_id uuid;
begin
  current_session_id := app.current_test_session_id();

  if tg_op = 'INSERT' then
    if new.test_session_id is null and current_session_id is not null then
      new.test_session_id := current_session_id;
    end if;

    if new.test_session_id is not null then
      new.is_test := true;
    end if;
  elsif tg_op = 'UPDATE' then
    if coalesce(old.is_test, false) then
      new.is_test := true;
      new.test_session_id := coalesce(new.test_session_id, old.test_session_id);
    elsif new.test_session_id is not null then
      new.is_test := true;
    end if;
  end if;

  if coalesce(new.is_test, false) then
    if new.test_session_id is null then
      if current_session_id is not null then
        new.test_session_id := current_session_id;
      else
        raise exception
          'Test rows on %.% require test_session_id',
          tg_table_schema,
          tg_table_name
          using errcode = '23514';
      end if;
    end if;
  else
    new.test_session_id := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_courses_apply_test_row_defaults on app.courses;
create trigger trg_courses_apply_test_row_defaults
before insert or update of is_test, test_session_id
on app.courses
for each row execute procedure app.apply_test_row_defaults();

drop trigger if exists trg_lessons_apply_test_row_defaults on app.lessons;
create trigger trg_lessons_apply_test_row_defaults
before insert or update of is_test, test_session_id
on app.lessons
for each row execute procedure app.apply_test_row_defaults();

drop trigger if exists trg_lesson_media_apply_test_row_defaults on app.lesson_media;
create trigger trg_lesson_media_apply_test_row_defaults
before insert or update of is_test, test_session_id
on app.lesson_media
for each row execute procedure app.apply_test_row_defaults();

drop trigger if exists trg_media_assets_apply_test_row_defaults on app.media_assets;
create trigger trg_media_assets_apply_test_row_defaults
before insert or update of is_test, test_session_id
on app.media_assets
for each row execute procedure app.apply_test_row_defaults();

drop trigger if exists trg_runtime_media_apply_test_row_defaults on app.runtime_media;
create trigger trg_runtime_media_apply_test_row_defaults
before insert or update of is_test, test_session_id
on app.runtime_media
for each row execute procedure app.apply_test_row_defaults();

create or replace function app.cleanup_test_session(target_test_session_id uuid)
returns void
language plpgsql
as $$
begin
  if target_test_session_id is null then
    raise exception 'cleanup_test_session requires test_session_id'
      using errcode = '22004';
  end if;

  delete from app.teacher_profile_media tpm
  where tpm.media_kind = 'lesson_media'
    and tpm.media_id in (
      select lm.id
      from app.lesson_media lm
      where lm.is_test = true
        and lm.test_session_id = target_test_session_id
    );

  delete from app.home_player_course_links hpcl
  where hpcl.lesson_media_id in (
    select lm.id
    from app.lesson_media lm
    where lm.is_test = true
      and lm.test_session_id = target_test_session_id
  );

  delete from app.home_player_uploads hpu
  where hpu.id in (
      select rm.home_player_upload_id
      from app.runtime_media rm
      where rm.is_test = true
        and rm.test_session_id = target_test_session_id
        and rm.home_player_upload_id is not null
    )
    or hpu.media_asset_id in (
      select ma.id
      from app.media_assets ma
      where ma.is_test = true
        and ma.test_session_id = target_test_session_id
    );

  delete from app.runtime_media
  where is_test = true
    and test_session_id = target_test_session_id;

  delete from app.lesson_media
  where is_test = true
    and test_session_id = target_test_session_id;

  delete from app.media_assets
  where is_test = true
    and test_session_id = target_test_session_id;

  delete from app.lessons
  where is_test = true
    and test_session_id = target_test_session_id;

  delete from app.courses
  where is_test = true
    and test_session_id = target_test_session_id;
end;
$$;

create or replace function app.cleanup_stale_test_data(
  max_age interval default interval '24 hours'
)
returns integer
language plpgsql
as $$
declare
  session_row record;
  cleaned_sessions integer := 0;
begin
  for session_row in
    with stale_sessions as (
      select distinct c.test_session_id
      from app.courses c
      where c.is_test = true
        and c.test_session_id is not null
        and c.created_at < now() - max_age

      union

      select distinct l.test_session_id
      from app.lessons l
      where l.is_test = true
        and l.test_session_id is not null
        and l.created_at < now() - max_age

      union

      select distinct lm.test_session_id
      from app.lesson_media lm
      where lm.is_test = true
        and lm.test_session_id is not null
        and lm.created_at < now() - max_age

      union

      select distinct ma.test_session_id
      from app.media_assets ma
      where ma.is_test = true
        and ma.test_session_id is not null
        and ma.created_at < now() - max_age

      union

      select distinct rm.test_session_id
      from app.runtime_media rm
      where rm.is_test = true
        and rm.test_session_id is not null
        and rm.created_at < now() - max_age
    )
    select stale_sessions.test_session_id
    from stale_sessions
  loop
    perform app.cleanup_test_session(session_row.test_session_id);
    cleaned_sessions := cleaned_sessions + 1;
  end loop;

  return cleaned_sessions;
end;
$$;

create or replace function app.retire_runtime_media_for_lesson_media(target_lesson_media_id uuid)
returns uuid
language plpgsql
as $$
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
    coalesce(lm.created_at, now()) as created_at,
    lm.is_test,
    lm.test_session_id
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

  update app.runtime_media rm
  set reference_type = source_row.reference_type,
      auth_scope = source_row.auth_scope,
      fallback_policy = source_row.fallback_policy,
      teacher_id = source_row.teacher_id,
      course_id = source_row.course_id,
      lesson_id = source_row.lesson_id,
      media_asset_id = source_row.media_asset_id,
      media_object_id = source_row.media_object_id,
      legacy_storage_bucket = source_row.legacy_storage_bucket,
      legacy_storage_path = source_row.legacy_storage_path,
      kind = source_row.kind,
      active = false,
      is_test = source_row.is_test,
      test_session_id = source_row.test_session_id,
      updated_at = now()
  where rm.lesson_media_id = source_row.lesson_media_id
    and rm.active = true
  returning rm.id into runtime_id;

  if runtime_id is not null then
    return runtime_id;
  end if;

  update app.runtime_media rm
  set reference_type = source_row.reference_type,
      auth_scope = source_row.auth_scope,
      fallback_policy = source_row.fallback_policy,
      teacher_id = source_row.teacher_id,
      course_id = source_row.course_id,
      lesson_id = source_row.lesson_id,
      media_asset_id = source_row.media_asset_id,
      media_object_id = source_row.media_object_id,
      legacy_storage_bucket = source_row.legacy_storage_bucket,
      legacy_storage_path = source_row.legacy_storage_path,
      kind = source_row.kind,
      active = false,
      is_test = source_row.is_test,
      test_session_id = source_row.test_session_id,
      updated_at = now()
  where rm.id = (
    select existing.id
    from app.runtime_media existing
    where existing.lesson_media_id = source_row.lesson_media_id
    order by existing.updated_at desc nulls last,
             existing.created_at desc nulls last,
             existing.id desc
    limit 1
  )
  returning rm.id into runtime_id;

  if runtime_id is not null then
    return runtime_id;
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
    is_test,
    test_session_id,
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
    source_row.is_test,
    source_row.test_session_id,
    source_row.created_at,
    now()
  )
  returning id into runtime_id;

  return runtime_id;
end;
$$;

create or replace function app.upsert_runtime_media_for_lesson_media(target_lesson_media_id uuid)
returns uuid
language plpgsql
as $$
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
    is_test,
    test_session_id,
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
    lm.is_test,
    lm.test_session_id,
    coalesce(lm.created_at, now()),
    now()
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  join app.courses c on c.id = l.course_id
  left join app.media_objects mo on mo.id = lm.media_id
  left join app.media_assets ma on ma.id = lm.media_asset_id
  where lm.id = target_lesson_media_id
  on conflict (lesson_media_id)
    where lesson_media_id is not null and active = true do update
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
        is_test = app.runtime_media.is_test or excluded.is_test,
        test_session_id = coalesce(
          excluded.test_session_id,
          app.runtime_media.test_session_id
        ),
        updated_at = now()
  returning id into runtime_id;

  return runtime_id;
end;
$$;

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
    is_test,
    test_session_id,
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
    coalesce(ma.is_test, false) or app.current_test_session_id() is not null,
    coalesce(ma.test_session_id, app.current_test_session_id()),
    coalesce(hpu.created_at, now()),
    now()
  from app.home_player_uploads hpu
  left join app.media_objects mo on mo.id = hpu.media_id
  left join app.media_assets ma on ma.id = hpu.media_asset_id
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
        is_test = app.runtime_media.is_test or excluded.is_test,
        test_session_id = coalesce(
          excluded.test_session_id,
          app.runtime_media.test_session_id
        ),
        updated_at = now()
  returning id into runtime_id;

  return runtime_id;
end;
$$;

do $$
declare
  existing_job record;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      for existing_job in
        select jobid
        from cron.job
        where jobname = 'app_cleanup_stale_test_data_hourly'
      loop
        perform cron.unschedule(existing_job.jobid);
      end loop;

      perform cron.schedule(
        'app_cleanup_stale_test_data_hourly',
        '15 * * * *',
        $cron$select app.cleanup_stale_test_data(interval '24 hours');$cron$
      );
    exception
      when undefined_table or undefined_function or invalid_schema_name then
        null;
    end;
  end if;
end;
$$;

commit;
