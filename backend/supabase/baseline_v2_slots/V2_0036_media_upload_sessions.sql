create table app.media_upload_sessions (
  id uuid primary key default gen_random_uuid(),
  media_asset_id uuid not null references app.media_assets(id) on delete cascade,
  owner_user_id uuid not null,
  state text not null default 'open',
  total_bytes bigint not null,
  content_type text not null,
  chunk_size integer not null,
  expected_chunks integer not null,
  received_bytes bigint not null default 0,
  expires_at timestamptz not null,
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint media_upload_sessions_state_check
    check (state in ('open', 'finalized', 'expired')),
  constraint media_upload_sessions_total_bytes_check check (total_bytes > 0),
  constraint media_upload_sessions_content_type_check
    check (length(btrim(content_type)) > 0),
  constraint media_upload_sessions_chunk_size_check check (chunk_size > 0),
  constraint media_upload_sessions_expected_chunks_check check (expected_chunks > 0),
  constraint media_upload_sessions_received_bytes_check check (received_bytes >= 0),
  constraint media_upload_sessions_received_lte_total_check
    check (received_bytes <= total_bytes),
  constraint media_upload_sessions_finalized_at_check
    check ((state = 'finalized') = (finalized_at is not null))
);

create index media_upload_sessions_media_asset_owner_idx
  on app.media_upload_sessions (media_asset_id, owner_user_id, created_at desc);

create index media_upload_sessions_expiration_idx
  on app.media_upload_sessions (state, expires_at);

create table app.media_upload_chunks (
  id uuid primary key default gen_random_uuid(),
  upload_session_id uuid not null references app.media_upload_sessions(id) on delete cascade,
  media_asset_id uuid not null references app.media_assets(id) on delete cascade,
  chunk_index integer not null,
  byte_start bigint not null,
  byte_end bigint not null,
  size_bytes integer not null,
  sha256 text not null,
  spool_object_path text not null,
  created_at timestamptz not null default now(),
  constraint media_upload_chunks_chunk_index_check check (chunk_index >= 0),
  constraint media_upload_chunks_byte_start_check check (byte_start >= 0),
  constraint media_upload_chunks_byte_end_check check (byte_end >= 0),
  constraint media_upload_chunks_size_bytes_check check (size_bytes > 0),
  constraint media_upload_chunks_sha256_check
    check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint media_upload_chunks_spool_object_path_check
    check (length(btrim(spool_object_path)) > 0),
  constraint media_upload_chunks_range_check check (byte_end >= byte_start),
  constraint media_upload_chunks_size_matches_range_check
    check ((byte_end - byte_start + 1) = size_bytes),
  unique (upload_session_id, chunk_index)
);

create index media_upload_chunks_session_order_idx
  on app.media_upload_chunks (upload_session_id, chunk_index);

create index media_upload_chunks_media_asset_idx
  on app.media_upload_chunks (media_asset_id, created_at desc);
