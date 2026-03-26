create table "app"."media_assets" (
  "id" uuid not null default gen_random_uuid(),
  "owner_id" uuid,
  "course_id" uuid,
  "lesson_id" uuid,
  "media_type" text not null,
  "ingest_format" text not null,
  "original_object_path" text not null,
  "original_content_type" text,
  "original_filename" text,
  "original_size_bytes" bigint,
  "storage_bucket" text not null default 'course-media'::text,
  "streaming_object_path" text,
  "streaming_format" text,
  "duration_seconds" integer,
  "codec" text,
  "state" text not null,
  "error_message" text,
  "processing_attempts" integer not null default 0,
  "processing_locked_at" timestamp with time zone,
  "next_retry_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "purpose" text not null default 'lesson_audio'::text,
  "streaming_storage_bucket" text
);

create unique index "media_assets_pkey" on "app"."media_assets" using btree ("id");

create index "idx_media_assets_course" on "app"."media_assets" using btree ("course_id");

create index "idx_media_assets_course_cover"
  on "app"."media_assets" using btree ("course_id")
  where ("purpose" = 'course_cover'::text);

create index "idx_media_assets_lesson" on "app"."media_assets" using btree ("lesson_id");

create index "idx_media_assets_next_retry" on "app"."media_assets" using btree ("next_retry_at");

create index "idx_media_assets_purpose" on "app"."media_assets" using btree ("purpose");

create index "idx_media_assets_state" on "app"."media_assets" using btree ("state");

alter table "app"."media_assets"
  add constraint "media_assets_pkey" primary key using index "media_assets_pkey";

alter table "app"."media_assets"
  add constraint "media_assets_course_id_fkey"
  foreign key ("course_id") references "app"."courses" ("id") on delete set null not valid;

alter table "app"."media_assets"
  validate constraint "media_assets_course_id_fkey";

alter table "app"."media_assets"
  add constraint "media_assets_lesson_id_fkey"
  foreign key ("lesson_id") references "app"."lessons" ("id") on delete set null not valid;

alter table "app"."media_assets"
  validate constraint "media_assets_lesson_id_fkey";

alter table "app"."media_assets"
  add constraint "media_assets_media_type_check"
  check (("media_type" = any (array['audio'::text, 'document'::text, 'image'::text, 'video'::text]))) not valid;

alter table "app"."media_assets"
  validate constraint "media_assets_media_type_check";

alter table "app"."media_assets"
  add constraint "media_assets_owner_id_fkey"
  foreign key ("owner_id") references "app"."profiles" ("user_id") on delete set null not valid;

alter table "app"."media_assets"
  validate constraint "media_assets_owner_id_fkey";

alter table "app"."media_assets"
  add constraint "media_assets_purpose_check"
  check (("purpose" = any (array['lesson_audio'::text, 'course_cover'::text, 'home_player_audio'::text, 'lesson_media'::text]))) not valid;

alter table "app"."media_assets"
  validate constraint "media_assets_purpose_check";

alter table "app"."media_assets"
  add constraint "media_assets_state_check"
  check (("state" = any (array['pending_upload'::text, 'uploaded'::text, 'processing'::text, 'ready'::text, 'failed'::text]))) not valid;

alter table "app"."media_assets"
  validate constraint "media_assets_state_check";

grant delete on table "app"."media_assets" to "anon";
grant insert on table "app"."media_assets" to "anon";
grant select on table "app"."media_assets" to "anon";
grant update on table "app"."media_assets" to "anon";
grant delete on table "app"."media_assets" to "authenticated";
grant insert on table "app"."media_assets" to "authenticated";
grant select on table "app"."media_assets" to "authenticated";
grant update on table "app"."media_assets" to "authenticated";
grant delete on table "app"."media_assets" to "service_role";
grant insert on table "app"."media_assets" to "service_role";
grant select on table "app"."media_assets" to "service_role";
grant update on table "app"."media_assets" to "service_role";

alter table "app"."courses"
  add constraint "courses_cover_media_id_fkey"
  foreign key ("cover_media_id") references "app"."media_assets" ("id") on delete set null not valid;

alter table "app"."courses"
  validate constraint "courses_cover_media_id_fkey";
