create table app.media_assets (
  id uuid not null default gen_random_uuid(),
  media_type app.media_type not null,
  purpose app.media_purpose not null,
  original_object_path text not null,
  ingest_format text not null,
  playback_object_path text,
  playback_format text,
  state app.media_state not null default 'pending_upload',
  error_message text,
  processing_attempts integer not null default 0,
  processing_locked_at timestamptz,
  next_retry_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint media_assets_pkey primary key (id),
  constraint media_assets_processing_attempts_check
    check (processing_attempts >= 0),
  constraint media_assets_ready_playback_object_path_check
    check (
      state <> 'ready'::app.media_state
      or playback_object_path is not null
    ),
  constraint media_assets_audio_ready_playback_format_check
    check (
      media_type <> 'audio'::app.media_type
      or state <> 'ready'::app.media_state
      or playback_format = 'mp3'
    ),
  constraint media_assets_pending_upload_no_playback_check
    check (
      state <> 'pending_upload'::app.media_state
      or (
        playback_object_path is null
        and playback_format is null
      )
    )
);

create index media_assets_purpose_state_idx
  on app.media_assets (purpose, state);

create index media_assets_worker_scan_idx
  on app.media_assets (state, next_retry_at, processing_locked_at, created_at, id);

comment on table app.media_assets is
  'Canonical media identity and lifecycle table only. Media ownership comes from source relations, not from app.media_assets.';

comment on column app.media_assets.media_type is
  'Canonical media type enum for the asset identity.';

comment on column app.media_assets.purpose is
  'Canonical media purpose enum for the asset lifecycle and placement boundary.';

comment on column app.media_assets.original_object_path is
  'Original storage object coordinate retained as infrastructure metadata, not delivery authority.';

comment on column app.media_assets.playback_object_path is
  'Worker-produced playback object coordinate required only when media is ready.';

comment on column app.media_assets.state is
  'Canonical lifecycle state for media processing and readiness.';

comment on column app.media_assets.processing_attempts is
  'Worker support counter for media processing attempts.';

comment on column app.media_assets.processing_locked_at is
  'Worker support lock timestamp for deterministic processing scans.';

comment on column app.media_assets.next_retry_at is
  'Worker support retry timestamp for deterministic processing scans.';
