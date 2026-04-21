-- Slot 0023 canonicalizes zero-based contiguous course-family ordering directly
-- on app.courses. It adds append-only observability for family-position
-- changes, performs a deterministic backfill that preserves existing family
-- order by current group_position and resolves ties by course id ascending,
-- and installs deferred set-level enforcement for future writes.
--
-- This slot does not assign access, pricing, enrollment, bundle, payment, or
-- membership semantics to course_group_id or group_position.

create table if not exists app.course_family_position_events (
  event_id uuid not null default gen_random_uuid(),
  audit_run_id uuid,
  course_id uuid not null,
  event_type text not null,
  reason text not null,
  old_course_group_id uuid,
  new_course_group_id uuid,
  old_group_position integer,
  new_group_position integer,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint course_family_position_events_pkey primary key (event_id),

  constraint course_family_position_events_event_type_check
    check (event_type in ('insert', 'update', 'delete')),

  constraint course_family_position_events_reason_not_blank_check
    check (btrim(reason) <> ''),

  constraint course_family_position_events_old_position_check
    check (old_group_position is null or old_group_position >= 0),

  constraint course_family_position_events_new_position_check
    check (new_group_position is null or new_group_position >= 0)
);

create index if not exists course_family_position_events_audit_run_id_idx
  on app.course_family_position_events (audit_run_id)
  where audit_run_id is not null;

create index if not exists course_family_position_events_course_id_idx
  on app.course_family_position_events (course_id);

create index if not exists course_family_position_events_old_group_idx
  on app.course_family_position_events (old_course_group_id, old_group_position)
  where old_course_group_id is not null;

create index if not exists course_family_position_events_new_group_idx
  on app.course_family_position_events (new_course_group_id, new_group_position)
  where new_course_group_id is not null;

comment on table app.course_family_position_events is
  'Append-only observability log for canonical course-family position changes. It does not own course-family or course-order authority.';

comment on column app.course_family_position_events.audit_run_id is
  'Optional correlation id for one deterministic backfill or operator-scoped position rewrite run.';

comment on column app.course_family_position_events.reason is
  'Operator or system reason for the position change. Observability only.';

comment on column app.course_family_position_events.metadata is
  'Structured observability payload for position changes. It is not course-family authority.';

create or replace function app.prevent_course_family_position_events_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  raise exception 'app.course_family_position_events is append-only observability support';
end;
$$;

drop trigger if exists course_family_position_events_append_only
  on app.course_family_position_events;

create trigger course_family_position_events_append_only
before update or delete on app.course_family_position_events
for each row
execute function app.prevent_course_family_position_events_mutation();

create or replace function app.log_course_family_position_event()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_reason text;
  v_origin text;
  v_run_id_text text;
  v_run_id uuid;
begin
  v_reason := coalesce(
    nullif(
      btrim(pg_catalog.current_setting('app.course_family_position_event_reason', true)),
      ''
    ),
    'course_family_position_write'
  );
  v_origin := coalesce(
    nullif(
      btrim(pg_catalog.current_setting('app.course_family_position_event_origin', true)),
      ''
    ),
    'app.courses'
  );
  v_run_id_text := nullif(
    pg_catalog.current_setting('app.course_family_position_event_run_id', true),
    ''
  );

  if v_run_id_text is not null then
    v_run_id := v_run_id_text::uuid;
  end if;

  if tg_op = 'INSERT' then
    insert into app.course_family_position_events (
      audit_run_id,
      course_id,
      event_type,
      reason,
      old_course_group_id,
      new_course_group_id,
      old_group_position,
      new_group_position,
      metadata
    )
    values (
      v_run_id,
      new.id,
      'insert',
      v_reason,
      null,
      new.course_group_id,
      null,
      new.group_position,
      jsonb_build_object(
        'origin',
        v_origin,
        'trigger_name',
        tg_name
      )
    );

    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.course_group_id is not distinct from old.course_group_id
       and new.group_position is not distinct from old.group_position then
      return new;
    end if;

    insert into app.course_family_position_events (
      audit_run_id,
      course_id,
      event_type,
      reason,
      old_course_group_id,
      new_course_group_id,
      old_group_position,
      new_group_position,
      metadata
    )
    values (
      v_run_id,
      new.id,
      'update',
      v_reason,
      old.course_group_id,
      new.course_group_id,
      old.group_position,
      new.group_position,
      jsonb_build_object(
        'origin',
        v_origin,
        'trigger_name',
        tg_name
      )
    );

    return new;
  end if;

  if tg_op = 'DELETE' then
    insert into app.course_family_position_events (
      audit_run_id,
      course_id,
      event_type,
      reason,
      old_course_group_id,
      new_course_group_id,
      old_group_position,
      new_group_position,
      metadata
    )
    values (
      v_run_id,
      old.id,
      'delete',
      v_reason,
      old.course_group_id,
      null,
      old.group_position,
      null,
      jsonb_build_object(
        'origin',
        v_origin,
        'trigger_name',
        tg_name
      )
    );

    return old;
  end if;

  raise exception 'unsupported course-family position event operation %', tg_op;
end;
$$;

drop trigger if exists courses_family_position_event_log
  on app.courses;

create trigger courses_family_position_event_log
after insert or delete or update of course_group_id, group_position
on app.courses
for each row
execute function app.log_course_family_position_event();

create or replace function app.assert_course_family_positions_contiguous(
  p_course_group_id uuid
)
returns void
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_count integer;
  v_min_position integer;
  v_max_position integer;
  v_distinct_positions integer;
begin
  if p_course_group_id is null then
    raise exception 'course family contiguity check requires course_group_id';
  end if;

  select count(*)::integer,
         min(group_position)::integer,
         max(group_position)::integer,
         count(distinct group_position)::integer
    into v_count, v_min_position, v_max_position, v_distinct_positions
  from app.courses
  where course_group_id = p_course_group_id;

  if v_count = 0 then
    return;
  end if;

  if v_min_position <> 0
     or v_max_position <> v_count - 1
     or v_distinct_positions <> v_count then
    raise exception
      'course family % must occupy contiguous positions from 0 to %',
      p_course_group_id,
      v_count - 1;
  end if;
end;
$$;

create or replace function app.enforce_course_family_positions_contiguous()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
begin
  if tg_op = 'INSERT' then
    perform app.assert_course_family_positions_contiguous(new.course_group_id);
    return null;
  end if;

  if tg_op = 'UPDATE' then
    if new.course_group_id is not distinct from old.course_group_id
       and new.group_position is not distinct from old.group_position then
      return null;
    end if;

    perform app.assert_course_family_positions_contiguous(old.course_group_id);

    if new.course_group_id is distinct from old.course_group_id then
      perform app.assert_course_family_positions_contiguous(new.course_group_id);
    end if;

    return null;
  end if;

  if tg_op = 'DELETE' then
    perform app.assert_course_family_positions_contiguous(old.course_group_id);
    return null;
  end if;

  raise exception 'unsupported course-family contiguity operation %', tg_op;
end;
$$;

create or replace function app.reindex_course_family_positions(
  p_reason text default 'baseline_v2_slot_0023_backfill',
  p_origin text default 'V2_0023_course_family_ordering.sql'
)
returns table (
  audit_run_id uuid,
  changed_count integer
)
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  v_reason text;
  v_origin text;
  v_run_id uuid := gen_random_uuid();
  v_changed_count integer := 0;
begin
  v_reason := coalesce(nullif(btrim(p_reason), ''), 'baseline_v2_slot_0023_backfill');
  v_origin := coalesce(nullif(btrim(p_origin), ''), 'V2_0023_course_family_ordering.sql');

  perform pg_catalog.set_config(
    'app.course_family_position_event_reason',
    v_reason,
    true
  );
  perform pg_catalog.set_config(
    'app.course_family_position_event_origin',
    v_origin,
    true
  );
  perform pg_catalog.set_config(
    'app.course_family_position_event_run_id',
    v_run_id::text,
    true
  );

  with ranked as (
    select c.id,
           c.group_position as old_group_position,
           row_number() over (
             partition by c.course_group_id
             order by c.group_position asc, c.id asc
           )::integer - 1 as new_group_position
    from app.courses c
  ),
  changed as (
    update app.courses c
       set group_position = ranked.new_group_position
      from ranked
     where c.id = ranked.id
       and c.group_position is distinct from ranked.new_group_position
    returning 1
  )
  select count(*)::integer
    into v_changed_count
  from changed;

  perform pg_catalog.set_config('app.course_family_position_event_reason', '', true);
  perform pg_catalog.set_config('app.course_family_position_event_origin', '', true);
  perform pg_catalog.set_config('app.course_family_position_event_run_id', '', true);

  audit_run_id := v_run_id;
  changed_count := v_changed_count;
  return next;
end;
$$;

comment on function app.reindex_course_family_positions(text, text) is
  'Deterministic course-family backfill: preserve current family order by group_position and resolve ties by course id ascending, then rewrite each family to contiguous zero-based positions.';

lock table app.courses in share row exclusive mode;

alter table app.courses
  drop constraint if exists courses_group_position_key;

do $$
declare
  v_audit_run_id uuid;
  v_changed_count integer;
begin
  select audit_run_id, changed_count
    into v_audit_run_id, v_changed_count
  from app.reindex_course_family_positions(
    'baseline_v2_slot_0023_backfill',
    'V2_0023_course_family_ordering.sql'
  );
end;
$$;

alter table app.courses
  add constraint courses_group_position_key
  unique (course_group_id, group_position)
  deferrable initially deferred;

drop trigger if exists courses_family_positions_contiguous_positions
  on app.courses;

create constraint trigger courses_family_positions_contiguous_positions
after insert or update or delete
on app.courses
deferrable initially deferred
for each row
execute function app.enforce_course_family_positions_contiguous();

comment on column app.courses.course_group_id is
  'Canonical course family identifier. Family authority exists only in app.courses.';

comment on column app.courses.group_position is
  'Canonical zero-based contiguous course-family order. Position 0 is the structural intro slot only.';
