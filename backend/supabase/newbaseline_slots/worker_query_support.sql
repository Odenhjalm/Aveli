-- Phase 5: canonical media pipeline enforcement
-- This slot owns only the canonical worker mutation boundary and minimal
-- worker-support enforcement for media readiness.
-- It must not introduce queue tables, retry tables, alternate mutation paths,
-- or direct writes to app.runtime_media.
-- runtime_media remains a read-only projection owned by Phase 3.
-- The canonical worker function is the only allowed mutation boundary for
-- transitions that move app.media_assets into worker-owned processing states
-- and into playback-ready state.
-- Minimal audio readiness verification is stored on app.media_assets as
-- playback_format, assigned by the canonical worker function.

create or replace function app.enforce_media_assets_pipeline()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  in_worker_context boolean :=
    coalesce(current_setting('app.canonical_worker_function_context', true), '') = 'on';
begin
  if tg_op = 'INSERT' then
    if new.state = 'ready'::app.media_state then
      raise exception
        'canonical media pipeline forbids inserting media_assets directly into ready state';
    end if;

    if new.playback_format is not null then
      raise exception
        'playback_format is assigned only by the canonical worker function';
    end if;

    if new.media_type = 'audio'::app.media_type
       and new.state not in (
         'pending_upload'::app.media_state,
         'uploaded'::app.media_state
       ) then
      raise exception
        'audio media_assets must begin in pending_upload or uploaded state';
    end if;

    return new;
  end if;

  if new.id is distinct from old.id
     or new.media_type is distinct from old.media_type
     or new.purpose is distinct from old.purpose
     or new.original_object_path is distinct from old.original_object_path
     or new.ingest_format is distinct from old.ingest_format then
    raise exception
      'canonical media pipeline does not allow mutation of media_assets identity or source fields';
  end if;

  if new.playback_format is distinct from old.playback_format
     and not in_worker_context then
    raise exception
      'playback_format may be assigned only through the canonical worker function';
  end if;

  if new.state is not distinct from old.state
     and new.playback_format is not distinct from old.playback_format then
    return new;
  end if;

  if old.state = 'pending_upload'::app.media_state
     and new.state = 'uploaded'::app.media_state then
    return new;
  end if;

  if old.state = 'uploaded'::app.media_state
     and new.state = 'processing'::app.media_state then
    if not in_worker_context then
      raise exception
        'uploaded -> processing may occur only through the canonical worker function';
    end if;

    if old.media_type = 'audio'::app.media_type
       and new.playback_format is distinct from 'mp3' then
      raise exception
        'uploaded -> processing for audio must assign playback_format = mp3';
    end if;

    return new;
  end if;

  if old.state = 'processing'::app.media_state
     and new.state in (
       'ready'::app.media_state,
       'failed'::app.media_state
     ) then
    if not in_worker_context then
      raise exception
        'processing -> ready/failed may occur only through the canonical worker function';
    end if;

    if old.media_type = 'audio'::app.media_type
       and new.state = 'ready'::app.media_state
       and new.playback_format is distinct from 'mp3' then
      raise exception
        'audio ready requires playback_format = mp3';
    end if;

    return new;
  end if;

  raise exception
    'invalid canonical media_assets state transition: % -> %',
    old.state,
    new.state;
end;
$$;

create or replace function app.canonical_worker_transition_media_asset_state(
  p_media_asset_id uuid,
  p_target_state app.media_state
)
returns app.media_assets
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  updated_row app.media_assets%rowtype;
begin
  if p_target_state not in (
    'processing'::app.media_state,
    'ready'::app.media_state,
    'failed'::app.media_state
  ) then
    raise exception
      'canonical worker function accepts only processing, ready, or failed as target states';
  end if;

  perform 1
  from app.media_assets
  where id = p_media_asset_id
  for update;

  if not found then
    raise exception
      'media_assets row % does not exist',
      p_media_asset_id;
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    update app.media_assets
    set state = p_target_state,
        playback_format = case
          when media_type = 'audio'::app.media_type
               and p_target_state = 'processing'::app.media_state
            then 'mp3'
          else playback_format
        end
    where id = p_media_asset_id
    returning * into updated_row;
  exception
    when others then
      perform pg_catalog.set_config(
        'app.canonical_worker_function_context',
        'off',
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'off',
    true
  );

  return updated_row;
end;
$$;

revoke all on function app.canonical_worker_transition_media_asset_state(
  uuid,
  app.media_state
) from public;

drop trigger if exists media_assets_pipeline_enforcement on app.media_assets;

create trigger media_assets_pipeline_enforcement
before insert or update on app.media_assets
for each row
execute function app.enforce_media_assets_pipeline();

-- Canonical drip progression remains stored state on app.course_enrollments.
-- Only the worker may advance current_unlock_position after enrollment creation.
-- Runtime requests and frontend logic must never derive unlock state.

create index if not exists course_enrollments_drip_worker_scan_idx
on app.course_enrollments (course_id, current_unlock_position, drip_started_at);

create index if not exists lessons_course_position_desc_idx
on app.lessons (course_id, position desc);

create or replace function app.canonical_worker_advance_course_enrollment_drip(
  p_now timestamptz default clock_timestamp()
)
returns setof app.course_enrollments
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
begin
  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    return query
    with course_state as (
      select
        c.id as course_id,
        c.drip_interval_days,
        coalesce(max(l.position), 0)::integer as max_lesson_position
      from app.courses as c
      left join app.lessons as l
        on l.course_id = c.id
      where c.drip_enabled = true
      group by c.id, c.drip_interval_days
    ),
    drip_candidates as (
      select
        ce.id,
        least(
          course_state.max_lesson_position,
          (
            1 + floor(
              extract(epoch from (p_now - ce.drip_started_at))
              / (course_state.drip_interval_days * 86400)
            )
          )::integer
        ) as computed_unlock_position
      from app.course_enrollments as ce
      join course_state
        on course_state.course_id = ce.course_id
      where course_state.max_lesson_position > 0
        and ce.current_unlock_position < course_state.max_lesson_position
    ),
    updated as (
      update app.course_enrollments as ce
      set current_unlock_position = drip_candidates.computed_unlock_position
      from drip_candidates
      where ce.id = drip_candidates.id
        and drip_candidates.computed_unlock_position > ce.current_unlock_position
      returning ce.*
    )
    select * from updated;
  exception
    when others then
      perform pg_catalog.set_config(
        'app.canonical_worker_function_context',
        'off',
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'off',
    true
  );

  return;
end;
$$;

revoke all on function app.canonical_worker_advance_course_enrollment_drip(
  timestamptz
) from public;
