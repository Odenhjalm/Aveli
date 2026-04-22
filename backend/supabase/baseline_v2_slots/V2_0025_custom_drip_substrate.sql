create table if not exists app.course_custom_drip_configs (
  course_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_custom_drip_configs_pkey primary key (course_id),
  constraint course_custom_drip_configs_course_id_fkey
    foreign key (course_id) references app.courses (id) on delete cascade
);

comment on table app.course_custom_drip_configs is
  'Canonical custom-drip schedule root. Presence of a row selects custom lesson-offset scheduling for the course.';

create table if not exists app.course_custom_drip_lesson_offsets (
  course_id uuid not null,
  lesson_id uuid not null,
  unlock_offset_days integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_custom_drip_lesson_offsets_pkey primary key (course_id, lesson_id),
  constraint course_custom_drip_lesson_offsets_course_id_fkey
    foreign key (course_id)
    references app.course_custom_drip_configs (course_id)
    on delete cascade,
  constraint course_custom_drip_lesson_offsets_lesson_id_fkey
    foreign key (lesson_id)
    references app.lessons (id)
    on delete cascade,
  constraint course_custom_drip_lesson_offsets_unlock_offset_days_check
    check (unlock_offset_days >= 0)
);

create index if not exists course_custom_drip_lesson_offsets_lesson_id_idx
  on app.course_custom_drip_lesson_offsets (lesson_id);

create index if not exists course_custom_drip_lesson_offsets_course_offset_idx
  on app.course_custom_drip_lesson_offsets (course_id, unlock_offset_days);

comment on table app.course_custom_drip_lesson_offsets is
  'Canonical per-lesson custom-drip offsets. unlock_offset_days is the cumulative day offset from course_enrollments.drip_started_at.';

comment on column app.course_custom_drip_lesson_offsets.unlock_offset_days is
  'Cumulative unlock offset in whole days from app.course_enrollments.drip_started_at. This is not stored on app.lessons.';

create or replace function app.touch_course_custom_drip_schedule_row()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, clock_timestamp());
  end if;

  new.updated_at := clock_timestamp();
  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'course_custom_drip_configs'
      and tg.tgname = 'course_custom_drip_configs_touch_timestamps'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger course_custom_drip_configs_touch_timestamps
      before insert or update
      on app.course_custom_drip_configs
      for each row
      execute function app.touch_course_custom_drip_schedule_row()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'course_custom_drip_lesson_offsets'
      and tg.tgname = 'course_custom_drip_lesson_offsets_touch_timestamps'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger course_custom_drip_lesson_offsets_touch_timestamps
      before insert or update
      on app.course_custom_drip_lesson_offsets
      for each row
      execute function app.touch_course_custom_drip_schedule_row()
    $sql$;
  end if;
end;
$$;

create or replace function app.course_custom_drip_schedule_is_locked(
  p_course_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, app
as $$
  select exists (
    select 1
    from app.course_enrollments
    where course_id = p_course_id
  );
$$;

comment on function app.course_custom_drip_schedule_is_locked(uuid) is
  'Returns true once any enrollment exists for the course. Custom-drip schedule-affecting edits are forbidden after that point.';

create or replace function app.assert_course_custom_drip_schedule(
  p_course_id uuid
)
returns void
language plpgsql
stable
set search_path = pg_catalog, app
as $$
declare
  v_drip_enabled boolean;
  v_drip_interval_days integer;
  v_lesson_count integer := 0;
  v_offset_count integer := 0;
  v_first_offset integer;
  v_invalid_row_count integer := 0;
begin
  if p_course_id is null then
    raise exception 'custom drip schedule validation requires course id';
  end if;

  if not exists (
    select 1
    from app.course_custom_drip_configs
    where course_id = p_course_id
  ) then
    raise exception 'course % lacks custom drip config', p_course_id;
  end if;

  select c.drip_enabled, c.drip_interval_days
    into v_drip_enabled, v_drip_interval_days
  from app.courses as c
  where c.id = p_course_id;

  if not found then
    raise exception 'course % does not exist', p_course_id;
  end if;

  if v_drip_enabled or v_drip_interval_days is not null then
    raise exception 'custom drip course % requires legacy drip fields disabled',
      p_course_id;
  end if;

  select count(*)
    into v_lesson_count
  from app.lessons
  where course_id = p_course_id;

  select count(*)
    into v_offset_count
  from app.course_custom_drip_lesson_offsets
  where course_id = p_course_id;

  if v_offset_count <> v_lesson_count then
    raise exception 'course % custom drip requires one offset row per lesson',
      p_course_id;
  end if;

  if v_lesson_count = 0 then
    return;
  end if;

  select offsets.unlock_offset_days
    into v_first_offset
  from app.lessons as l
  join app.course_custom_drip_lesson_offsets as offsets
    on offsets.lesson_id = l.id
   and offsets.course_id = p_course_id
  where l.course_id = p_course_id
  order by l.position asc, l.id asc
  limit 1;

  if v_first_offset is distinct from 0 then
    raise exception 'course % custom drip requires first lesson offset 0',
      p_course_id;
  end if;

  select count(*)
    into v_invalid_row_count
  from (
    select
      l.id,
      l.position,
      offsets.unlock_offset_days,
      lag(offsets.unlock_offset_days) over (
        order by l.position asc, l.id asc
      ) as previous_offset_days
    from app.lessons as l
    left join app.course_custom_drip_lesson_offsets as offsets
      on offsets.lesson_id = l.id
     and offsets.course_id = p_course_id
    where l.course_id = p_course_id
  ) as schedule_rows
  where schedule_rows.unlock_offset_days is null
     or schedule_rows.unlock_offset_days < 0
     or (
       schedule_rows.previous_offset_days is not null
       and schedule_rows.unlock_offset_days < schedule_rows.previous_offset_days
     );

  if v_invalid_row_count > 0 then
    raise exception
      'course % custom drip offsets must be complete and nondecreasing by lesson.position',
      p_course_id;
  end if;
end;
$$;

comment on function app.assert_course_custom_drip_schedule(uuid) is
  'Asserts the full custom-drip authority model for one course: legacy fields disabled, exactly one offset row per lesson, first offset zero, and nondecreasing offsets by lesson.position.';

create or replace function app.assert_course_custom_drip_schedule_if_present(
  p_course_id uuid
)
returns void
language plpgsql
stable
set search_path = pg_catalog, app
as $$
begin
  if p_course_id is null then
    return;
  end if;

  if exists (
    select 1
    from app.course_custom_drip_configs
    where course_id = p_course_id
  ) then
    perform app.assert_course_custom_drip_schedule(p_course_id);
  end if;
end;
$$;

create or replace function app.enforce_course_custom_drip_config_row_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_drip_enabled boolean;
  v_drip_interval_days integer;
begin
  select c.drip_enabled, c.drip_interval_days
    into v_drip_enabled, v_drip_interval_days
  from app.courses as c
  where c.id = new.course_id;

  if not found then
    raise exception 'course % does not exist', new.course_id;
  end if;

  if v_drip_enabled or v_drip_interval_days is not null then
    raise exception
      'custom drip config requires legacy drip fields disabled for course %',
      new.course_id;
  end if;

  return new;
end;
$$;

create or replace function app.enforce_course_custom_drip_lesson_offset_row_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_lesson_course_id uuid;
begin
  select l.course_id
    into v_lesson_course_id
  from app.lessons as l
  where l.id = new.lesson_id;

  if not found then
    raise exception 'lesson % does not exist', new.lesson_id;
  end if;

  if v_lesson_course_id is distinct from new.course_id then
    raise exception
      'custom drip lesson offset lesson % must belong to course %',
      new.lesson_id,
      new.course_id;
  end if;

  return new;
end;
$$;

create or replace function app.enforce_course_custom_drip_schedule_mutation_lock()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_course_id uuid;
begin
  v_course_id := case
    when tg_op = 'DELETE' then old.course_id
    else new.course_id
  end;

  if app.course_custom_drip_schedule_is_locked(v_course_id) then
    raise exception
      'custom drip schedule-affecting edits are locked after first enrollment for course %',
      v_course_id;
  end if;

  return case
    when tg_op = 'DELETE' then old
    else new
  end;
end;
$$;

create or replace function app.enforce_course_custom_drip_course_update_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  if new.drip_enabled is not distinct from old.drip_enabled
     and new.drip_interval_days is not distinct from old.drip_interval_days then
    return new;
  end if;

  if not exists (
    select 1
    from app.course_custom_drip_configs
    where course_id = new.id
  ) then
    return new;
  end if;

  if new.drip_enabled or new.drip_interval_days is not null then
    raise exception
      'custom drip course % must keep legacy drip fields disabled',
      new.id;
  end if;

  if app.course_custom_drip_schedule_is_locked(new.id) then
    raise exception
      'custom drip schedule-affecting edits are locked after first enrollment for course %',
      new.id;
  end if;

  return new;
end;
$$;

create or replace function app.enforce_custom_drip_lesson_structure_lock()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  if tg_op = 'INSERT' then
    if exists (
      select 1
      from app.course_custom_drip_configs
      where course_id = new.course_id
    )
    and app.course_custom_drip_schedule_is_locked(new.course_id) then
      raise exception
        'custom drip schedule-affecting edits are locked after first enrollment for course %',
        new.course_id;
    end if;

    return new;
  end if;

  if tg_op = 'DELETE' then
    if exists (
      select 1
      from app.course_custom_drip_configs
      where course_id = old.course_id
    )
    and app.course_custom_drip_schedule_is_locked(old.course_id) then
      raise exception
        'custom drip schedule-affecting edits are locked after first enrollment for course %',
        old.course_id;
    end if;

    return old;
  end if;

  if new.course_id is distinct from old.course_id
     or new.position is distinct from old.position then
    if exists (
      select 1
      from app.course_custom_drip_configs
      where course_id = old.course_id
    )
    and app.course_custom_drip_schedule_is_locked(old.course_id) then
      raise exception
        'custom drip schedule-affecting edits are locked after first enrollment for course %',
        old.course_id;
    end if;

    if exists (
      select 1
      from app.course_custom_drip_configs
      where course_id = new.course_id
    )
    and app.course_custom_drip_schedule_is_locked(new.course_id) then
      raise exception
        'custom drip schedule-affecting edits are locked after first enrollment for course %',
        new.course_id;
    end if;
  end if;

  return new;
end;
$$;

create or replace function app.enforce_course_custom_drip_schedule_consistency()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  if tg_table_name = 'course_custom_drip_configs' then
    if tg_op <> 'DELETE' then
      perform app.assert_course_custom_drip_schedule(new.course_id);
    end if;
    return null;
  end if;

  if tg_table_name = 'course_custom_drip_lesson_offsets' then
    perform app.assert_course_custom_drip_schedule_if_present(
      case
        when tg_op = 'DELETE' then old.course_id
        else new.course_id
      end
    );
    return null;
  end if;

  if tg_table_name = 'lessons' then
    if tg_op = 'UPDATE' and old.course_id is distinct from new.course_id then
      perform app.assert_course_custom_drip_schedule_if_present(old.course_id);
    end if;

    perform app.assert_course_custom_drip_schedule_if_present(
      case
        when tg_op = 'DELETE' then old.course_id
        else new.course_id
      end
    );

    return null;
  end if;

  return null;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'course_custom_drip_configs'
      and tg.tgname = 'course_custom_drip_configs_row_contract'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger course_custom_drip_configs_row_contract
      before insert or update
      on app.course_custom_drip_configs
      for each row
      execute function app.enforce_course_custom_drip_config_row_contract()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'course_custom_drip_lesson_offsets'
      and tg.tgname = 'course_custom_drip_lesson_offsets_row_contract'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger course_custom_drip_lesson_offsets_row_contract
      before insert or update
      on app.course_custom_drip_lesson_offsets
      for each row
      execute function app.enforce_course_custom_drip_lesson_offset_row_contract()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'course_custom_drip_configs'
      and tg.tgname = 'course_custom_drip_configs_schedule_lock'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger course_custom_drip_configs_schedule_lock
      before insert or update or delete
      on app.course_custom_drip_configs
      for each row
      execute function app.enforce_course_custom_drip_schedule_mutation_lock()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'course_custom_drip_lesson_offsets'
      and tg.tgname = 'course_custom_drip_lesson_offsets_schedule_lock'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger course_custom_drip_lesson_offsets_schedule_lock
      before insert or update or delete
      on app.course_custom_drip_lesson_offsets
      for each row
      execute function app.enforce_course_custom_drip_schedule_mutation_lock()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'courses'
      and tg.tgname = 'courses_custom_drip_legacy_field_guard'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger courses_custom_drip_legacy_field_guard
      before update of drip_enabled, drip_interval_days
      on app.courses
      for each row
      execute function app.enforce_course_custom_drip_course_update_contract()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'lessons'
      and tg.tgname = 'lessons_custom_drip_schedule_lock'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create trigger lessons_custom_drip_schedule_lock
      before insert or update or delete
      on app.lessons
      for each row
      execute function app.enforce_custom_drip_lesson_structure_lock()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'course_custom_drip_configs'
      and tg.tgname = 'course_custom_drip_configs_schedule_consistency'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create constraint trigger course_custom_drip_configs_schedule_consistency
      after insert or update
      on app.course_custom_drip_configs
      deferrable initially deferred
      for each row
      execute function app.enforce_course_custom_drip_schedule_consistency()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'course_custom_drip_lesson_offsets'
      and tg.tgname = 'course_custom_drip_lesson_offsets_schedule_consistency'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create constraint trigger course_custom_drip_lesson_offsets_schedule_consistency
      after insert or update or delete
      on app.course_custom_drip_lesson_offsets
      deferrable initially deferred
      for each row
      execute function app.enforce_course_custom_drip_schedule_consistency()
    $sql$;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger as tg
    join pg_class as cls
      on cls.oid = tg.tgrelid
    join pg_namespace as n
      on n.oid = cls.relnamespace
    where n.nspname = 'app'
      and cls.relname = 'lessons'
      and tg.tgname = 'lessons_custom_drip_schedule_consistency'
      and not tg.tgisinternal
  ) then
    execute $sql$
      create constraint trigger lessons_custom_drip_schedule_consistency
      after insert or update or delete
      on app.lessons
      deferrable initially deferred
      for each row
      execute function app.enforce_course_custom_drip_schedule_consistency()
    $sql$;
  end if;
end;
$$;
