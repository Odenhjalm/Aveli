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

      if p_playback_format is null or btrim(p_playback_format) = '' then
        raise exception 'ready media requires playback_format';
      end if;

      if v_asset.media_type = 'audio'::app.media_type
         and btrim(p_playback_format) <> 'mp3' then
        raise exception 'ready audio media requires playback_format mp3';
      end if;

      if v_asset.purpose = 'course_cover'::app.media_purpose
         and v_asset.media_type = 'image'::app.media_type
         and btrim(p_playback_format) <> 'jpg' then
        raise exception 'ready course cover media requires playback_format jpg';
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

create or replace function app.canonical_worker_lock_media_asset_for_processing(
  p_media_asset_id uuid,
  p_locked_at timestamptz default clock_timestamp()
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
    raise exception 'media worker lock requires media_asset_id';
  end if;

  if p_locked_at is null then
    raise exception 'media worker lock requires locked_at';
  end if;

  select *
    into v_asset
  from app.media_assets
  where id = p_media_asset_id
  for update;

  if not found then
    raise exception 'media asset % does not exist', p_media_asset_id;
  end if;

  if v_asset.state not in (
    'uploaded'::app.media_state,
    'processing'::app.media_state
  ) then
    raise exception 'media asset % must be uploaded or processing before worker lock', p_media_asset_id;
  end if;

  if v_asset.processing_locked_at is not null then
    raise exception 'media asset % is already processing-locked', p_media_asset_id;
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    update app.media_assets
       set state = 'processing'::app.media_state,
           error_message = null,
           processing_locked_at = p_locked_at,
           next_retry_at = null,
           updated_at = p_locked_at
     where id = p_media_asset_id
    returning * into v_asset;

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

create or replace function app.canonical_worker_release_stale_media_asset_locks(
  p_stale_after_seconds integer,
  p_released_at timestamptz default clock_timestamp()
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  v_released integer := 0;
begin
  if p_stale_after_seconds is null or p_stale_after_seconds < 1 then
    raise exception 'media worker stale lock release requires positive stale_after_seconds';
  end if;

  if p_released_at is null then
    raise exception 'media worker stale lock release requires released_at';
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    update app.media_assets
       set processing_locked_at = null,
           next_retry_at = case
             when next_retry_at is null or next_retry_at > p_released_at
               then p_released_at
             else next_retry_at
           end,
           updated_at = p_released_at
     where state = 'processing'::app.media_state
       and processing_locked_at is not null
       and processing_locked_at < p_released_at - make_interval(secs => p_stale_after_seconds)
       and (
         media_type = 'audio'::app.media_type
         or (
           media_type = 'image'::app.media_type
           and purpose in (
             'course_cover'::app.media_purpose,
             'profile_media'::app.media_purpose
           )
         )
       );

    get diagnostics v_released = row_count;

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

  return v_released;
end;
$$;

create or replace function app.canonical_worker_defer_media_asset_processing(
  p_media_asset_id uuid,
  p_next_retry_at timestamptz default clock_timestamp(),
  p_deferred_at timestamptz default clock_timestamp()
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
    raise exception 'media worker defer requires media_asset_id';
  end if;

  if p_next_retry_at is null then
    raise exception 'media worker defer requires next_retry_at';
  end if;

  if p_deferred_at is null then
    raise exception 'media worker defer requires deferred_at';
  end if;

  select *
    into v_asset
  from app.media_assets
  where id = p_media_asset_id
  for update;

  if not found then
    raise exception 'media asset % does not exist', p_media_asset_id;
  end if;

  if v_asset.state not in (
    'uploaded'::app.media_state,
    'processing'::app.media_state
  ) then
    raise exception 'media asset % must be uploaded or processing before defer', p_media_asset_id;
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    update app.media_assets
       set processing_locked_at = null,
           next_retry_at = p_next_retry_at,
           updated_at = p_deferred_at
     where id = p_media_asset_id
    returning * into v_asset;

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

create or replace function app.canonical_worker_increment_media_asset_attempts(
  p_media_asset_id uuid,
  p_incremented_at timestamptz default clock_timestamp()
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
    raise exception 'media worker attempt increment requires media_asset_id';
  end if;

  if p_incremented_at is null then
    raise exception 'media worker attempt increment requires incremented_at';
  end if;

  select *
    into v_asset
  from app.media_assets
  where id = p_media_asset_id
  for update;

  if not found then
    raise exception 'media asset % does not exist', p_media_asset_id;
  end if;

  if v_asset.state <> 'processing'::app.media_state then
    raise exception 'media asset % must be processing before attempt increment', p_media_asset_id;
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    update app.media_assets
       set processing_attempts = coalesce(processing_attempts, 0) + 1,
           updated_at = p_incremented_at
     where id = p_media_asset_id
    returning * into v_asset;

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

revoke all on function app.canonical_worker_lock_media_asset_for_processing(
  uuid,
  timestamptz
) from public;

revoke all on function app.canonical_worker_release_stale_media_asset_locks(
  integer,
  timestamptz
) from public;

revoke all on function app.canonical_worker_defer_media_asset_processing(
  uuid,
  timestamptz,
  timestamptz
) from public;

revoke all on function app.canonical_worker_increment_media_asset_attempts(
  uuid,
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
  'Canonical worker authority for media upload-completion and terminal processing transitions. It mutates app.media_assets lifecycle fields only inside DB-owned worker context.';

comment on function app.canonical_worker_lock_media_asset_for_processing(
  uuid,
  timestamptz
) is
  'Canonical worker authority for acquiring media processing locks and moving uploaded assets into processing state.';

comment on function app.canonical_worker_release_stale_media_asset_locks(
  integer,
  timestamptz
) is
  'Canonical worker authority for releasing stale media processing locks.';

comment on function app.canonical_worker_defer_media_asset_processing(
  uuid,
  timestamptz,
  timestamptz
) is
  'Canonical worker authority for deferring media processing and scheduling retry.';

comment on function app.canonical_worker_increment_media_asset_attempts(
  uuid,
  timestamptz
) is
  'Canonical worker authority for consuming a media processing attempt.';
