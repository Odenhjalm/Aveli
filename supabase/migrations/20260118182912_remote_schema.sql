drop extension if exists "pg_net";

alter table "app"."live_event_registrations" drop constraint "live_event_registrations_event_id_user_id_key";

alter table "app"."live_events" drop constraint "live_events_course_id_fkey";

alter table "app"."live_events" drop constraint "live_events_teacher_id_fkey";

alter table "app"."livekit_webhook_jobs" drop constraint "livekit_webhook_jobs_pkey";

drop index if exists "app"."live_event_registrations_event_id_user_id_key";

drop index if exists "app"."livekit_webhook_jobs_pkey";


  create table "app"."classroom_messages" (
    "id" uuid not null default gen_random_uuid(),
    "course_id" uuid not null,
    "user_id" uuid not null,
    "message" text not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "app"."classroom_messages" enable row level security;


  create table "app"."classroom_presence" (
    "id" uuid not null default gen_random_uuid(),
    "course_id" uuid not null,
    "user_id" uuid not null,
    "last_seen" timestamp with time zone not null default now()
      );


alter table "app"."classroom_presence" enable row level security;


  create table "app"."lesson_packages" (
    "id" uuid not null default gen_random_uuid(),
    "lesson_id" uuid not null,
    "stripe_product_id" text not null,
    "stripe_price_id" text not null,
    "price_amount" integer not null,
    "price_currency" text not null default 'sek'::text,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."lesson_packages" enable row level security;


  create table "app"."music_tracks" (
    "id" uuid not null default gen_random_uuid(),
    "teacher_id" uuid not null,
    "title" text not null,
    "description" text,
    "duration_seconds" integer,
    "storage_path" text not null,
    "cover_image_path" text,
    "access_scope" text not null,
    "course_id" uuid,
    "is_published" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."music_tracks" enable row level security;


  create table "app"."teacher_accounts" (
    "user_id" uuid not null,
    "stripe_account_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."teacher_accounts" enable row level security;


  create table "app"."welcome_cards" (
    "id" uuid not null default gen_random_uuid(),
    "title" text,
    "body" text,
    "image_path" text not null,
    "day" integer,
    "month" integer,
    "is_active" boolean not null default true,
    "created_by" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "app"."welcome_cards" enable row level security;

alter table "app"."lessons" add column "price_amount_cents" integer not null default 0;

alter table "app"."lessons" add column "price_currency" text not null default 'sek'::text;

alter table "app"."live_event_registrations" drop column "status";

alter table "app"."live_events" drop column "livekit_room";

alter table "app"."live_events" drop column "metadata";

alter table "app"."live_events" add column "room_name" text not null;

alter table "app"."live_events" add column "scheduled_at" timestamp with time zone not null;

alter table "app"."live_events" alter column "access_type" drop default;

alter table "app"."live_events" alter column "teacher_id" set not null;

alter table "app"."livekit_webhook_jobs" drop column "attempts";

alter table "app"."livekit_webhook_jobs" drop column "error";

alter table "app"."livekit_webhook_jobs" drop column "job_id";

alter table "app"."livekit_webhook_jobs" drop column "last_attempted_at";

alter table "app"."livekit_webhook_jobs" add column "attempt" integer not null default 0;

alter table "app"."livekit_webhook_jobs" add column "id" uuid not null default gen_random_uuid();

alter table "app"."livekit_webhook_jobs" add column "last_attempt_at" timestamp with time zone;

alter table "app"."livekit_webhook_jobs" add column "last_error" text;

alter table "app"."profiles" add column "last_login_at" timestamp with time zone;

alter table "app"."profiles" add column "last_login_provider" text;

alter table "app"."profiles" add column "provider_avatar_url" text;

alter table "app"."profiles" add column "provider_email_verified" boolean;

alter table "app"."profiles" add column "provider_name" text;

alter table "app"."profiles" add column "provider_user_id" text;

CREATE UNIQUE INDEX classroom_messages_pkey ON app.classroom_messages USING btree (id);

CREATE UNIQUE INDEX classroom_presence_course_id_user_id_key ON app.classroom_presence USING btree (course_id, user_id);

CREATE UNIQUE INDEX classroom_presence_pkey ON app.classroom_presence USING btree (id);

CREATE INDEX idx_classroom_messages_course ON app.classroom_messages USING btree (course_id);

CREATE INDEX idx_classroom_messages_created ON app.classroom_messages USING btree (created_at);

CREATE INDEX idx_classroom_presence_course ON app.classroom_presence USING btree (course_id);

CREATE INDEX idx_classroom_presence_last_seen ON app.classroom_presence USING btree (last_seen);

CREATE INDEX idx_lesson_packages_lesson ON app.lesson_packages USING btree (lesson_id);

CREATE UNIQUE INDEX idx_live_event_registrations_unique ON app.live_event_registrations USING btree (event_id, user_id);

CREATE INDEX idx_live_events_access_type ON app.live_events USING btree (access_type);

CREATE INDEX idx_live_events_scheduled_at ON app.live_events USING btree (scheduled_at);

CREATE INDEX idx_music_tracks_course ON app.music_tracks USING btree (course_id);

CREATE INDEX idx_music_tracks_created ON app.music_tracks USING btree (created_at DESC);

CREATE INDEX idx_music_tracks_teacher ON app.music_tracks USING btree (teacher_id);

CREATE INDEX idx_welcome_cards_active ON app.welcome_cards USING btree (is_active);

CREATE INDEX idx_welcome_cards_date ON app.welcome_cards USING btree (month, day);

CREATE UNIQUE INDEX lesson_packages_lesson_id_key ON app.lesson_packages USING btree (lesson_id);

CREATE UNIQUE INDEX lesson_packages_pkey ON app.lesson_packages USING btree (id);

CREATE UNIQUE INDEX music_tracks_pkey ON app.music_tracks USING btree (id);

CREATE UNIQUE INDEX teacher_accounts_pkey ON app.teacher_accounts USING btree (user_id);

CREATE UNIQUE INDEX welcome_cards_pkey ON app.welcome_cards USING btree (id);

CREATE UNIQUE INDEX livekit_webhook_jobs_pkey ON app.livekit_webhook_jobs USING btree (id);

alter table "app"."classroom_messages" add constraint "classroom_messages_pkey" PRIMARY KEY using index "classroom_messages_pkey";

alter table "app"."classroom_presence" add constraint "classroom_presence_pkey" PRIMARY KEY using index "classroom_presence_pkey";

alter table "app"."lesson_packages" add constraint "lesson_packages_pkey" PRIMARY KEY using index "lesson_packages_pkey";

alter table "app"."music_tracks" add constraint "music_tracks_pkey" PRIMARY KEY using index "music_tracks_pkey";

alter table "app"."teacher_accounts" add constraint "teacher_accounts_pkey" PRIMARY KEY using index "teacher_accounts_pkey";

alter table "app"."welcome_cards" add constraint "welcome_cards_pkey" PRIMARY KEY using index "welcome_cards_pkey";

alter table "app"."livekit_webhook_jobs" add constraint "livekit_webhook_jobs_pkey" PRIMARY KEY using index "livekit_webhook_jobs_pkey";

alter table "app"."classroom_messages" add constraint "classroom_messages_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."classroom_messages" validate constraint "classroom_messages_course_id_fkey";

alter table "app"."classroom_messages" add constraint "classroom_messages_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."classroom_messages" validate constraint "classroom_messages_user_id_fkey";

alter table "app"."classroom_presence" add constraint "classroom_presence_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."classroom_presence" validate constraint "classroom_presence_course_id_fkey";

alter table "app"."classroom_presence" add constraint "classroom_presence_course_id_user_id_key" UNIQUE using index "classroom_presence_course_id_user_id_key";

alter table "app"."classroom_presence" add constraint "classroom_presence_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."classroom_presence" validate constraint "classroom_presence_user_id_fkey";

alter table "app"."course_products" add constraint "course_products_course_id_key" UNIQUE using index "course_products_course_id_key";

alter table "app"."entitlements" add constraint "entitlements_source_check" CHECK ((source = ANY (ARRAY['purchase'::text, 'subscription'::text, 'admin'::text]))) not valid;

alter table "app"."entitlements" validate constraint "entitlements_source_check";

alter table "app"."guest_claim_tokens" add constraint "guest_claim_tokens_token_key" UNIQUE using index "guest_claim_tokens_token_key";

alter table "app"."lesson_packages" add constraint "lesson_packages_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES app.lessons(id) ON DELETE CASCADE not valid;

alter table "app"."lesson_packages" validate constraint "lesson_packages_lesson_id_fkey";

alter table "app"."lesson_packages" add constraint "lesson_packages_lesson_id_key" UNIQUE using index "lesson_packages_lesson_id_key";

alter table "app"."music_tracks" add constraint "music_tracks_access_scope_check" CHECK ((access_scope = ANY (ARRAY['membership'::text, 'course'::text]))) not valid;

alter table "app"."music_tracks" validate constraint "music_tracks_access_scope_check";

alter table "app"."music_tracks" add constraint "music_tracks_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE not valid;

alter table "app"."music_tracks" validate constraint "music_tracks_course_id_fkey";

alter table "app"."music_tracks" add constraint "music_tracks_scope_course" CHECK ((((access_scope = 'course'::text) AND (course_id IS NOT NULL)) OR ((access_scope = 'membership'::text) AND (course_id IS NULL)))) not valid;

alter table "app"."music_tracks" validate constraint "music_tracks_scope_course";

alter table "app"."music_tracks" add constraint "music_tracks_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."music_tracks" validate constraint "music_tracks_teacher_id_fkey";

alter table "app"."teacher_accounts" add constraint "teacher_accounts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."teacher_accounts" validate constraint "teacher_accounts_user_id_fkey";

alter table "app"."welcome_cards" add constraint "welcome_cards_created_by_fkey" FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."welcome_cards" validate constraint "welcome_cards_created_by_fkey";

alter table "app"."welcome_cards" add constraint "welcome_cards_day_check" CHECK (((day >= 1) AND (day <= 31))) not valid;

alter table "app"."welcome_cards" validate constraint "welcome_cards_day_check";

alter table "app"."welcome_cards" add constraint "welcome_cards_day_month_pair" CHECK ((((day IS NULL) AND (month IS NULL)) OR ((day IS NOT NULL) AND (month IS NOT NULL)))) not valid;

alter table "app"."welcome_cards" validate constraint "welcome_cards_day_month_pair";

alter table "app"."welcome_cards" add constraint "welcome_cards_month_check" CHECK (((month >= 1) AND (month <= 12))) not valid;

alter table "app"."welcome_cards" validate constraint "welcome_cards_month_check";

alter table "app"."live_events" add constraint "live_events_course_id_fkey" FOREIGN KEY (course_id) REFERENCES app.courses(id) not valid;

alter table "app"."live_events" validate constraint "live_events_course_id_fkey";

alter table "app"."live_events" add constraint "live_events_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE not valid;

alter table "app"."live_events" validate constraint "live_events_teacher_id_fkey";

set check_function_bodies = off;

create or replace view "app"."course_enrollments_view" as  SELECT e.user_id,
    e.course_id,
    c.title AS course_title,
    e.source AS purchase_source,
    e.created_at
   FROM (app.entitlements e
     JOIN app.courses c ON ((c.id = e.course_id)));


CREATE OR REPLACE FUNCTION app.has_course_classroom_access(p_course_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
AS $function$
  select
    coalesce(app.is_admin(p_user_id), false)
    or exists (
      select 1 from app.courses c
      where c.id = p_course_id and c.created_by = p_user_id
    )
    or exists (
      select 1 from app.entitlements e
      where e.course_id = p_course_id and e.user_id = p_user_id
    )
    or exists (
      select 1 from app.enrollments en
      where en.course_id = p_course_id and en.user_id = p_user_id
    )
    or exists (
      select 1
      from app.memberships m
      where m.user_id = p_user_id
        and lower(coalesce(m.status, 'active')) not in (
          'canceled', 'unpaid', 'incomplete_expired', 'past_due'
        )
    );
$function$
;

CREATE OR REPLACE FUNCTION app.touch_livekit_webhook_jobs()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    begin
      new.updated_at = now();
      return new;
    end;
    $function$
;

create or replace view "app"."v_meditation_audio_library" as  SELECT lm.id AS media_id,
    m.course_id,
    l.id AS lesson_id,
    l.title,
    NULL::text AS description,
    COALESCE(mo.storage_path, lm.storage_path) AS storage_path,
    COALESCE(mo.storage_bucket, lm.storage_bucket, 'lesson-media'::text) AS storage_bucket,
    lm.duration_seconds,
    lm.created_at
   FROM (((app.lesson_media lm
     JOIN app.lessons l ON ((l.id = lm.lesson_id)))
     JOIN app.modules m ON ((m.id = l.module_id)))
     LEFT JOIN app.media_objects mo ON ((mo.id = lm.media_id)))
  WHERE (lower(lm.kind) = 'audio'::text);


CREATE OR REPLACE FUNCTION public.rest_insert_seminar(p_host_id uuid, p_title text, p_status app.seminar_status)
 RETURNS app.seminars
 LANGUAGE plpgsql
AS $function$
declare
  created_row app.seminars%rowtype;
begin
  insert into app.seminars (host_id, title, status)
  values (p_host_id, p_title, p_status)
  returning * into created_row;

  return created_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.rest_select_seminar(p_seminar_id uuid)
 RETURNS SETOF app.seminars
 LANGUAGE sql
 STABLE
AS $function$
  select *
  from app.seminars
  where id = p_seminar_id;
$function$
;

CREATE OR REPLACE FUNCTION public.rest_select_seminar_attendees(p_seminar_id uuid)
 RETURNS SETOF app.seminar_attendees
 LANGUAGE sql
 STABLE
AS $function$
  select *
  from app.seminar_attendees
  where seminar_id = p_seminar_id;
$function$
;

CREATE OR REPLACE FUNCTION public.rest_update_seminar_description(p_seminar_id uuid, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  updated_row app.seminars%rowtype;
begin
  update app.seminars
  set description = p_description
  where id = p_seminar_id
  returning * into updated_row;

  if not found then
    return jsonb_build_object('id', null, 'description', null);
  end if;

  return to_jsonb(updated_row);
end;
$function$
;

grant delete on table "app"."activities" to "anon";

grant insert on table "app"."activities" to "anon";

grant select on table "app"."activities" to "anon";

grant update on table "app"."activities" to "anon";

grant delete on table "app"."activities" to "authenticated";

grant insert on table "app"."activities" to "authenticated";

grant select on table "app"."activities" to "authenticated";

grant update on table "app"."activities" to "authenticated";

grant delete on table "app"."activities" to "service_role";

grant insert on table "app"."activities" to "service_role";

grant select on table "app"."activities" to "service_role";

grant update on table "app"."activities" to "service_role";

grant delete on table "app"."app_config" to "anon";

grant insert on table "app"."app_config" to "anon";

grant select on table "app"."app_config" to "anon";

grant update on table "app"."app_config" to "anon";

grant delete on table "app"."app_config" to "authenticated";

grant insert on table "app"."app_config" to "authenticated";

grant select on table "app"."app_config" to "authenticated";

grant update on table "app"."app_config" to "authenticated";

grant delete on table "app"."app_config" to "service_role";

grant insert on table "app"."app_config" to "service_role";

grant select on table "app"."app_config" to "service_role";

grant update on table "app"."app_config" to "service_role";

grant delete on table "app"."auth_events" to "anon";

grant insert on table "app"."auth_events" to "anon";

grant select on table "app"."auth_events" to "anon";

grant update on table "app"."auth_events" to "anon";

grant delete on table "app"."auth_events" to "authenticated";

grant insert on table "app"."auth_events" to "authenticated";

grant select on table "app"."auth_events" to "authenticated";

grant update on table "app"."auth_events" to "authenticated";

grant delete on table "app"."auth_events" to "service_role";

grant insert on table "app"."auth_events" to "service_role";

grant select on table "app"."auth_events" to "service_role";

grant update on table "app"."auth_events" to "service_role";

grant delete on table "app"."billing_logs" to "anon";

grant insert on table "app"."billing_logs" to "anon";

grant select on table "app"."billing_logs" to "anon";

grant update on table "app"."billing_logs" to "anon";

grant delete on table "app"."billing_logs" to "authenticated";

grant insert on table "app"."billing_logs" to "authenticated";

grant select on table "app"."billing_logs" to "authenticated";

grant update on table "app"."billing_logs" to "authenticated";

grant delete on table "app"."billing_logs" to "service_role";

grant insert on table "app"."billing_logs" to "service_role";

grant select on table "app"."billing_logs" to "service_role";

grant update on table "app"."billing_logs" to "service_role";

grant delete on table "app"."certificates" to "anon";

grant insert on table "app"."certificates" to "anon";

grant select on table "app"."certificates" to "anon";

grant update on table "app"."certificates" to "anon";

grant delete on table "app"."certificates" to "authenticated";

grant insert on table "app"."certificates" to "authenticated";

grant select on table "app"."certificates" to "authenticated";

grant update on table "app"."certificates" to "authenticated";

grant delete on table "app"."certificates" to "service_role";

grant insert on table "app"."certificates" to "service_role";

grant select on table "app"."certificates" to "service_role";

grant update on table "app"."certificates" to "service_role";

grant delete on table "app"."classroom_messages" to "anon";

grant insert on table "app"."classroom_messages" to "anon";

grant select on table "app"."classroom_messages" to "anon";

grant update on table "app"."classroom_messages" to "anon";

grant delete on table "app"."classroom_messages" to "authenticated";

grant insert on table "app"."classroom_messages" to "authenticated";

grant select on table "app"."classroom_messages" to "authenticated";

grant update on table "app"."classroom_messages" to "authenticated";

grant delete on table "app"."classroom_messages" to "service_role";

grant insert on table "app"."classroom_messages" to "service_role";

grant select on table "app"."classroom_messages" to "service_role";

grant update on table "app"."classroom_messages" to "service_role";

grant delete on table "app"."classroom_presence" to "anon";

grant insert on table "app"."classroom_presence" to "anon";

grant select on table "app"."classroom_presence" to "anon";

grant update on table "app"."classroom_presence" to "anon";

grant delete on table "app"."classroom_presence" to "authenticated";

grant insert on table "app"."classroom_presence" to "authenticated";

grant select on table "app"."classroom_presence" to "authenticated";

grant update on table "app"."classroom_presence" to "authenticated";

grant delete on table "app"."classroom_presence" to "service_role";

grant insert on table "app"."classroom_presence" to "service_role";

grant select on table "app"."classroom_presence" to "service_role";

grant update on table "app"."classroom_presence" to "service_role";

grant delete on table "app"."course_bundle_courses" to "anon";

grant insert on table "app"."course_bundle_courses" to "anon";

grant select on table "app"."course_bundle_courses" to "anon";

grant update on table "app"."course_bundle_courses" to "anon";

grant delete on table "app"."course_bundle_courses" to "authenticated";

grant insert on table "app"."course_bundle_courses" to "authenticated";

grant select on table "app"."course_bundle_courses" to "authenticated";

grant update on table "app"."course_bundle_courses" to "authenticated";

grant delete on table "app"."course_bundle_courses" to "service_role";

grant insert on table "app"."course_bundle_courses" to "service_role";

grant select on table "app"."course_bundle_courses" to "service_role";

grant update on table "app"."course_bundle_courses" to "service_role";

grant delete on table "app"."course_bundles" to "anon";

grant insert on table "app"."course_bundles" to "anon";

grant select on table "app"."course_bundles" to "anon";

grant update on table "app"."course_bundles" to "anon";

grant delete on table "app"."course_bundles" to "authenticated";

grant insert on table "app"."course_bundles" to "authenticated";

grant select on table "app"."course_bundles" to "authenticated";

grant update on table "app"."course_bundles" to "authenticated";

grant delete on table "app"."course_bundles" to "service_role";

grant insert on table "app"."course_bundles" to "service_role";

grant select on table "app"."course_bundles" to "service_role";

grant update on table "app"."course_bundles" to "service_role";

grant delete on table "app"."course_display_priorities" to "anon";

grant insert on table "app"."course_display_priorities" to "anon";

grant select on table "app"."course_display_priorities" to "anon";

grant update on table "app"."course_display_priorities" to "anon";

grant delete on table "app"."course_display_priorities" to "authenticated";

grant insert on table "app"."course_display_priorities" to "authenticated";

grant select on table "app"."course_display_priorities" to "authenticated";

grant update on table "app"."course_display_priorities" to "authenticated";

grant delete on table "app"."course_display_priorities" to "service_role";

grant insert on table "app"."course_display_priorities" to "service_role";

grant select on table "app"."course_display_priorities" to "service_role";

grant update on table "app"."course_display_priorities" to "service_role";

grant delete on table "app"."course_entitlements" to "anon";

grant insert on table "app"."course_entitlements" to "anon";

grant select on table "app"."course_entitlements" to "anon";

grant update on table "app"."course_entitlements" to "anon";

grant delete on table "app"."course_entitlements" to "authenticated";

grant insert on table "app"."course_entitlements" to "authenticated";

grant select on table "app"."course_entitlements" to "authenticated";

grant update on table "app"."course_entitlements" to "authenticated";

grant delete on table "app"."course_entitlements" to "service_role";

grant insert on table "app"."course_entitlements" to "service_role";

grant select on table "app"."course_entitlements" to "service_role";

grant update on table "app"."course_entitlements" to "service_role";

grant delete on table "app"."course_products" to "anon";

grant insert on table "app"."course_products" to "anon";

grant select on table "app"."course_products" to "anon";

grant update on table "app"."course_products" to "anon";

grant delete on table "app"."course_products" to "authenticated";

grant insert on table "app"."course_products" to "authenticated";

grant select on table "app"."course_products" to "authenticated";

grant update on table "app"."course_products" to "authenticated";

grant delete on table "app"."course_products" to "service_role";

grant insert on table "app"."course_products" to "service_role";

grant select on table "app"."course_products" to "service_role";

grant update on table "app"."course_products" to "service_role";

grant delete on table "app"."course_quizzes" to "anon";

grant insert on table "app"."course_quizzes" to "anon";

grant select on table "app"."course_quizzes" to "anon";

grant update on table "app"."course_quizzes" to "anon";

grant delete on table "app"."course_quizzes" to "authenticated";

grant insert on table "app"."course_quizzes" to "authenticated";

grant select on table "app"."course_quizzes" to "authenticated";

grant update on table "app"."course_quizzes" to "authenticated";

grant delete on table "app"."course_quizzes" to "service_role";

grant insert on table "app"."course_quizzes" to "service_role";

grant select on table "app"."course_quizzes" to "service_role";

grant update on table "app"."course_quizzes" to "service_role";

grant delete on table "app"."courses" to "anon";

grant insert on table "app"."courses" to "anon";

grant select on table "app"."courses" to "anon";

grant update on table "app"."courses" to "anon";

grant delete on table "app"."courses" to "authenticated";

grant insert on table "app"."courses" to "authenticated";

grant select on table "app"."courses" to "authenticated";

grant update on table "app"."courses" to "authenticated";

grant delete on table "app"."courses" to "service_role";

grant insert on table "app"."courses" to "service_role";

grant select on table "app"."courses" to "service_role";

grant update on table "app"."courses" to "service_role";

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

grant delete on table "app"."entitlements" to "anon";

grant insert on table "app"."entitlements" to "anon";

grant select on table "app"."entitlements" to "anon";

grant update on table "app"."entitlements" to "anon";

grant delete on table "app"."entitlements" to "authenticated";

grant insert on table "app"."entitlements" to "authenticated";

grant select on table "app"."entitlements" to "authenticated";

grant update on table "app"."entitlements" to "authenticated";

grant delete on table "app"."entitlements" to "service_role";

grant insert on table "app"."entitlements" to "service_role";

grant select on table "app"."entitlements" to "service_role";

grant update on table "app"."entitlements" to "service_role";

grant delete on table "app"."follows" to "anon";

grant insert on table "app"."follows" to "anon";

grant select on table "app"."follows" to "anon";

grant update on table "app"."follows" to "anon";

grant delete on table "app"."follows" to "authenticated";

grant insert on table "app"."follows" to "authenticated";

grant select on table "app"."follows" to "authenticated";

grant update on table "app"."follows" to "authenticated";

grant delete on table "app"."follows" to "service_role";

grant insert on table "app"."follows" to "service_role";

grant select on table "app"."follows" to "service_role";

grant update on table "app"."follows" to "service_role";

grant delete on table "app"."guest_claim_tokens" to "anon";

grant insert on table "app"."guest_claim_tokens" to "anon";

grant select on table "app"."guest_claim_tokens" to "anon";

grant update on table "app"."guest_claim_tokens" to "anon";

grant delete on table "app"."guest_claim_tokens" to "authenticated";

grant insert on table "app"."guest_claim_tokens" to "authenticated";

grant select on table "app"."guest_claim_tokens" to "authenticated";

grant update on table "app"."guest_claim_tokens" to "authenticated";

grant delete on table "app"."guest_claim_tokens" to "service_role";

grant insert on table "app"."guest_claim_tokens" to "service_role";

grant select on table "app"."guest_claim_tokens" to "service_role";

grant update on table "app"."guest_claim_tokens" to "service_role";

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

grant delete on table "app"."lesson_packages" to "anon";

grant insert on table "app"."lesson_packages" to "anon";

grant select on table "app"."lesson_packages" to "anon";

grant update on table "app"."lesson_packages" to "anon";

grant delete on table "app"."lesson_packages" to "authenticated";

grant insert on table "app"."lesson_packages" to "authenticated";

grant select on table "app"."lesson_packages" to "authenticated";

grant update on table "app"."lesson_packages" to "authenticated";

grant delete on table "app"."lesson_packages" to "service_role";

grant insert on table "app"."lesson_packages" to "service_role";

grant select on table "app"."lesson_packages" to "service_role";

grant update on table "app"."lesson_packages" to "service_role";

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

grant delete on table "app"."live_event_registrations" to "anon";

grant insert on table "app"."live_event_registrations" to "anon";

grant select on table "app"."live_event_registrations" to "anon";

grant update on table "app"."live_event_registrations" to "anon";

grant delete on table "app"."live_event_registrations" to "authenticated";

grant insert on table "app"."live_event_registrations" to "authenticated";

grant select on table "app"."live_event_registrations" to "authenticated";

grant update on table "app"."live_event_registrations" to "authenticated";

grant delete on table "app"."live_event_registrations" to "service_role";

grant insert on table "app"."live_event_registrations" to "service_role";

grant select on table "app"."live_event_registrations" to "service_role";

grant update on table "app"."live_event_registrations" to "service_role";

grant delete on table "app"."live_events" to "anon";

grant insert on table "app"."live_events" to "anon";

grant select on table "app"."live_events" to "anon";

grant update on table "app"."live_events" to "anon";

grant delete on table "app"."live_events" to "authenticated";

grant insert on table "app"."live_events" to "authenticated";

grant select on table "app"."live_events" to "authenticated";

grant update on table "app"."live_events" to "authenticated";

grant delete on table "app"."live_events" to "service_role";

grant insert on table "app"."live_events" to "service_role";

grant select on table "app"."live_events" to "service_role";

grant update on table "app"."live_events" to "service_role";

grant delete on table "app"."livekit_webhook_jobs" to "anon";

grant insert on table "app"."livekit_webhook_jobs" to "anon";

grant select on table "app"."livekit_webhook_jobs" to "anon";

grant update on table "app"."livekit_webhook_jobs" to "anon";

grant delete on table "app"."livekit_webhook_jobs" to "authenticated";

grant insert on table "app"."livekit_webhook_jobs" to "authenticated";

grant select on table "app"."livekit_webhook_jobs" to "authenticated";

grant update on table "app"."livekit_webhook_jobs" to "authenticated";

grant delete on table "app"."livekit_webhook_jobs" to "service_role";

grant insert on table "app"."livekit_webhook_jobs" to "service_role";

grant select on table "app"."livekit_webhook_jobs" to "service_role";

grant update on table "app"."livekit_webhook_jobs" to "service_role";

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

grant delete on table "app"."meditations" to "anon";

grant insert on table "app"."meditations" to "anon";

grant select on table "app"."meditations" to "anon";

grant update on table "app"."meditations" to "anon";

grant delete on table "app"."meditations" to "authenticated";

grant insert on table "app"."meditations" to "authenticated";

grant select on table "app"."meditations" to "authenticated";

grant update on table "app"."meditations" to "authenticated";

grant delete on table "app"."meditations" to "service_role";

grant insert on table "app"."meditations" to "service_role";

grant select on table "app"."meditations" to "service_role";

grant update on table "app"."meditations" to "service_role";

grant delete on table "app"."memberships" to "anon";

grant insert on table "app"."memberships" to "anon";

grant select on table "app"."memberships" to "anon";

grant update on table "app"."memberships" to "anon";

grant delete on table "app"."memberships" to "authenticated";

grant insert on table "app"."memberships" to "authenticated";

grant select on table "app"."memberships" to "authenticated";

grant update on table "app"."memberships" to "authenticated";

grant delete on table "app"."memberships" to "service_role";

grant insert on table "app"."memberships" to "service_role";

grant select on table "app"."memberships" to "service_role";

grant update on table "app"."memberships" to "service_role";

grant delete on table "app"."messages" to "anon";

grant insert on table "app"."messages" to "anon";

grant select on table "app"."messages" to "anon";

grant update on table "app"."messages" to "anon";

grant delete on table "app"."messages" to "authenticated";

grant insert on table "app"."messages" to "authenticated";

grant select on table "app"."messages" to "authenticated";

grant update on table "app"."messages" to "authenticated";

grant delete on table "app"."messages" to "service_role";

grant insert on table "app"."messages" to "service_role";

grant select on table "app"."messages" to "service_role";

grant update on table "app"."messages" to "service_role";

grant delete on table "app"."modules" to "anon";

grant insert on table "app"."modules" to "anon";

grant select on table "app"."modules" to "anon";

grant update on table "app"."modules" to "anon";

grant delete on table "app"."modules" to "authenticated";

grant insert on table "app"."modules" to "authenticated";

grant select on table "app"."modules" to "authenticated";

grant update on table "app"."modules" to "authenticated";

grant delete on table "app"."modules" to "service_role";

grant insert on table "app"."modules" to "service_role";

grant select on table "app"."modules" to "service_role";

grant update on table "app"."modules" to "service_role";

grant delete on table "app"."music_tracks" to "anon";

grant insert on table "app"."music_tracks" to "anon";

grant select on table "app"."music_tracks" to "anon";

grant update on table "app"."music_tracks" to "anon";

grant delete on table "app"."music_tracks" to "authenticated";

grant insert on table "app"."music_tracks" to "authenticated";

grant select on table "app"."music_tracks" to "authenticated";

grant update on table "app"."music_tracks" to "authenticated";

grant delete on table "app"."music_tracks" to "service_role";

grant insert on table "app"."music_tracks" to "service_role";

grant select on table "app"."music_tracks" to "service_role";

grant update on table "app"."music_tracks" to "service_role";

grant delete on table "app"."notifications" to "anon";

grant insert on table "app"."notifications" to "anon";

grant select on table "app"."notifications" to "anon";

grant update on table "app"."notifications" to "anon";

grant delete on table "app"."notifications" to "authenticated";

grant insert on table "app"."notifications" to "authenticated";

grant select on table "app"."notifications" to "authenticated";

grant update on table "app"."notifications" to "authenticated";

grant delete on table "app"."notifications" to "service_role";

grant insert on table "app"."notifications" to "service_role";

grant select on table "app"."notifications" to "service_role";

grant update on table "app"."notifications" to "service_role";

grant delete on table "app"."orders" to "anon";

grant insert on table "app"."orders" to "anon";

grant select on table "app"."orders" to "anon";

grant update on table "app"."orders" to "anon";

grant delete on table "app"."orders" to "authenticated";

grant insert on table "app"."orders" to "authenticated";

grant select on table "app"."orders" to "authenticated";

grant update on table "app"."orders" to "authenticated";

grant delete on table "app"."orders" to "service_role";

grant insert on table "app"."orders" to "service_role";

grant select on table "app"."orders" to "service_role";

grant update on table "app"."orders" to "service_role";

grant delete on table "app"."payment_events" to "anon";

grant insert on table "app"."payment_events" to "anon";

grant select on table "app"."payment_events" to "anon";

grant update on table "app"."payment_events" to "anon";

grant delete on table "app"."payment_events" to "authenticated";

grant insert on table "app"."payment_events" to "authenticated";

grant select on table "app"."payment_events" to "authenticated";

grant update on table "app"."payment_events" to "authenticated";

grant delete on table "app"."payment_events" to "service_role";

grant insert on table "app"."payment_events" to "service_role";

grant select on table "app"."payment_events" to "service_role";

grant update on table "app"."payment_events" to "service_role";

grant delete on table "app"."payments" to "anon";

grant insert on table "app"."payments" to "anon";

grant select on table "app"."payments" to "anon";

grant update on table "app"."payments" to "anon";

grant delete on table "app"."payments" to "authenticated";

grant insert on table "app"."payments" to "authenticated";

grant select on table "app"."payments" to "authenticated";

grant update on table "app"."payments" to "authenticated";

grant delete on table "app"."payments" to "service_role";

grant insert on table "app"."payments" to "service_role";

grant select on table "app"."payments" to "service_role";

grant update on table "app"."payments" to "service_role";

grant delete on table "app"."posts" to "anon";

grant insert on table "app"."posts" to "anon";

grant select on table "app"."posts" to "anon";

grant update on table "app"."posts" to "anon";

grant delete on table "app"."posts" to "authenticated";

grant insert on table "app"."posts" to "authenticated";

grant select on table "app"."posts" to "authenticated";

grant update on table "app"."posts" to "authenticated";

grant delete on table "app"."posts" to "service_role";

grant insert on table "app"."posts" to "service_role";

grant select on table "app"."posts" to "service_role";

grant update on table "app"."posts" to "service_role";

grant delete on table "app"."profiles" to "anon";

grant insert on table "app"."profiles" to "anon";

grant select on table "app"."profiles" to "anon";

grant update on table "app"."profiles" to "anon";

grant delete on table "app"."profiles" to "authenticated";

grant insert on table "app"."profiles" to "authenticated";

grant select on table "app"."profiles" to "authenticated";

grant update on table "app"."profiles" to "authenticated";

grant delete on table "app"."profiles" to "service_role";

grant insert on table "app"."profiles" to "service_role";

grant select on table "app"."profiles" to "service_role";

grant update on table "app"."profiles" to "service_role";

grant delete on table "app"."purchases" to "anon";

grant insert on table "app"."purchases" to "anon";

grant select on table "app"."purchases" to "anon";

grant update on table "app"."purchases" to "anon";

grant delete on table "app"."purchases" to "authenticated";

grant insert on table "app"."purchases" to "authenticated";

grant select on table "app"."purchases" to "authenticated";

grant update on table "app"."purchases" to "authenticated";

grant delete on table "app"."purchases" to "service_role";

grant insert on table "app"."purchases" to "service_role";

grant select on table "app"."purchases" to "service_role";

grant update on table "app"."purchases" to "service_role";

grant delete on table "app"."quiz_questions" to "anon";

grant insert on table "app"."quiz_questions" to "anon";

grant select on table "app"."quiz_questions" to "anon";

grant update on table "app"."quiz_questions" to "anon";

grant delete on table "app"."quiz_questions" to "authenticated";

grant insert on table "app"."quiz_questions" to "authenticated";

grant select on table "app"."quiz_questions" to "authenticated";

grant update on table "app"."quiz_questions" to "authenticated";

grant delete on table "app"."quiz_questions" to "service_role";

grant insert on table "app"."quiz_questions" to "service_role";

grant select on table "app"."quiz_questions" to "service_role";

grant update on table "app"."quiz_questions" to "service_role";

grant delete on table "app"."refresh_tokens" to "anon";

grant insert on table "app"."refresh_tokens" to "anon";

grant select on table "app"."refresh_tokens" to "anon";

grant update on table "app"."refresh_tokens" to "anon";

grant delete on table "app"."refresh_tokens" to "authenticated";

grant insert on table "app"."refresh_tokens" to "authenticated";

grant select on table "app"."refresh_tokens" to "authenticated";

grant update on table "app"."refresh_tokens" to "authenticated";

grant delete on table "app"."refresh_tokens" to "service_role";

grant insert on table "app"."refresh_tokens" to "service_role";

grant select on table "app"."refresh_tokens" to "service_role";

grant update on table "app"."refresh_tokens" to "service_role";

grant delete on table "app"."reviews" to "anon";

grant insert on table "app"."reviews" to "anon";

grant select on table "app"."reviews" to "anon";

grant update on table "app"."reviews" to "anon";

grant delete on table "app"."reviews" to "authenticated";

grant insert on table "app"."reviews" to "authenticated";

grant select on table "app"."reviews" to "authenticated";

grant update on table "app"."reviews" to "authenticated";

grant delete on table "app"."reviews" to "service_role";

grant insert on table "app"."reviews" to "service_role";

grant select on table "app"."reviews" to "service_role";

grant update on table "app"."reviews" to "service_role";

grant delete on table "app"."seminar_attendees" to "anon";

grant insert on table "app"."seminar_attendees" to "anon";

grant select on table "app"."seminar_attendees" to "anon";

grant update on table "app"."seminar_attendees" to "anon";

grant delete on table "app"."seminar_attendees" to "authenticated";

grant insert on table "app"."seminar_attendees" to "authenticated";

grant select on table "app"."seminar_attendees" to "authenticated";

grant update on table "app"."seminar_attendees" to "authenticated";

grant delete on table "app"."seminar_attendees" to "service_role";

grant insert on table "app"."seminar_attendees" to "service_role";

grant select on table "app"."seminar_attendees" to "service_role";

grant update on table "app"."seminar_attendees" to "service_role";

grant delete on table "app"."seminar_recordings" to "anon";

grant insert on table "app"."seminar_recordings" to "anon";

grant select on table "app"."seminar_recordings" to "anon";

grant update on table "app"."seminar_recordings" to "anon";

grant delete on table "app"."seminar_recordings" to "authenticated";

grant insert on table "app"."seminar_recordings" to "authenticated";

grant select on table "app"."seminar_recordings" to "authenticated";

grant update on table "app"."seminar_recordings" to "authenticated";

grant delete on table "app"."seminar_recordings" to "service_role";

grant insert on table "app"."seminar_recordings" to "service_role";

grant select on table "app"."seminar_recordings" to "service_role";

grant update on table "app"."seminar_recordings" to "service_role";

grant delete on table "app"."seminar_sessions" to "anon";

grant insert on table "app"."seminar_sessions" to "anon";

grant select on table "app"."seminar_sessions" to "anon";

grant update on table "app"."seminar_sessions" to "anon";

grant delete on table "app"."seminar_sessions" to "authenticated";

grant insert on table "app"."seminar_sessions" to "authenticated";

grant select on table "app"."seminar_sessions" to "authenticated";

grant update on table "app"."seminar_sessions" to "authenticated";

grant delete on table "app"."seminar_sessions" to "service_role";

grant insert on table "app"."seminar_sessions" to "service_role";

grant select on table "app"."seminar_sessions" to "service_role";

grant update on table "app"."seminar_sessions" to "service_role";

grant delete on table "app"."seminars" to "anon";

grant insert on table "app"."seminars" to "anon";

grant select on table "app"."seminars" to "anon";

grant update on table "app"."seminars" to "anon";

grant delete on table "app"."seminars" to "authenticated";

grant insert on table "app"."seminars" to "authenticated";

grant select on table "app"."seminars" to "authenticated";

grant update on table "app"."seminars" to "authenticated";

grant delete on table "app"."seminars" to "service_role";

grant insert on table "app"."seminars" to "service_role";

grant select on table "app"."seminars" to "service_role";

grant update on table "app"."seminars" to "service_role";

grant delete on table "app"."services" to "anon";

grant insert on table "app"."services" to "anon";

grant select on table "app"."services" to "anon";

grant update on table "app"."services" to "anon";

grant delete on table "app"."services" to "authenticated";

grant insert on table "app"."services" to "authenticated";

grant select on table "app"."services" to "authenticated";

grant update on table "app"."services" to "authenticated";

grant delete on table "app"."services" to "service_role";

grant insert on table "app"."services" to "service_role";

grant select on table "app"."services" to "service_role";

grant update on table "app"."services" to "service_role";

grant delete on table "app"."session_slots" to "anon";

grant insert on table "app"."session_slots" to "anon";

grant select on table "app"."session_slots" to "anon";

grant update on table "app"."session_slots" to "anon";

grant delete on table "app"."session_slots" to "authenticated";

grant insert on table "app"."session_slots" to "authenticated";

grant select on table "app"."session_slots" to "authenticated";

grant update on table "app"."session_slots" to "authenticated";

grant delete on table "app"."session_slots" to "service_role";

grant insert on table "app"."session_slots" to "service_role";

grant select on table "app"."session_slots" to "service_role";

grant update on table "app"."session_slots" to "service_role";

grant delete on table "app"."sessions" to "anon";

grant insert on table "app"."sessions" to "anon";

grant select on table "app"."sessions" to "anon";

grant update on table "app"."sessions" to "anon";

grant delete on table "app"."sessions" to "authenticated";

grant insert on table "app"."sessions" to "authenticated";

grant select on table "app"."sessions" to "authenticated";

grant update on table "app"."sessions" to "authenticated";

grant delete on table "app"."sessions" to "service_role";

grant insert on table "app"."sessions" to "service_role";

grant select on table "app"."sessions" to "service_role";

grant update on table "app"."sessions" to "service_role";

grant delete on table "app"."stripe_customers" to "anon";

grant insert on table "app"."stripe_customers" to "anon";

grant select on table "app"."stripe_customers" to "anon";

grant update on table "app"."stripe_customers" to "anon";

grant delete on table "app"."stripe_customers" to "authenticated";

grant insert on table "app"."stripe_customers" to "authenticated";

grant select on table "app"."stripe_customers" to "authenticated";

grant update on table "app"."stripe_customers" to "authenticated";

grant delete on table "app"."stripe_customers" to "service_role";

grant insert on table "app"."stripe_customers" to "service_role";

grant select on table "app"."stripe_customers" to "service_role";

grant update on table "app"."stripe_customers" to "service_role";

grant delete on table "app"."subscriptions" to "anon";

grant insert on table "app"."subscriptions" to "anon";

grant select on table "app"."subscriptions" to "anon";

grant update on table "app"."subscriptions" to "anon";

grant delete on table "app"."subscriptions" to "authenticated";

grant insert on table "app"."subscriptions" to "authenticated";

grant select on table "app"."subscriptions" to "authenticated";

grant update on table "app"."subscriptions" to "authenticated";

grant delete on table "app"."subscriptions" to "service_role";

grant insert on table "app"."subscriptions" to "service_role";

grant select on table "app"."subscriptions" to "service_role";

grant update on table "app"."subscriptions" to "service_role";

grant delete on table "app"."tarot_requests" to "anon";

grant insert on table "app"."tarot_requests" to "anon";

grant select on table "app"."tarot_requests" to "anon";

grant update on table "app"."tarot_requests" to "anon";

grant delete on table "app"."tarot_requests" to "authenticated";

grant insert on table "app"."tarot_requests" to "authenticated";

grant select on table "app"."tarot_requests" to "authenticated";

grant update on table "app"."tarot_requests" to "authenticated";

grant delete on table "app"."tarot_requests" to "service_role";

grant insert on table "app"."tarot_requests" to "service_role";

grant select on table "app"."tarot_requests" to "service_role";

grant update on table "app"."tarot_requests" to "service_role";

grant delete on table "app"."teacher_accounts" to "anon";

grant insert on table "app"."teacher_accounts" to "anon";

grant select on table "app"."teacher_accounts" to "anon";

grant update on table "app"."teacher_accounts" to "anon";

grant delete on table "app"."teacher_accounts" to "authenticated";

grant insert on table "app"."teacher_accounts" to "authenticated";

grant select on table "app"."teacher_accounts" to "authenticated";

grant update on table "app"."teacher_accounts" to "authenticated";

grant delete on table "app"."teacher_accounts" to "service_role";

grant insert on table "app"."teacher_accounts" to "service_role";

grant select on table "app"."teacher_accounts" to "service_role";

grant update on table "app"."teacher_accounts" to "service_role";

grant delete on table "app"."teacher_approvals" to "anon";

grant insert on table "app"."teacher_approvals" to "anon";

grant select on table "app"."teacher_approvals" to "anon";

grant update on table "app"."teacher_approvals" to "anon";

grant delete on table "app"."teacher_approvals" to "authenticated";

grant insert on table "app"."teacher_approvals" to "authenticated";

grant select on table "app"."teacher_approvals" to "authenticated";

grant update on table "app"."teacher_approvals" to "authenticated";

grant delete on table "app"."teacher_approvals" to "service_role";

grant insert on table "app"."teacher_approvals" to "service_role";

grant select on table "app"."teacher_approvals" to "service_role";

grant update on table "app"."teacher_approvals" to "service_role";

grant delete on table "app"."teacher_directory" to "anon";

grant insert on table "app"."teacher_directory" to "anon";

grant select on table "app"."teacher_directory" to "anon";

grant update on table "app"."teacher_directory" to "anon";

grant delete on table "app"."teacher_directory" to "authenticated";

grant insert on table "app"."teacher_directory" to "authenticated";

grant select on table "app"."teacher_directory" to "authenticated";

grant update on table "app"."teacher_directory" to "authenticated";

grant delete on table "app"."teacher_directory" to "service_role";

grant insert on table "app"."teacher_directory" to "service_role";

grant select on table "app"."teacher_directory" to "service_role";

grant update on table "app"."teacher_directory" to "service_role";

grant delete on table "app"."teacher_payout_methods" to "anon";

grant insert on table "app"."teacher_payout_methods" to "anon";

grant select on table "app"."teacher_payout_methods" to "anon";

grant update on table "app"."teacher_payout_methods" to "anon";

grant delete on table "app"."teacher_payout_methods" to "authenticated";

grant insert on table "app"."teacher_payout_methods" to "authenticated";

grant select on table "app"."teacher_payout_methods" to "authenticated";

grant update on table "app"."teacher_payout_methods" to "authenticated";

grant delete on table "app"."teacher_payout_methods" to "service_role";

grant insert on table "app"."teacher_payout_methods" to "service_role";

grant select on table "app"."teacher_payout_methods" to "service_role";

grant update on table "app"."teacher_payout_methods" to "service_role";

grant delete on table "app"."teacher_permissions" to "anon";

grant insert on table "app"."teacher_permissions" to "anon";

grant select on table "app"."teacher_permissions" to "anon";

grant update on table "app"."teacher_permissions" to "anon";

grant delete on table "app"."teacher_permissions" to "authenticated";

grant insert on table "app"."teacher_permissions" to "authenticated";

grant select on table "app"."teacher_permissions" to "authenticated";

grant update on table "app"."teacher_permissions" to "authenticated";

grant delete on table "app"."teacher_permissions" to "service_role";

grant insert on table "app"."teacher_permissions" to "service_role";

grant select on table "app"."teacher_permissions" to "service_role";

grant update on table "app"."teacher_permissions" to "service_role";

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

grant delete on table "app"."teachers" to "anon";

grant insert on table "app"."teachers" to "anon";

grant select on table "app"."teachers" to "anon";

grant update on table "app"."teachers" to "anon";

grant delete on table "app"."teachers" to "authenticated";

grant insert on table "app"."teachers" to "authenticated";

grant select on table "app"."teachers" to "authenticated";

grant update on table "app"."teachers" to "authenticated";

grant delete on table "app"."teachers" to "service_role";

grant insert on table "app"."teachers" to "service_role";

grant select on table "app"."teachers" to "service_role";

grant update on table "app"."teachers" to "service_role";

grant delete on table "app"."welcome_cards" to "anon";

grant insert on table "app"."welcome_cards" to "anon";

grant select on table "app"."welcome_cards" to "anon";

grant update on table "app"."welcome_cards" to "anon";

grant delete on table "app"."welcome_cards" to "authenticated";

grant insert on table "app"."welcome_cards" to "authenticated";

grant select on table "app"."welcome_cards" to "authenticated";

grant update on table "app"."welcome_cards" to "authenticated";

grant delete on table "app"."welcome_cards" to "service_role";

grant insert on table "app"."welcome_cards" to "service_role";

grant select on table "app"."welcome_cards" to "service_role";

grant update on table "app"."welcome_cards" to "service_role";


  create policy "classroom_messages_access"
  on "app"."classroom_messages"
  as permissive
  for all
  to authenticated
using (app.has_course_classroom_access(course_id, auth.uid()))
with check (app.has_course_classroom_access(course_id, auth.uid()));



  create policy "classroom_messages_service"
  on "app"."classroom_messages"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "classroom_presence_access"
  on "app"."classroom_presence"
  as permissive
  for all
  to authenticated
using (app.has_course_classroom_access(course_id, auth.uid()))
with check (app.has_course_classroom_access(course_id, auth.uid()));



  create policy "classroom_presence_service"
  on "app"."classroom_presence"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "course_entitlements_owner_read"
  on "app"."course_entitlements"
  as permissive
  for select
  to authenticated
using ((user_id = auth.uid()));



  create policy "course_entitlements_owner_update"
  on "app"."course_entitlements"
  as permissive
  for update
  to authenticated
using ((user_id = auth.uid()))
with check ((user_id = auth.uid()));



  create policy "course_entitlements_service_role"
  on "app"."course_entitlements"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "lesson_packages_owner"
  on "app"."lesson_packages"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM ((app.lessons l
     JOIN app.modules m ON ((m.id = l.module_id)))
     JOIN app.courses c ON ((c.id = m.course_id)))
  WHERE ((l.id = lesson_packages.lesson_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))))
with check ((EXISTS ( SELECT 1
   FROM ((app.lessons l
     JOIN app.modules m ON ((m.id = l.module_id)))
     JOIN app.courses c ON ((c.id = m.course_id)))
  WHERE ((l.id = lesson_packages.lesson_id) AND ((c.created_by = auth.uid()) OR app.is_admin(auth.uid()))))));



  create policy "lesson_packages_service_role"
  on "app"."lesson_packages"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "live_event_registrations_service"
  on "app"."live_event_registrations"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "live_events_service"
  on "app"."live_events"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."livekit_webhook_jobs"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "music_tracks_entitled_read"
  on "app"."music_tracks"
  as permissive
  for select
  to authenticated
using (((is_published = true) AND (((access_scope = 'membership'::text) AND (auth.uid() IS NOT NULL) AND ((EXISTS ( SELECT 1
   FROM app.memberships m
  WHERE ((m.user_id = auth.uid()) AND (lower(COALESCE(m.status, 'active'::text)) <> ALL (ARRAY['canceled'::text, 'unpaid'::text, 'incomplete_expired'::text, 'past_due'::text]))))) OR true)) OR ((access_scope = 'course'::text) AND (course_id IS NOT NULL) AND app.has_course_classroom_access(course_id, auth.uid())))));



  create policy "music_tracks_owner"
  on "app"."music_tracks"
  as permissive
  for all
  to authenticated
using (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())))
with check (((teacher_id = auth.uid()) OR app.is_admin(auth.uid())));



  create policy "music_tracks_service"
  on "app"."music_tracks"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."seminar_recordings"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "service_role_full_access"
  on "app"."seminar_sessions"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "teacher_accounts_self"
  on "app"."teacher_accounts"
  as permissive
  for all
  to authenticated
using (((auth.uid() = user_id) OR app.is_admin(auth.uid())))
with check (((auth.uid() = user_id) OR app.is_admin(auth.uid())));



  create policy "teacher_accounts_service_role"
  on "app"."teacher_accounts"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "welcome_cards_active_read"
  on "app"."welcome_cards"
  as permissive
  for select
  to authenticated
using ((is_active = true));



  create policy "welcome_cards_manage"
  on "app"."welcome_cards"
  as permissive
  for all
  to authenticated
using ((((created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM app.profiles p
  WHERE ((p.user_id = auth.uid()) AND ((p.role_v2 = 'teacher'::app.user_role) OR (p.is_admin = true)))))) OR app.is_admin(auth.uid())))
with check ((((created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM app.profiles p
  WHERE ((p.user_id = auth.uid()) AND ((p.role_v2 = 'teacher'::app.user_role) OR (p.is_admin = true)))))) OR app.is_admin(auth.uid())));



  create policy "welcome_cards_owner_read"
  on "app"."welcome_cards"
  as permissive
  for select
  to authenticated
using ((((created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM app.profiles p
  WHERE ((p.user_id = auth.uid()) AND ((p.role_v2 = 'teacher'::app.user_role) OR (p.is_admin = true)))))) OR app.is_admin(auth.uid())));



  create policy "welcome_cards_service_role"
  on "app"."welcome_cards"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));


CREATE TRIGGER trg_lesson_packages_updated BEFORE UPDATE ON app.lesson_packages FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_music_tracks_updated_at BEFORE UPDATE ON app.music_tracks FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_teacher_accounts_updated BEFORE UPDATE ON app.teacher_accounts FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_welcome_cards_updated_at BEFORE UPDATE ON app.welcome_cards FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


  create policy "storage_owner_private_rw"
  on "storage"."objects"
  as permissive
  for all
  to authenticated
using (((bucket_id = ANY (ARRAY['course-media'::text, 'lesson-media'::text, 'audio_private'::text, 'welcome-cards'::text])) AND (owner = auth.uid())))
with check (((bucket_id = ANY (ARRAY['course-media'::text, 'lesson-media'::text, 'audio_private'::text, 'welcome-cards'::text])) AND (owner = auth.uid())));



  create policy "storage_public_read_avatars_thumbnails"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = ANY (ARRAY['avatars'::text, 'thumbnails'::text])));



  create policy "storage_service_role_full_access"
  on "storage"."objects"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "storage_signed_private_read"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using ((bucket_id = ANY (ARRAY['course-media'::text, 'lesson-media'::text, 'audio_private'::text, 'welcome-cards'::text])));



