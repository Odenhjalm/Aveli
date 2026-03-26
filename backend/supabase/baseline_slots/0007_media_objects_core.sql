create table "app"."media_objects" (
  "id" uuid not null default gen_random_uuid(),
  "owner_id" uuid,
  "storage_path" text not null,
  "storage_bucket" text not null,
  "content_type" text,
  "byte_size" bigint not null default 0,
  "checksum" text,
  "original_name" text,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

alter table "app"."media_objects" enable row level security;

create unique index "media_objects_pkey" on "app"."media_objects" using btree ("id");

create unique index "media_objects_storage_path_storage_bucket_key"
  on "app"."media_objects" using btree ("storage_path", "storage_bucket");

create index "idx_media_owner" on "app"."media_objects" using btree ("owner_id");

alter table "app"."media_objects"
  add constraint "media_objects_pkey" primary key using index "media_objects_pkey";

alter table "app"."media_objects"
  add constraint "media_objects_owner_id_fkey"
  foreign key ("owner_id") references "app"."profiles" ("user_id") on delete set null not valid;

alter table "app"."media_objects"
  validate constraint "media_objects_owner_id_fkey";

alter table "app"."media_objects"
  add constraint "media_objects_storage_path_storage_bucket_key"
  unique using index "media_objects_storage_path_storage_bucket_key";

grant delete on table "app"."media_objects" to "anon";
grant insert on table "app"."media_objects" to "anon";
grant select on table "app"."media_objects" to "anon";
grant update on table "app"."media_objects" to "anon";
grant delete on table "app"."media_objects" to "authenticated";
grant insert on table "app"."media_objects" to "authenticated";
grant select on table "app"."media_objects" to "authenticated";
grant update on table "app"."media_objects" to "authenticated";
grant delete on table "app"."media_objects" to "service_role";
grant insert on table "app"."media_objects" to "service_role";
grant select on table "app"."media_objects" to "service_role";
grant update on table "app"."media_objects" to "service_role";

create policy "media_owner_rw"
on "app"."media_objects"
as permissive
for all
to authenticated
using ((("owner_id" = auth.uid()) or app.is_admin(auth.uid())))
with check ((("owner_id" = auth.uid()) or app.is_admin(auth.uid())));

create policy "media_service_role"
on "app"."media_objects"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "service_role_full_access"
on "app"."media_objects"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
