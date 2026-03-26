create table "app"."lessons" (
  "id" uuid not null default gen_random_uuid(),
  "title" text not null,
  "content_markdown" text,
  "video_url" text,
  "duration_seconds" integer,
  "is_intro" boolean not null default false,
  "position" integer not null default 0,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "price_amount_cents" integer not null default 0,
  "price_currency" text not null default 'sek'::text,
  "course_id" uuid not null
);

alter table "app"."lessons" enable row level security;

create unique index "lessons_pkey" on "app"."lessons" using btree ("id");

create unique index "lessons_course_id_position_key" on "app"."lessons" using btree ("course_id", "position");

create index "idx_lessons_course" on "app"."lessons" using btree ("course_id");

alter table "app"."lessons"
  add constraint "lessons_pkey" primary key using index "lessons_pkey";

alter table "app"."lessons"
  add constraint "lessons_course_id_fkey"
  foreign key ("course_id") references "app"."courses" ("id") not valid;

alter table "app"."lessons"
  validate constraint "lessons_course_id_fkey";

alter table "app"."lessons"
  add constraint "lessons_course_id_position_key" unique using index "lessons_course_id_position_key";

create trigger "trg_lessons_touch"
before update on "app"."lessons"
for each row
execute function "app"."set_updated_at"();

grant delete on table "app"."lessons" to "anon";
grant insert on table "app"."lessons" to "anon";
grant select on table "app"."lessons" to "anon";
grant update on table "app"."lessons" to "anon";
grant delete on table "app"."lessons" to "authenticated";
grant insert on table "app"."lessons" to "authenticated";
grant select on table "app"."lessons" to "authenticated";
grant update on table "app"."lessons" to "authenticated";
grant delete on table "app"."lessons" to "service_role";
grant insert on table "app"."lessons" to "service_role";
grant select on table "app"."lessons" to "service_role";
grant update on table "app"."lessons" to "service_role";

create policy "lessons_select"
on "app"."lessons"
as permissive
for select
to public
using (
  (
    app.is_admin(auth.uid())
  )
  or (
    exists (
      select 1
      from app.enrollments e
      join app.courses c on c.id = e.course_id
      where e.user_id = auth.uid()
        and e.course_id = lessons.course_id
        and c.id = lessons.course_id
    )
  )
);

create policy "lessons_service_role"
on "app"."lessons"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "lessons_write"
on "app"."lessons"
as permissive
for all
to authenticated
using (
  (
    app.is_admin(auth.uid())
  )
  or (
    exists (
      select 1
      from app.courses c
      where c.id = lessons.course_id
        and c.created_by = auth.uid()
    )
  )
)
with check (
  (
    app.is_admin(auth.uid())
  )
  or (
    exists (
      select 1
      from app.courses c
      where c.id = lessons.course_id
        and c.created_by = auth.uid()
    )
  )
);

create policy "service_role_full_access"
on "app"."lessons"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
