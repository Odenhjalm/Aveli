create table app.media_assets (
  id uuid not null,
  media_type app.media_type not null,
  purpose app.media_purpose not null,
  original_object_path text not null,
  ingest_format text not null,
  state app.media_state not null,
  constraint media_assets_pkey primary key (id)
);

-- Structural cover linkage only. The core-table phase remains limited to
-- canonical fields, structural references, and local row invariants.
-- Category-based surface rules do not introduce schema fields here, and
-- cross-table business enforcement for media purpose is out of scope.
alter table app.courses
  add constraint courses_cover_media_id_fkey
  foreign key (cover_media_id) references app.media_assets (id);
