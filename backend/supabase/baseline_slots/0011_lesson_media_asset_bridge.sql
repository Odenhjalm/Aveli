alter table "app"."lesson_media"
  alter column "media_id" drop not null;

alter table "app"."lesson_media"
  add column "media_asset_id" uuid;

alter table "app"."lesson_media"
  add column "storage_path" text;

alter table "app"."lesson_media"
  add column "storage_bucket" text not null default 'lesson-media'::text;

alter table "app"."lesson_media"
  add column "duration_seconds" integer;

alter table "app"."lesson_media"
  add constraint "lesson_media_media_asset_id_fkey"
  foreign key ("media_asset_id") references "app"."media_assets" ("id") on delete set null not valid;

alter table "app"."lesson_media"
  validate constraint "lesson_media_media_asset_id_fkey";

alter table "app"."lesson_media"
  add constraint "lesson_media_path_or_object"
  check (
    ("media_id" is not null)
    or ("storage_path" is not null)
    or ("media_asset_id" is not null)
  ) not valid;

alter table "app"."lesson_media"
  validate constraint "lesson_media_path_or_object";
