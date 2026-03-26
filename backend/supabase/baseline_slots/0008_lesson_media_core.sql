create table "app"."lesson_media" (
  "id" uuid not null default gen_random_uuid(),
  "lesson_id" uuid not null,
  "media_id" uuid not null,
  "kind" text not null,
  "position" integer not null default 0,
  "created_at" timestamp with time zone not null default now()
);

alter table "app"."lesson_media" enable row level security;

create unique index "lesson_media_pkey" on "app"."lesson_media" using btree ("id");

create unique index "lesson_media_lesson_id_position_key"
  on "app"."lesson_media" using btree ("lesson_id", "position");

alter table "app"."lesson_media"
  add constraint "lesson_media_pkey" primary key using index "lesson_media_pkey";

alter table "app"."lesson_media"
  add constraint "lesson_media_kind_check"
  check (
    "kind" = any (
      array[
        'video'::text,
        'audio'::text,
        'image'::text,
        'pdf'::text,
        'other'::text
      ]
    )
  ) not valid;

alter table "app"."lesson_media"
  validate constraint "lesson_media_kind_check";

alter table "app"."lesson_media"
  add constraint "lesson_media_lesson_id_fkey"
  foreign key ("lesson_id") references "app"."lessons" ("id") on delete cascade not valid;

alter table "app"."lesson_media"
  validate constraint "lesson_media_lesson_id_fkey";

alter table "app"."lesson_media"
  add constraint "lesson_media_media_id_fkey"
  foreign key ("media_id") references "app"."media_objects" ("id") not valid;

alter table "app"."lesson_media"
  validate constraint "lesson_media_media_id_fkey";

alter table "app"."lesson_media"
  add constraint "lesson_media_lesson_id_position_key"
  unique using index "lesson_media_lesson_id_position_key";

grant delete on table "app"."lesson_media" to "anon";
grant insert on table "app"."lesson_media" to "anon";
grant select on table "app"."lesson_media" to "anon";
grant update on table "app"."lesson_media" to "anon";
grant delete on table "app"."lesson_media" to "authenticated";
grant insert on table "app"."lesson_media" to "authenticated";
grant select on table "app"."lesson_media" to "authenticated";
grant update on table "app"."lesson_media" to "authenticated";
grant delete on table "app"."lesson_media" to "service_role";
grant insert on table "app"."lesson_media" to "service_role";
grant select on table "app"."lesson_media" to "service_role";
grant update on table "app"."lesson_media" to "service_role";

create policy "lesson_media_select"
on "app"."lesson_media"
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
      from app.lessons l
      join app.courses c on c.id = l.course_id
      join app.enrollments e on e.course_id = c.id
      where l.id = lesson_media.lesson_id
        and c.id = l.course_id
        and e.user_id = auth.uid()
    )
  )
);

create policy "lesson_media_service_role"
on "app"."lesson_media"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "lesson_media_write"
on "app"."lesson_media"
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
      from app.lessons l
      join app.courses c on c.id = l.course_id
      where l.id = lesson_media.lesson_id
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
      from app.lessons l
      join app.courses c on c.id = l.course_id
      where l.id = lesson_media.lesson_id
        and c.created_by = auth.uid()
    )
  )
);

create policy "service_role_full_access"
on "app"."lesson_media"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
