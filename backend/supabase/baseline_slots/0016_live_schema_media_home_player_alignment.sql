alter table "app"."profiles"
  add column "onboarding_state" text;

alter table "app"."profiles"
  add constraint "profiles_onboarding_state_check"
  check (
    (
      "onboarding_state" is null
    ) or (
      "onboarding_state" = any (
        array[
          'registered_unverified'::text,
          'verified_unpaid'::text,
          'access_active_profile_incomplete'::text,
          'access_active_profile_complete'::text,
          'welcomed'::text
        ]
      )
    )
  );

create index "idx_profiles_onboarding_state"
  on "app"."profiles" using btree ("onboarding_state");

alter table "app"."profiles"
  add constraint "profiles_avatar_media_id_fkey"
  foreign key ("avatar_media_id") references "app"."media_objects" ("id");

comment on table "app"."profiles"
  is 'RLS placeholder: allow owners + admins to read/write their profile rows when Supabase is enabled.';

create or replace function "app"."current_test_session_id"()
returns uuid
language plpgsql
stable
as $function$
declare
  raw_value text;
begin
  raw_value := nullif(current_setting('app.test_session_id', true), '');
  if raw_value is null then
    return null;
  end if;

  return raw_value::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$function$;


create or replace function "app"."is_test_row_visible"(
  row_is_test boolean,
  row_test_session_id uuid
)
returns boolean
language sql
stable
as $function$
  select
    coalesce(row_is_test, false) = false
    or row_test_session_id = app.current_test_session_id()
$function$;


create or replace function "app"."apply_test_row_defaults"()
returns trigger
language plpgsql
as $function$
declare
  current_session_id uuid;
begin
  current_session_id := app.current_test_session_id();

  if tg_op = 'INSERT' then
    if new.test_session_id is null and current_session_id is not null then
      new.test_session_id := current_session_id;
    end if;

    if new.test_session_id is not null then
      new.is_test := true;
    end if;
  elsif tg_op = 'UPDATE' then
    if coalesce(old.is_test, false) then
      new.is_test := true;
      new.test_session_id := coalesce(new.test_session_id, old.test_session_id);
    elsif new.test_session_id is not null then
      new.is_test := true;
    end if;
  end if;

  if coalesce(new.is_test, false) then
    if new.test_session_id is null then
      if current_session_id is not null then
        new.test_session_id := current_session_id;
      else
        raise exception
          'Test rows on %.% require test_session_id',
          tg_table_schema,
          tg_table_name
          using errcode = '23514';
      end if;
    end if;
  else
    new.test_session_id := null;
  end if;

  return new;
end;
$function$;

alter table "app"."courses"
  add column "is_test" boolean not null default false;

alter table "app"."courses"
  add column "test_session_id" uuid;

alter table "app"."courses"
  add constraint "courses_test_session_consistency"
  check (
    (
      coalesce("is_test", false) = false
      and "test_session_id" is null
    ) or (
      coalesce("is_test", false) = true
      and "test_session_id" is not null
    )
  );

create index "courses_slug_idx" on "app"."courses" using btree ("slug");

create index "idx_courses_test_session"
  on "app"."courses" using btree ("test_session_id")
  where ("is_test" = true);

drop trigger if exists "trg_courses_apply_test_row_defaults" on "app"."courses";

create trigger "trg_courses_apply_test_row_defaults"
before insert or update of "is_test", "test_session_id" on "app"."courses"
for each row
execute function "app"."apply_test_row_defaults"();

comment on table "app"."courses"
  is 'RLS placeholder: course authors (created_by) + admins may manage records; public read for published courses.';

drop policy if exists "courses_enrolled_read" on "app"."courses";

alter table "app"."lessons"
  add column "is_test" boolean not null default false;

alter table "app"."lessons"
  add column "test_session_id" uuid;

alter table "app"."lessons"
  drop constraint "lessons_course_id_fkey";

alter table "app"."lessons"
  add constraint "lessons_course_id_fkey"
  foreign key ("course_id") references "app"."courses" ("id") on delete cascade;

alter table "app"."lessons"
  add constraint "lessons_test_session_consistency"
  check (
    (
      coalesce("is_test", false) = false
      and "test_session_id" is null
    ) or (
      coalesce("is_test", false) = true
      and "test_session_id" is not null
    )
  );

create index "idx_lessons_test_session"
  on "app"."lessons" using btree ("test_session_id")
  where ("is_test" = true);

drop trigger if exists "trg_lessons_apply_test_row_defaults" on "app"."lessons";

create trigger "trg_lessons_apply_test_row_defaults"
before insert or update of "is_test", "test_session_id" on "app"."lessons"
for each row
execute function "app"."apply_test_row_defaults"();

drop policy if exists "lessons_select" on "app"."lessons";
drop policy if exists "lessons_service_role" on "app"."lessons";
drop policy if exists "lessons_write" on "app"."lessons";

create policy "lessons_select"
on "app"."lessons"
as permissive
for select
to authenticated
using (
  exists (
    select 1
    from app.courses c
    where c.id = lessons.course_id
      and (
        c.created_by = auth.uid()
        or app.is_admin(auth.uid())
        or (c.is_published and lessons.is_intro = true)
        or exists (
          select 1
          from app.enrollments e
          where e.course_id = c.id
            and e.user_id = auth.uid()
        )
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
  exists (
    select 1
    from app.courses c
    where c.id = lessons.course_id
      and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
  )
)
with check (
  exists (
    select 1
    from app.courses c
    where c.id = lessons.course_id
      and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
  )
);

comment on table "app"."lessons"
  is 'RLS placeholder: restrict lesson access to course owners and enrolled users once RLS is enabled.';

drop policy if exists "enrollments_user" on "app"."enrollments";

create policy "enrollments_user"
on "app"."enrollments"
as permissive
for all
to authenticated
using (
  (
    "user_id" = auth.uid()
  ) or app.is_admin(auth.uid()) or exists (
    select 1
    from app.courses c
    where c.id = enrollments.course_id
      and c.created_by = auth.uid()
  )
)
with check (
  ("user_id" = auth.uid()) or app.is_admin(auth.uid())
);

alter table "app"."lesson_media"
  add column "is_test" boolean not null default false;

alter table "app"."lesson_media"
  add column "test_session_id" uuid;

alter table "app"."lesson_media"
  drop constraint "lesson_media_media_id_fkey";

alter table "app"."lesson_media"
  add constraint "lesson_media_media_id_fkey"
  foreign key ("media_id") references "app"."media_objects" ("id") on delete set null;

alter table "app"."lesson_media"
  add constraint "lesson_media_test_session_consistency"
  check (
    (
      coalesce("is_test", false) = false
      and "test_session_id" is null
    ) or (
      coalesce("is_test", false) = true
      and "test_session_id" is not null
    )
  );

create index "idx_lesson_media_asset"
  on "app"."lesson_media" using btree ("media_asset_id");

create index "idx_lesson_media_lesson"
  on "app"."lesson_media" using btree ("lesson_id");

create index "idx_lesson_media_media"
  on "app"."lesson_media" using btree ("media_id");

create index "idx_lesson_media_test_session"
  on "app"."lesson_media" using btree ("test_session_id")
  where ("is_test" = true);

drop trigger if exists "trg_lesson_media_apply_test_row_defaults" on "app"."lesson_media";

create trigger "trg_lesson_media_apply_test_row_defaults"
before insert or update of "is_test", "test_session_id" on "app"."lesson_media"
for each row
execute function "app"."apply_test_row_defaults"();

drop policy if exists "lesson_media_select" on "app"."lesson_media";
drop policy if exists "lesson_media_service_role" on "app"."lesson_media";
drop policy if exists "lesson_media_service" on "app"."lesson_media";
drop policy if exists "lesson_media_write" on "app"."lesson_media";

create policy "lesson_media_select"
on "app"."lesson_media"
as permissive
for select
to authenticated
using (
  exists (
    select 1
    from app.lessons l
    join app.courses c on c.id = l.course_id
    where l.id = lesson_media.lesson_id
      and (
        c.created_by = auth.uid()
        or app.is_admin(auth.uid())
        or (c.is_published and l.is_intro = true)
        or exists (
          select 1
          from app.enrollments e
          where e.course_id = c.id
            and e.user_id = auth.uid()
        )
      )
  )
);

create policy "lesson_media_service"
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
  exists (
    select 1
    from app.lessons l
    join app.courses c on c.id = l.course_id
    where l.id = lesson_media.lesson_id
      and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
  )
)
with check (
  exists (
    select 1
    from app.lessons l
    join app.courses c on c.id = l.course_id
    where l.id = lesson_media.lesson_id
      and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
  )
);

alter table "app"."media_assets"
  add column "is_test" boolean not null default false;

alter table "app"."media_assets"
  add column "test_session_id" uuid;

alter table "app"."media_assets"
  add constraint "media_assets_test_session_consistency"
  check (
    (
      coalesce("is_test", false) = false
      and "test_session_id" is null
    ) or (
      coalesce("is_test", false) = true
      and "test_session_id" is not null
    )
  );

create index "idx_media_assets_test_session"
  on "app"."media_assets" using btree ("test_session_id")
  where ("is_test" = true);

drop trigger if exists "trg_media_assets_apply_test_row_defaults" on "app"."media_assets";

create trigger "trg_media_assets_apply_test_row_defaults"
before insert or update of "is_test", "test_session_id" on "app"."media_assets"
for each row
execute function "app"."apply_test_row_defaults"();

create or replace function "app"."touch_home_player_course_links"()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;


create or replace function "app"."touch_home_player_uploads"()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;


create table "app"."home_player_course_links" (
  "id" uuid not null default gen_random_uuid(),
  "teacher_id" uuid not null,
  "lesson_media_id" uuid,
  "title" text not null,
  "course_title_snapshot" text not null default ''::text,
  "enabled" boolean not null default true,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

comment on table "app"."home_player_course_links"
  is 'Explicit course-media links for the Home player (no file ownership).';

create unique index "home_player_course_links_pkey"
  on "app"."home_player_course_links" using btree ("id");

create unique index "home_player_course_links_teacher_id_lesson_media_id_key"
  on "app"."home_player_course_links" using btree ("teacher_id", "lesson_media_id");

create index "idx_home_player_course_links_teacher_created"
  on "app"."home_player_course_links" using btree ("teacher_id", "created_at" desc);

alter table "app"."home_player_course_links"
  add constraint "home_player_course_links_pkey"
  primary key using index "home_player_course_links_pkey";

alter table "app"."home_player_course_links"
  add constraint "home_player_course_links_teacher_id_lesson_media_id_key"
  unique using index "home_player_course_links_teacher_id_lesson_media_id_key";

alter table "app"."home_player_course_links"
  add constraint "home_player_course_links_lesson_media_id_fkey"
  foreign key ("lesson_media_id") references "app"."lesson_media" ("id") on delete set null;

alter table "app"."home_player_course_links"
  add constraint "home_player_course_links_teacher_id_fkey"
  foreign key ("teacher_id") references "app"."profiles" ("user_id") on delete cascade;

alter table "app"."home_player_course_links" enable row level security;

grant delete on table "app"."home_player_course_links" to "anon";
grant insert on table "app"."home_player_course_links" to "anon";
grant select on table "app"."home_player_course_links" to "anon";
grant update on table "app"."home_player_course_links" to "anon";
grant delete on table "app"."home_player_course_links" to "authenticated";
grant insert on table "app"."home_player_course_links" to "authenticated";
grant select on table "app"."home_player_course_links" to "authenticated";
grant update on table "app"."home_player_course_links" to "authenticated";
grant delete on table "app"."home_player_course_links" to "service_role";
grant insert on table "app"."home_player_course_links" to "service_role";
grant select on table "app"."home_player_course_links" to "service_role";
grant update on table "app"."home_player_course_links" to "service_role";

create policy "home_player_course_links_owner"
on "app"."home_player_course_links"
as permissive
for all
to authenticated
using ((("teacher_id" = auth.uid()) or app.is_admin(auth.uid())))
with check ((("teacher_id" = auth.uid()) or app.is_admin(auth.uid())));

drop trigger if exists "trg_home_player_course_links_touch" on "app"."home_player_course_links";

create trigger "trg_home_player_course_links_touch"
before update on "app"."home_player_course_links"
for each row
execute function "app"."touch_home_player_course_links"();

create table "app"."home_player_uploads" (
  "id" uuid not null default gen_random_uuid(),
  "teacher_id" uuid not null,
  "media_id" uuid,
  "title" text not null,
  "kind" text not null,
  "active" boolean not null default true,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "media_asset_id" uuid,
  constraint "home_player_uploads_kind_check"
    check (("kind" = any (array['audio'::text, 'video'::text]))),
  constraint "home_player_uploads_media_ref_check"
    check ((("media_id" is null) <> ("media_asset_id" is null)))
);

comment on table "app"."home_player_uploads"
  is 'Teacher-owned uploads dedicated to the Home player (independent of courses).';

create unique index "home_player_uploads_pkey"
  on "app"."home_player_uploads" using btree ("id");

create index "idx_home_player_uploads_media"
  on "app"."home_player_uploads" using btree ("media_id");

create index "idx_home_player_uploads_media_asset"
  on "app"."home_player_uploads" using btree ("media_asset_id");

create index "idx_home_player_uploads_teacher_created"
  on "app"."home_player_uploads" using btree ("teacher_id", "created_at" desc);

alter table "app"."home_player_uploads"
  add constraint "home_player_uploads_pkey"
  primary key using index "home_player_uploads_pkey";

alter table "app"."home_player_uploads"
  add constraint "home_player_uploads_media_asset_id_fkey"
  foreign key ("media_asset_id") references "app"."media_assets" ("id");

alter table "app"."home_player_uploads"
  add constraint "home_player_uploads_media_id_fkey"
  foreign key ("media_id") references "app"."media_objects" ("id");

alter table "app"."home_player_uploads"
  add constraint "home_player_uploads_teacher_id_fkey"
  foreign key ("teacher_id") references "app"."profiles" ("user_id") on delete cascade;

alter table "app"."home_player_uploads" enable row level security;

grant delete on table "app"."home_player_uploads" to "anon";
grant insert on table "app"."home_player_uploads" to "anon";
grant select on table "app"."home_player_uploads" to "anon";
grant update on table "app"."home_player_uploads" to "anon";
grant delete on table "app"."home_player_uploads" to "authenticated";
grant insert on table "app"."home_player_uploads" to "authenticated";
grant select on table "app"."home_player_uploads" to "authenticated";
grant update on table "app"."home_player_uploads" to "authenticated";
grant delete on table "app"."home_player_uploads" to "service_role";
grant insert on table "app"."home_player_uploads" to "service_role";
grant select on table "app"."home_player_uploads" to "service_role";
grant update on table "app"."home_player_uploads" to "service_role";

create policy "home_player_uploads_owner"
on "app"."home_player_uploads"
as permissive
for all
to authenticated
using ((("teacher_id" = auth.uid()) or app.is_admin(auth.uid())))
with check ((("teacher_id" = auth.uid()) or app.is_admin(auth.uid())));

drop trigger if exists "trg_home_player_uploads_touch" on "app"."home_player_uploads";

create trigger "trg_home_player_uploads_touch"
before update on "app"."home_player_uploads"
for each row
execute function "app"."touch_home_player_uploads"();

create table "app"."lesson_media_issues" (
  "lesson_media_id" uuid not null,
  "issue" text not null,
  "details" jsonb not null default '{}'::jsonb,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  constraint "lesson_media_issues_issue_check"
    check (
      "issue" = any (
        array[
          'missing_object'::text,
          'bucket_mismatch'::text,
          'key_format_drift'::text,
          'unsupported'::text
        ]
      )
    )
);

create unique index "lesson_media_issues_pkey"
  on "app"."lesson_media_issues" using btree ("lesson_media_id");

create index "idx_lesson_media_issues_issue"
  on "app"."lesson_media_issues" using btree ("issue");

alter table "app"."lesson_media_issues"
  add constraint "lesson_media_issues_pkey"
  primary key using index "lesson_media_issues_pkey";

alter table "app"."lesson_media_issues"
  add constraint "lesson_media_issues_lesson_media_id_fkey"
  foreign key ("lesson_media_id") references "app"."lesson_media" ("id") on delete cascade;

grant delete on table "app"."lesson_media_issues" to "anon";
grant insert on table "app"."lesson_media_issues" to "anon";
grant select on table "app"."lesson_media_issues" to "anon";
grant update on table "app"."lesson_media_issues" to "anon";
grant delete on table "app"."lesson_media_issues" to "authenticated";
grant insert on table "app"."lesson_media_issues" to "authenticated";
grant select on table "app"."lesson_media_issues" to "authenticated";
grant update on table "app"."lesson_media_issues" to "authenticated";
grant delete on table "app"."lesson_media_issues" to "service_role";
grant insert on table "app"."lesson_media_issues" to "service_role";
grant select on table "app"."lesson_media_issues" to "service_role";
grant update on table "app"."lesson_media_issues" to "service_role";

create table "app"."media_resolution_failures" (
  "id" bigint generated by default as identity not null,
  "created_at" timestamp with time zone not null default now(),
  "lesson_media_id" uuid,
  "mode" text not null,
  "reason" text not null,
  "details" jsonb not null default '{}'::jsonb
);

create unique index "media_resolution_failures_pkey"
  on "app"."media_resolution_failures" using btree ("id");

create index "idx_media_resolution_failures_created_at"
  on "app"."media_resolution_failures" using btree ("created_at" desc);

create index "idx_media_resolution_failures_lesson_media"
  on "app"."media_resolution_failures" using btree ("lesson_media_id");

create index "idx_media_resolution_failures_reason"
  on "app"."media_resolution_failures" using btree ("reason");

alter table "app"."media_resolution_failures"
  add constraint "media_resolution_failures_pkey"
  primary key using index "media_resolution_failures_pkey";

alter table "app"."media_resolution_failures"
  add constraint "media_resolution_failures_lesson_media_id_fkey"
  foreign key ("lesson_media_id") references "app"."lesson_media" ("id") on delete set null;

grant delete on table "app"."media_resolution_failures" to "anon";
grant insert on table "app"."media_resolution_failures" to "anon";
grant select on table "app"."media_resolution_failures" to "anon";
grant update on table "app"."media_resolution_failures" to "anon";
grant delete on table "app"."media_resolution_failures" to "authenticated";
grant insert on table "app"."media_resolution_failures" to "authenticated";
grant select on table "app"."media_resolution_failures" to "authenticated";
grant update on table "app"."media_resolution_failures" to "authenticated";
grant delete on table "app"."media_resolution_failures" to "service_role";
grant insert on table "app"."media_resolution_failures" to "service_role";
grant select on table "app"."media_resolution_failures" to "service_role";
grant update on table "app"."media_resolution_failures" to "service_role";

create or replace function "app"."touch_teacher_profile_media"()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;


create table "app"."teacher_profile_media" (
  "id" uuid not null default gen_random_uuid(),
  "teacher_id" uuid not null,
  "media_kind" text not null,
  "media_id" uuid,
  "external_url" text,
  "title" text,
  "description" text,
  "cover_media_id" uuid,
  "cover_image_url" text,
  "position" integer not null default 0,
  "is_published" boolean not null default true,
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "enabled_for_home_player" boolean not null default false,
  "visibility_intro_material" boolean not null default false,
  "visibility_course_member" boolean not null default false,
  "home_visibility_intro_material" boolean not null default false,
  "home_visibility_course_member" boolean not null default false,
  constraint "teacher_profile_media_media_kind_check"
    check (
      "media_kind" = any (
        array[
          'lesson_media'::text,
          'seminar_recording'::text,
          'external'::text
        ]
      )
    )
);

comment on table "app"."teacher_profile_media"
  is 'Curated media rows surfaced on teacher profile pages (lesson clips, seminar recordings, external links).';

comment on column "app"."teacher_profile_media"."enabled_for_home_player"
  is 'Explicit teacher opt-in gate for Home player inclusion.';

comment on column "app"."teacher_profile_media"."visibility_intro_material"
  is 'When enabled_for_home_player is true: visible to active Aveli members (intro material).';

comment on column "app"."teacher_profile_media"."visibility_course_member"
  is 'When enabled_for_home_player is true: visible to enrolled course members (paid content).';

create unique index "teacher_profile_media_pkey"
  on "app"."teacher_profile_media" using btree ("id");

create unique index "teacher_profile_media_teacher_id_media_kind_media_id_key"
  on "app"."teacher_profile_media"
  using btree ("teacher_id", "media_kind", "media_id");

create index "idx_teacher_profile_media_teacher"
  on "app"."teacher_profile_media" using btree ("teacher_id", "position");

alter table "app"."teacher_profile_media"
  add constraint "teacher_profile_media_pkey"
  primary key using index "teacher_profile_media_pkey";

alter table "app"."teacher_profile_media"
  add constraint "teacher_profile_media_teacher_id_media_kind_media_id_key"
  unique using index "teacher_profile_media_teacher_id_media_kind_media_id_key";

alter table "app"."teacher_profile_media"
  add constraint "teacher_profile_media_cover_media_id_fkey"
  foreign key ("cover_media_id") references "app"."media_objects" ("id") on delete set null;

alter table "app"."teacher_profile_media"
  add constraint "teacher_profile_media_media_id_fkey"
  foreign key ("media_id") references "app"."lesson_media" ("id") on delete set null;

alter table "app"."teacher_profile_media"
  add constraint "teacher_profile_media_teacher_id_fkey"
  foreign key ("teacher_id") references "app"."profiles" ("user_id") on delete cascade;

alter table "app"."teacher_profile_media" enable row level security;

grant delete on table "app"."teacher_profile_media" to "anon";
grant insert on table "app"."teacher_profile_media" to "anon";
grant select on table "app"."teacher_profile_media" to "anon";
grant update on table "app"."teacher_profile_media" to "anon";
grant delete on table "app"."teacher_profile_media" to "authenticated";
grant insert on table "app"."teacher_profile_media" to "authenticated";
grant select on table "app"."teacher_profile_media" to "authenticated";
grant update on table "app"."teacher_profile_media" to "authenticated";
grant delete on table "app"."teacher_profile_media" to "service_role";
grant insert on table "app"."teacher_profile_media" to "service_role";
grant select on table "app"."teacher_profile_media" to "service_role";
grant update on table "app"."teacher_profile_media" to "service_role";

create policy "service_role_full_access"
on "app"."teacher_profile_media"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "tpm_public_read"
on "app"."teacher_profile_media"
as permissive
for select
to public
using (("is_published" = true));

create policy "tpm_teacher"
on "app"."teacher_profile_media"
as permissive
for all
to authenticated
using ((("teacher_id" = auth.uid()) or app.is_admin(auth.uid())))
with check ((("teacher_id" = auth.uid()) or app.is_admin(auth.uid())));

drop trigger if exists "trg_teacher_profile_media_touch" on "app"."teacher_profile_media";

create trigger "trg_teacher_profile_media_touch"
before update on "app"."teacher_profile_media"
for each row
execute function "app"."touch_teacher_profile_media"();

alter table "app"."runtime_media"
  add column "is_test" boolean not null default false;

alter table "app"."runtime_media"
  add column "test_session_id" uuid;

alter table "app"."runtime_media"
  drop constraint "runtime_media_auth_scope_check";

alter table "app"."runtime_media"
  drop constraint "runtime_media_course_id_fkey";

alter table "app"."runtime_media"
  drop constraint "runtime_media_lesson_id_fkey";

alter table "app"."runtime_media"
  drop constraint "runtime_media_lesson_media_id_key";

alter table "app"."runtime_media"
  drop constraint "runtime_media_lesson_projection_shape";

alter table "app"."runtime_media"
  drop constraint "runtime_media_reference_type_check";

alter table "app"."runtime_media"
  add constraint "runtime_media_auth_scope_check"
  check (
    "auth_scope" = any (
      array['lesson_course'::text, 'home_teacher_library'::text]
    )
  );

alter table "app"."runtime_media"
  add constraint "runtime_media_auth_shape"
  check (
    (
      "auth_scope" = 'lesson_course'::text
      and "lesson_media_id" is not null
      and "course_id" is not null
      and "lesson_id" is not null
    ) or (
      "auth_scope" = 'home_teacher_library'::text
      and "home_player_upload_id" is not null
    )
  );

alter table "app"."runtime_media"
  add constraint "runtime_media_course_id_fkey"
  foreign key ("course_id") references "app"."courses" ("id") on delete cascade;

alter table "app"."runtime_media"
  add constraint "runtime_media_home_player_upload_id_fkey"
  foreign key ("home_player_upload_id") references "app"."home_player_uploads" ("id") on delete cascade;

alter table "app"."runtime_media"
  add constraint "runtime_media_home_player_upload_id_key"
  unique ("home_player_upload_id");

alter table "app"."runtime_media"
  add constraint "runtime_media_lesson_id_fkey"
  foreign key ("lesson_id") references "app"."lessons" ("id") on delete cascade;

alter table "app"."runtime_media"
  add constraint "runtime_media_one_origin"
  check ((((("lesson_media_id" is not null))::integer + (("home_player_upload_id" is not null))::integer) = 1));

alter table "app"."runtime_media"
  add constraint "runtime_media_reference_type_check"
  check (
    "reference_type" = any (
      array['lesson_media'::text, 'home_player_upload'::text]
    )
  );

alter table "app"."runtime_media"
  add constraint "runtime_media_test_session_consistency"
  check (
    (
      coalesce("is_test", false) = false
      and "test_session_id" is null
    ) or (
      coalesce("is_test", false) = true
      and "test_session_id" is not null
    )
  );

create index "idx_runtime_media_teacher_active"
  on "app"."runtime_media" using btree ("teacher_id", "active");

create index "idx_runtime_media_test_session"
  on "app"."runtime_media" using btree ("test_session_id")
  where ("is_test" = true);

create unique index "idx_runtime_media_lesson_media_active_unique"
  on "app"."runtime_media" using btree ("lesson_media_id")
  where (("lesson_media_id" is not null) and ("active" = true));

create unique index "runtime_media_active_lesson_media_uidx"
  on "app"."runtime_media" using btree ("lesson_media_id")
  where ("active" = true);

drop trigger if exists "trg_runtime_media_apply_test_row_defaults" on "app"."runtime_media";
drop trigger if exists "trg_runtime_media_touch" on "app"."runtime_media";

create trigger "trg_runtime_media_apply_test_row_defaults"
before insert or update of "is_test", "test_session_id" on "app"."runtime_media"
for each row
execute function "app"."apply_test_row_defaults"();

create trigger "trg_runtime_media_touch"
before update on "app"."runtime_media"
for each row
execute function "app"."set_updated_at"();

create or replace function "app"."cleanup_test_session"(
  target_test_session_id uuid
)
returns void
language plpgsql
as $function$
begin
  if target_test_session_id is null then
    raise exception 'cleanup_test_session requires test_session_id'
      using errcode = '22004';
  end if;

  delete from app.teacher_profile_media tpm
  where tpm.media_kind = 'lesson_media'
    and tpm.media_id in (
      select lm.id
      from app.lesson_media lm
      where lm.is_test = true
        and lm.test_session_id = target_test_session_id
    );

  delete from app.home_player_course_links hpcl
  where hpcl.lesson_media_id in (
    select lm.id
    from app.lesson_media lm
    where lm.is_test = true
      and lm.test_session_id = target_test_session_id
  );

  delete from app.home_player_uploads hpu
  where hpu.id in (
      select rm.home_player_upload_id
      from app.runtime_media rm
      where rm.is_test = true
        and rm.test_session_id = target_test_session_id
        and rm.home_player_upload_id is not null
    )
    or hpu.media_asset_id in (
      select ma.id
      from app.media_assets ma
      where ma.is_test = true
        and ma.test_session_id = target_test_session_id
    );

  delete from app.runtime_media
  where is_test = true
    and test_session_id = target_test_session_id;

  delete from app.lesson_media
  where is_test = true
    and test_session_id = target_test_session_id;

  delete from app.media_assets
  where is_test = true
    and test_session_id = target_test_session_id;

  delete from app.lessons
  where is_test = true
    and test_session_id = target_test_session_id;

  delete from app.courses
  where is_test = true
    and test_session_id = target_test_session_id;
end;
$function$;


create or replace function "app"."cleanup_stale_test_data"(
  max_age interval default '24:00:00'::interval
)
returns integer
language plpgsql
as $function$
declare
  session_row record;
  cleaned_sessions integer := 0;
begin
  for session_row in
    with stale_sessions as (
      select distinct c.test_session_id
      from app.courses c
      where c.is_test = true
        and c.test_session_id is not null
        and c.created_at < now() - max_age

      union

      select distinct l.test_session_id
      from app.lessons l
      where l.is_test = true
        and l.test_session_id is not null
        and l.created_at < now() - max_age

      union

      select distinct lm.test_session_id
      from app.lesson_media lm
      where lm.is_test = true
        and lm.test_session_id is not null
        and lm.created_at < now() - max_age

      union

      select distinct ma.test_session_id
      from app.media_assets ma
      where ma.is_test = true
        and ma.test_session_id is not null
        and ma.created_at < now() - max_age

      union

      select distinct rm.test_session_id
      from app.runtime_media rm
      where rm.is_test = true
        and rm.test_session_id is not null
        and rm.created_at < now() - max_age
    )
    select stale_sessions.test_session_id
    from stale_sessions
  loop
    perform app.cleanup_test_session(session_row.test_session_id);
    cleaned_sessions := cleaned_sessions + 1;
  end loop;

  return cleaned_sessions;
end;
$function$;
