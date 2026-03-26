create table "app"."runtime_media" (
  "id" uuid not null default gen_random_uuid(),
  "reference_type" text not null,
  "auth_scope" text not null,
  "fallback_policy" text not null,
  "lesson_media_id" uuid,
  "home_player_upload_id" uuid,
  "teacher_id" uuid,
  "course_id" uuid,
  "lesson_id" uuid,
  "media_asset_id" uuid,
  "media_object_id" uuid,
  "legacy_storage_bucket" text,
  "legacy_storage_path" text,
  "kind" text not null,
  "active" boolean not null default true,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

create unique index "runtime_media_pkey" on "app"."runtime_media" using btree ("id");

create index "idx_runtime_media_asset" on "app"."runtime_media" using btree ("media_asset_id");

create index "idx_runtime_media_course" on "app"."runtime_media" using btree ("course_id");

create index "idx_runtime_media_lesson" on "app"."runtime_media" using btree ("lesson_id");

create index "idx_runtime_media_object" on "app"."runtime_media" using btree ("media_object_id");

create unique index "runtime_media_lesson_media_id_key"
  on "app"."runtime_media" using btree ("lesson_media_id");

alter table "app"."runtime_media"
  add constraint "runtime_media_pkey" primary key using index "runtime_media_pkey";

alter table "app"."runtime_media"
  add constraint "runtime_media_auth_scope_check"
  check (("auth_scope" = 'lesson_course'::text)) not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_auth_scope_check";

alter table "app"."runtime_media"
  add constraint "runtime_media_course_id_fkey"
  foreign key ("course_id") references "app"."courses" ("id") on delete set null not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_course_id_fkey";

alter table "app"."runtime_media"
  add constraint "runtime_media_fallback_policy_check"
  check (
    ("fallback_policy" = any (
      array[
        'never'::text,
        'if_no_ready_asset'::text,
        'legacy_only'::text
      ]
    ))
  ) not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_fallback_policy_check";

alter table "app"."runtime_media"
  add constraint "runtime_media_kind_check"
  check (
    ("kind" = any (
      array[
        'audio'::text,
        'video'::text,
        'image'::text,
        'document'::text,
        'other'::text
      ]
    ))
  ) not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_kind_check";

alter table "app"."runtime_media"
  add constraint "runtime_media_legacy_storage_pair"
  check ((("legacy_storage_path" is null) or ("legacy_storage_bucket" is not null))) not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_legacy_storage_pair";

alter table "app"."runtime_media"
  add constraint "runtime_media_lesson_id_fkey"
  foreign key ("lesson_id") references "app"."lessons" ("id") on delete set null not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_lesson_id_fkey";

alter table "app"."runtime_media"
  add constraint "runtime_media_lesson_media_id_fkey"
  foreign key ("lesson_media_id") references "app"."lesson_media" ("id") on delete cascade not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_lesson_media_id_fkey";

alter table "app"."runtime_media"
  add constraint "runtime_media_lesson_media_id_key"
  unique using index "runtime_media_lesson_media_id_key";

alter table "app"."runtime_media"
  add constraint "runtime_media_lesson_projection_shape"
  check (
    ("lesson_media_id" is not null)
    and ("course_id" is not null)
    and ("lesson_id" is not null)
    and ("home_player_upload_id" is null)
  ) not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_lesson_projection_shape";

alter table "app"."runtime_media"
  add constraint "runtime_media_media_asset_id_fkey"
  foreign key ("media_asset_id") references "app"."media_assets" ("id") on delete set null not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_media_asset_id_fkey";

alter table "app"."runtime_media"
  add constraint "runtime_media_media_object_id_fkey"
  foreign key ("media_object_id") references "app"."media_objects" ("id") on delete set null not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_media_object_id_fkey";

alter table "app"."runtime_media"
  add constraint "runtime_media_reference_type_check"
  check (("reference_type" = 'lesson_media'::text)) not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_reference_type_check";

alter table "app"."runtime_media"
  add constraint "runtime_media_teacher_id_fkey"
  foreign key ("teacher_id") references "app"."profiles" ("user_id") on delete set null not valid;

alter table "app"."runtime_media"
  validate constraint "runtime_media_teacher_id_fkey";

grant delete on table "app"."runtime_media" to "anon";
grant insert on table "app"."runtime_media" to "anon";
grant select on table "app"."runtime_media" to "anon";
grant update on table "app"."runtime_media" to "anon";
grant delete on table "app"."runtime_media" to "authenticated";
grant insert on table "app"."runtime_media" to "authenticated";
grant select on table "app"."runtime_media" to "authenticated";
grant update on table "app"."runtime_media" to "authenticated";
grant delete on table "app"."runtime_media" to "service_role";
grant insert on table "app"."runtime_media" to "service_role";
grant select on table "app"."runtime_media" to "service_role";
grant update on table "app"."runtime_media" to "service_role";
