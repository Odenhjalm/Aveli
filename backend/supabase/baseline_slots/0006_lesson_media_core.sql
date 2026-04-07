create table app.lesson_media (
  id uuid not null,
  lesson_id uuid not null,
  media_asset_id uuid not null,
  position integer not null,
  constraint lesson_media_pkey primary key (id),
  constraint lesson_media_lesson_id_position_key unique (lesson_id, position),
  constraint lesson_media_position_check check (position >= 1),
  constraint lesson_media_lesson_id_fkey
    foreign key (lesson_id) references app.lessons (id)
);

-- Replay-integrity recovery: the media-asset foreign key is restored only after
-- app.media_assets exists in the strict-order slot chain.
