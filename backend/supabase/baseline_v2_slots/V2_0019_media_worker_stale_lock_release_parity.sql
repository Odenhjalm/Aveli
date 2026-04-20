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
             'profile_media'::app.media_purpose,
             'lesson_media'::app.media_purpose
           )
         )
         or (
           media_type in (
             'video'::app.media_type,
             'document'::app.media_type
           )
           and purpose = 'lesson_media'::app.media_purpose
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

revoke all on function app.canonical_worker_release_stale_media_asset_locks(
  integer,
  timestamptz
) from public;

comment on function app.canonical_worker_release_stale_media_asset_locks(
  integer,
  timestamptz
) is
  'Canonical worker authority for releasing stale media processing locks. Release eligibility must match the active worker fetch/lock media class set.';
