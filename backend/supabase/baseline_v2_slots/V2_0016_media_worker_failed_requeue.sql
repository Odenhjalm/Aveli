create or replace function app.canonical_worker_requeue_failed_media_asset(
  p_media_asset_id uuid,
  p_requeued_at timestamptz default clock_timestamp()
) returns app.media_assets
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  v_asset app.media_assets%rowtype;
begin
  if p_media_asset_id is null then
    raise exception 'media worker requeue requires media_asset_id';
  end if;

  if p_requeued_at is null then
    raise exception 'media worker requeue requires requeued_at';
  end if;

  select *
    into v_asset
  from app.media_assets
  where id = p_media_asset_id
  for update;

  if not found then
    raise exception 'media asset % does not exist', p_media_asset_id;
  end if;

  if v_asset.state <> 'failed'::app.media_state then
    raise exception 'media asset % must be failed before requeue', p_media_asset_id;
  end if;

  if not (
    v_asset.media_type = 'audio'::app.media_type
    or (
      v_asset.media_type = 'image'::app.media_type
      and v_asset.purpose in (
        'course_cover'::app.media_purpose,
        'profile_media'::app.media_purpose
      )
    )
  ) then
    raise exception 'media asset % is not worker-requeueable', p_media_asset_id;
  end if;

  perform pg_catalog.set_config(
    'app.canonical_worker_function_context',
    'on',
    true
  );

  begin
    update app.media_assets
       set state = 'uploaded'::app.media_state,
           playback_object_path = null,
           playback_format = null,
           error_message = null,
           processing_locked_at = null,
           next_retry_at = null,
           updated_at = p_requeued_at
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

revoke all on function app.canonical_worker_requeue_failed_media_asset(
  uuid,
  timestamptz
) from public;

comment on function app.canonical_worker_requeue_failed_media_asset(
  uuid,
  timestamptz
) is
  'Canonical worker authority for retrying failed media assets by returning them to uploaded queue state without mutating immutable media identity.';
