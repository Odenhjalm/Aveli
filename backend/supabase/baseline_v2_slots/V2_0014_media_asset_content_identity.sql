alter table app.media_assets
  add column file_size bigint,
  add column content_hash text,
  add column content_hash_algorithm text,
  add column content_identity_computed_at timestamptz,
  add column content_identity_error text,
  add constraint media_assets_file_size_nonnegative_check
    check (file_size is null or file_size >= 0),
  add constraint media_assets_content_hash_sha256_format_check
    check (
      content_hash is null
      or content_hash ~ '^[0-9a-f]{64}$'
    ),
  add constraint media_assets_content_hash_algorithm_not_blank_check
    check (
      content_hash_algorithm is null
      or btrim(content_hash_algorithm) <> ''
    );

create index media_assets_content_hash_idx
  on app.media_assets (content_hash)
  where content_hash is not null;

create index media_assets_file_size_idx
  on app.media_assets (file_size)
  where file_size is not null;

create index media_assets_content_identity_idx
  on app.media_assets (content_hash_algorithm, content_hash, file_size)
  where content_hash is not null
    and file_size is not null;

comment on column app.media_assets.file_size is
  'Nullable canonical media identity metadata: source file size in bytes, populated only by an explicit backfill step.';

comment on column app.media_assets.content_hash is
  'Nullable canonical media identity metadata: lowercase SHA256 content hash, populated only by an explicit backfill step.';

comment on column app.media_assets.content_hash_algorithm is
  'Nullable canonical media identity metadata: hash algorithm identifier, for example sha256.';

comment on column app.media_assets.content_identity_computed_at is
  'Nullable timestamp recording when file_size and content_hash were computed.';

comment on column app.media_assets.content_identity_error is
  'Nullable non-authoritative backfill error detail for rows whose media identity metadata could not be computed.';
