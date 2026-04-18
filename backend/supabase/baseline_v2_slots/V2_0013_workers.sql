create or replace function app.canonical_worker_transition_media_asset(
  p_media_asset_id uuid,
  p_target_state app.media_state,
  p_playback_object_path text default null,
  p_playback_format text default null,
  p_error_message text default null,
  p_next_retry_at timestamptz default null,
  p_transitioned_at timestamptz default clock_timestamp()
)
returns app.media_assets
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  v_asset app.media_assets%rowtype;
begin
  if p_media_asset_id is null then
    raise exception 'media worker transition requires media_asset_id';
  end if;

  if p_target_state is null then
    raise exception 'media worker transition requires target state';
  end if;

  if p_transitioned_at is null then
    raise exception 'media worker transition requires transitioned_at';
  end if;

  select *
    into v_asset
  from app.media_assets
  where id = p_media_asset_id
  for update;

  if not found then
    raise exception 'media asset % does not exist', p_media_asset_id;
  end if;

  if p_target_state not in (
    'uploaded'::app.media_state,
    'processing'::app.media_state,
    'ready'::app.media_state,
    'failed'::app.media_state
  ) then
    raise exception 'media worker may transition only to uploaded, processing, ready, or failed';
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    if p_target_state = 'uploaded'::app.media_state then
      if v_asset.state <> 'pending_upload'::app.media_state then
        raise exception 'media asset % must be pending_upload before uploaded', p_media_asset_id;
      end if;

      if p_playback_object_path is not null
         or p_playback_format is not null
         or p_error_message is not null
         or p_next_retry_at is not null then
        raise exception 'uploaded transition must not set playback, error, or retry fields';
      end if;

      update app.media_assets
         set state = 'uploaded'::app.media_state,
             error_message = null,
             processing_locked_at = null,
             next_retry_at = null,
             updated_at = p_transitioned_at
       where id = p_media_asset_id
      returning * into v_asset;

    elsif p_target_state = 'processing'::app.media_state then
      if v_asset.state <> 'uploaded'::app.media_state then
        raise exception 'media asset % must be uploaded before processing', p_media_asset_id;
      end if;

      if p_playback_object_path is not null
         or p_playback_format is not null
         or p_error_message is not null
         or p_next_retry_at is not null then
        raise exception 'processing transition must not set playback, error, or retry fields';
      end if;

      update app.media_assets
         set state = 'processing'::app.media_state,
             error_message = null,
             processing_attempts = processing_attempts + 1,
             processing_locked_at = p_transitioned_at,
             next_retry_at = null,
             updated_at = p_transitioned_at
       where id = p_media_asset_id
      returning * into v_asset;

    elsif p_target_state = 'ready'::app.media_state then
      if v_asset.state <> 'processing'::app.media_state then
        raise exception 'media asset % must be processing before ready', p_media_asset_id;
      end if;

      if p_playback_object_path is null or btrim(p_playback_object_path) = '' then
        raise exception 'ready media requires playback_object_path';
      end if;

      if v_asset.media_type = 'audio'::app.media_type
         and p_playback_format is distinct from 'mp3' then
        raise exception 'ready audio media requires playback_format mp3';
      end if;

      if p_playback_format is not null and btrim(p_playback_format) = '' then
        raise exception 'playback_format must not be blank when provided';
      end if;

      update app.media_assets
         set state = 'ready'::app.media_state,
             playback_object_path = btrim(p_playback_object_path),
             playback_format = nullif(btrim(p_playback_format), ''),
             error_message = null,
             processing_locked_at = null,
             next_retry_at = null,
             updated_at = p_transitioned_at
       where id = p_media_asset_id
      returning * into v_asset;

    elsif p_target_state = 'failed'::app.media_state then
      if v_asset.state <> 'processing'::app.media_state then
        raise exception 'media asset % must be processing before failed', p_media_asset_id;
      end if;

      if p_error_message is null or btrim(p_error_message) = '' then
        raise exception 'failed media requires error_message';
      end if;

      update app.media_assets
         set state = 'failed'::app.media_state,
             error_message = btrim(p_error_message),
             processing_locked_at = null,
             next_retry_at = p_next_retry_at,
             updated_at = p_transitioned_at
       where id = p_media_asset_id
      returning * into v_asset;
    end if;

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

  return v_asset;
end;
$$;

revoke all on function app.canonical_worker_transition_media_asset(
  uuid,
  app.media_state,
  text,
  text,
  text,
  timestamptz,
  timestamptz
) from public;

comment on function app.canonical_worker_transition_media_asset(
  uuid,
  app.media_state,
  text,
  text,
  text,
  timestamptz,
  timestamptz
) is
  'Canonical worker authority for media upload-completion and processing lifecycle transitions only. It mutates app.media_assets and never writes runtime_media, storage, profile, referral, checkout, or LiveKit authority.';

create or replace function app.canonical_worker_advance_course_enrollment_drip(
  p_enrollment_id uuid,
  p_evaluated_at timestamptz default clock_timestamp()
)
returns app.course_enrollments
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  v_enrollment app.course_enrollments%rowtype;
  v_drip_enabled boolean;
  v_drip_interval_days integer;
  v_max_lesson_position integer := 0;
  v_elapsed_intervals integer := 0;
  v_computed_unlock_position integer := 0;
begin
  if p_enrollment_id is null then
    raise exception 'course enrollment drip advancement requires enrollment id';
  end if;

  if p_evaluated_at is null then
    raise exception 'course enrollment drip advancement requires evaluated_at';
  end if;

  select *
    into v_enrollment
  from app.course_enrollments
  where id = p_enrollment_id
  for update;

  if not found then
    raise exception 'course enrollment % does not exist', p_enrollment_id;
  end if;

  select
    c.drip_enabled,
    c.drip_interval_days,
    coalesce(max(l.position), 0)::integer
  into
    v_drip_enabled,
    v_drip_interval_days,
    v_max_lesson_position
  from app.courses as c
  left join app.lessons as l
    on l.course_id = c.id
  where c.id = v_enrollment.course_id
  group by c.id, c.drip_enabled, c.drip_interval_days;

  if not found then
    raise exception 'course % does not exist for enrollment %',
      v_enrollment.course_id,
      p_enrollment_id;
  end if;

  if v_drip_enabled = false then
    return v_enrollment;
  end if;

  if v_drip_interval_days is null or v_drip_interval_days <= 0 then
    raise exception 'drip-enabled course % requires positive drip_interval_days',
      v_enrollment.course_id;
  end if;

  if v_max_lesson_position = 0 then
    v_computed_unlock_position := 0;
  else
    v_elapsed_intervals := greatest(
      0,
      floor(
        extract(epoch from (p_evaluated_at - v_enrollment.drip_started_at))
        / (v_drip_interval_days * 86400.0)
      )::integer
    );

    v_computed_unlock_position := least(
      v_max_lesson_position,
      1 + v_elapsed_intervals
    );
  end if;

  if v_computed_unlock_position <= v_enrollment.current_unlock_position then
    return v_enrollment;
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    update app.course_enrollments
       set current_unlock_position = v_computed_unlock_position,
           updated_at = p_evaluated_at
     where id = p_enrollment_id
    returning * into v_enrollment;

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

  return v_enrollment;
end;
$$;

revoke all on function app.canonical_worker_advance_course_enrollment_drip(
  uuid,
  timestamptz
) from public;

comment on function app.canonical_worker_advance_course_enrollment_drip(
  uuid,
  timestamptz
) is
  'Canonical worker authority for advancing existing drip enrollment unlock state. It mutates only app.course_enrollments.current_unlock_position and never grants enrollment, checkout, membership, media, profile, referral, runtime_media, or LiveKit authority.';
