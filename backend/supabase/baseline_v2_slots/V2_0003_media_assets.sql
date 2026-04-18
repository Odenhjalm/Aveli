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
  constraint media_assets_original_object_path_not_blank_check
    check (btrim(original_object_path) <> ''),
  constraint media_assets_ingest_format_not_blank_check
    check (btrim(ingest_format) <> ''),
  constraint media_assets_processing_attempts_check
    check (processing_attempts >= 0),
  constraint media_assets_ready_playback_object_path_check
    check (
      state <> 'ready'::app.media_state
      or (
        playback_object_path is not null
        and btrim(playback_object_path) <> ''
      )
    ),
  constraint media_assets_playback_format_not_blank_check
    check (
      playback_format is null
      or btrim(playback_format) <> ''
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

create or replace function app.enforce_media_assets_lifecycle_contract()
returns trigger
language plpgsql
set search_path = pg_catalog, app
as $$
declare
  in_worker_context boolean :=
    coalesce(current_setting('app.canonical_worker_function_context', true), '') = 'on';
begin
  if new.id is distinct from old.id
     or new.media_type is distinct from old.media_type
     or new.purpose is distinct from old.purpose
     or new.original_object_path is distinct from old.original_object_path
     or new.ingest_format is distinct from old.ingest_format
     or new.created_at is distinct from old.created_at then
    raise exception 'canonical media identity fields are immutable after insert';
  end if;

  if new.state is distinct from old.state
     or new.playback_object_path is distinct from old.playback_object_path
     or new.playback_format is distinct from old.playback_format
     or new.error_message is distinct from old.error_message
     or new.processing_attempts is distinct from old.processing_attempts
     or new.processing_locked_at is distinct from old.processing_locked_at
     or new.next_retry_at is distinct from old.next_retry_at
     or new.updated_at is distinct from old.updated_at then
    if not in_worker_context then
      raise exception 'media lifecycle fields may be mutated only through the canonical worker context';
    end if;
  end if;

  return new;
end;
$$;

create trigger media_assets_lifecycle_contract
before update on app.media_assets
for each row
execute function app.enforce_media_assets_lifecycle_contract();

comment on function app.enforce_media_assets_lifecycle_contract() is
  'DB-level guard for media identity immutability and canonical worker-only media lifecycle mutations.';

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
