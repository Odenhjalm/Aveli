create type "app"."enrollment_source" as enum ('free_intro', 'purchase', 'membership', 'grant');

create table "app"."enrollments" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "course_id" uuid not null,
  "status" text not null default 'active'::text,
  "source" app.enrollment_source not null default 'purchase'::app.enrollment_source,
  "created_at" timestamp with time zone not null default now()
);

alter table "app"."enrollments" enable row level security;

create unique index "enrollments_pkey" on "app"."enrollments" using btree ("id");

create unique index "enrollments_user_id_course_id_key" on "app"."enrollments" using btree ("user_id", "course_id");

create index "idx_enrollments_course" on "app"."enrollments" using btree ("course_id");

create index "idx_enrollments_user" on "app"."enrollments" using btree ("user_id");

alter table "app"."enrollments"
  add constraint "enrollments_pkey" primary key using index "enrollments_pkey";

alter table "app"."enrollments"
  add constraint "enrollments_course_id_fkey"
  foreign key ("course_id") references "app"."courses" ("id") on delete cascade not valid;

alter table "app"."enrollments"
  validate constraint "enrollments_course_id_fkey";

alter table "app"."enrollments"
  add constraint "enrollments_user_id_course_id_key" unique using index "enrollments_user_id_course_id_key";

alter table "app"."enrollments"
  add constraint "enrollments_user_id_fkey"
  foreign key ("user_id") references "app"."profiles" ("user_id") on delete cascade not valid;

alter table "app"."enrollments"
  validate constraint "enrollments_user_id_fkey";

grant delete on table "app"."enrollments" to "anon";
grant insert on table "app"."enrollments" to "anon";
grant select on table "app"."enrollments" to "anon";
grant update on table "app"."enrollments" to "anon";
grant delete on table "app"."enrollments" to "authenticated";
grant insert on table "app"."enrollments" to "authenticated";
grant select on table "app"."enrollments" to "authenticated";
grant update on table "app"."enrollments" to "authenticated";
grant delete on table "app"."enrollments" to "service_role";
grant insert on table "app"."enrollments" to "service_role";
grant select on table "app"."enrollments" to "service_role";
grant update on table "app"."enrollments" to "service_role";

create policy "enrollments_user"
on "app"."enrollments"
as permissive
for all
to authenticated
using ((("user_id" = auth.uid()) or app.is_admin(auth.uid())))
with check ((("user_id" = auth.uid()) or app.is_admin(auth.uid())));

create policy "enrollments_service"
on "app"."enrollments"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "service_role_full_access"
on "app"."enrollments"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
