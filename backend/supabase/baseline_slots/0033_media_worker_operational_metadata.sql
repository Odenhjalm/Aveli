alter table app.media_assets
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists error_message text,
  add column if not exists processing_attempts integer not null default 0,
  add column if not exists processing_locked_at timestamptz,
  add column if not exists next_retry_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'media_assets_processing_attempts_check'
  ) then
    alter table app.media_assets
      add constraint media_assets_processing_attempts_check
      check (processing_attempts >= 0);
  end if;
end
$$;

create index if not exists media_assets_worker_queue_idx
  on app.media_assets (
    state,
    next_retry_at,
    processing_locked_at,
    created_at,
    updated_at,
    id
  )
  where (
    media_type = 'audio'::app.media_type
    or (
      media_type = 'image'::app.media_type
      and purpose = 'course_cover'::app.media_purpose
    )
  );

create index if not exists media_assets_worker_processing_lock_idx
  on app.media_assets (processing_locked_at)
  where state = 'processing'::app.media_state
    and processing_locked_at is not null;

comment on column app.media_assets.processing_attempts is
  'Operational retry counter for the canonical media worker. Not public media contract truth.';

comment on column app.media_assets.processing_locked_at is
  'Operational lock timestamp for the canonical media worker. Not public media contract truth.';

comment on column app.media_assets.next_retry_at is
  'Operational retry schedule timestamp for the canonical media worker. Not public media contract truth.';

comment on column app.media_assets.error_message is
  'Operational failure detail for the canonical media worker. Not public media contract truth.';
