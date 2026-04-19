create or replace function app.canonical_worker_requeue_failed_media_asset(
  p_media_asset_id uuid,
  p_requeued_at timestamptz default clock_timestamp()
) returns app.media_assets
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
begin
  if p_media_asset_id is null then
    raise exception 'media worker requeue requires media_asset_id';
  end if;

  if p_requeued_at is null then
    raise exception 'media worker requeue requires requeued_at';
  end if;

  raise exception 'failed media requeue is not authorized under current lifecycle contract';
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
  'Blocked compatibility surface. Failed media is terminal under the current lifecycle contract.';
