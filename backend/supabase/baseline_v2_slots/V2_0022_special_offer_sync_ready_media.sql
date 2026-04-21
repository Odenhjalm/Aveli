-- Slot 0022 intentionally extends canonical ready eligibility by exactly one
-- media class: image + special_offer_composite_image + jpg.
-- This is a scoped schema-level evolution aligned with one scoped lifecycle
-- sync-ready path for final pre-composed special-offer composite images.
-- No other media type, purpose, format, or lifecycle path is broadened.

alter table app.media_assets
  drop constraint if exists media_assets_ready_canonical_format_matrix_check;

alter table app.media_assets
  add constraint media_assets_ready_canonical_format_matrix_check
  check (
    state <> 'ready'::app.media_state
    or (
      (
        media_type = 'audio'::app.media_type
        and playback_format = 'mp3'
      )
      or (
        media_type = 'image'::app.media_type
        and purpose = 'lesson_media'::app.media_purpose
        and playback_format in ('jpg', 'png')
      )
      or (
        media_type = 'video'::app.media_type
        and purpose = 'lesson_media'::app.media_purpose
        and playback_format = 'mp4'
      )
      or (
        media_type = 'document'::app.media_type
        and purpose = 'lesson_media'::app.media_purpose
        and playback_format = 'pdf'
      )
      or (
        media_type = 'image'::app.media_type
        and purpose = 'course_cover'::app.media_purpose
        and playback_format = 'jpg'
      )
      or (
        media_type = 'image'::app.media_type
        and purpose = 'profile_media'::app.media_purpose
        and playback_format = 'jpg'
      )
      or (
        media_type = 'image'::app.media_type
        and purpose::text = 'special_offer_composite_image'
        and playback_format = 'jpg'
      )
    )
  );

comment on constraint media_assets_ready_canonical_format_matrix_check on app.media_assets is
  'Canonical ready playback-format matrix. Slot 0022 extends schema-level ready eligibility by exactly one media class: image plus special_offer_composite_image plus jpg. Lifecycle sync-ready support depends on this aligned eligibility; no other media purpose, media type, or playback format is broadened.';

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
  v_playback_format text;
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
      if p_playback_object_path is null or btrim(p_playback_object_path) = '' then
        raise exception 'ready media requires playback_object_path';
      end if;

      if p_playback_format is null or btrim(p_playback_format) = '' then
        raise exception 'ready media requires playback_format';
      end if;

      v_playback_format := btrim(p_playback_format);

      -- Purpose-scoped sync-ready exception aligned with the schema-level
      -- ready-format matrix extension: final special-offer composite images are
      -- already canonical JPG playback outputs and require no further transform.
      if v_asset.purpose::text = 'special_offer_composite_image' then
        if v_asset.media_type <> 'image'::app.media_type then
          raise exception 'ready special-offer composite image media requires image media_type';
        end if;

        if v_asset.state <> 'pending_upload'::app.media_state then
          raise exception 'special-offer composite image media asset % must be pending_upload before ready', p_media_asset_id;
        end if;

        if v_playback_format <> 'jpg' then
          raise exception 'ready special-offer composite image media requires playback_format jpg';
        end if;

      elsif v_asset.state <> 'processing'::app.media_state then
        raise exception 'media asset % must be processing before ready', p_media_asset_id;
      end if;

      if v_asset.media_type = 'audio'::app.media_type
         and v_playback_format <> 'mp3' then
        raise exception 'ready audio media requires playback_format mp3';
      end if;

      if v_asset.media_type = 'image'::app.media_type
         and v_asset.purpose = 'lesson_media'::app.media_purpose
         and v_playback_format not in ('jpg', 'png') then
        raise exception 'ready lesson image media requires playback_format jpg or png';
      end if;

      if v_asset.media_type = 'video'::app.media_type
         and v_asset.purpose = 'lesson_media'::app.media_purpose
         and v_playback_format <> 'mp4' then
        raise exception 'ready lesson video media requires playback_format mp4';
      end if;

      if v_asset.media_type = 'document'::app.media_type
         and v_asset.purpose = 'lesson_media'::app.media_purpose
         and v_playback_format <> 'pdf' then
        raise exception 'ready lesson document media requires playback_format pdf';
      end if;

      if v_asset.media_type = 'image'::app.media_type
         and v_asset.purpose = 'course_cover'::app.media_purpose
         and v_playback_format <> 'jpg' then
        raise exception 'ready course cover media requires playback_format jpg';
      end if;

      if v_asset.media_type = 'image'::app.media_type
         and v_asset.purpose = 'profile_media'::app.media_purpose
         and v_playback_format <> 'jpg' then
        raise exception 'ready profile media image requires playback_format jpg';
      end if;

      if not (
        (
          v_asset.media_type = 'audio'::app.media_type
          and v_playback_format = 'mp3'
        )
        or (
          v_asset.media_type = 'image'::app.media_type
          and v_asset.purpose = 'lesson_media'::app.media_purpose
          and v_playback_format in ('jpg', 'png')
        )
        or (
          v_asset.media_type = 'video'::app.media_type
          and v_asset.purpose = 'lesson_media'::app.media_purpose
          and v_playback_format = 'mp4'
        )
        or (
          v_asset.media_type = 'document'::app.media_type
          and v_asset.purpose = 'lesson_media'::app.media_purpose
          and v_playback_format = 'pdf'
        )
        or (
          v_asset.media_type = 'image'::app.media_type
          and v_asset.purpose = 'course_cover'::app.media_purpose
          and v_playback_format = 'jpg'
        )
        or (
          v_asset.media_type = 'image'::app.media_type
          and v_asset.purpose = 'profile_media'::app.media_purpose
          and v_playback_format = 'jpg'
        )
        or (
          v_asset.media_type = 'image'::app.media_type
          and v_asset.purpose::text = 'special_offer_composite_image'
          and v_playback_format = 'jpg'
        )
      ) then
        raise exception 'ready media violates canonical playback format matrix';
      end if;

      update app.media_assets
         set state = 'ready'::app.media_state,
             playback_object_path = btrim(p_playback_object_path),
             playback_format = v_playback_format,
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

comment on function app.canonical_worker_transition_media_asset(
  uuid,
  app.media_state,
  text,
  text,
  text,
  timestamptz,
  timestamptz
) is
  'Canonical worker-owned media lifecycle transition function. Slot 0022 aligns one schema-level ready-format extension with one scoped sync-ready path: only image plus special_offer_composite_image plus jpg may transition pending_upload to ready. All other media classes remain on the uploaded to processing to ready path.';
