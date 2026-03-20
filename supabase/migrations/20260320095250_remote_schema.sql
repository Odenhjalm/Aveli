


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "app";


ALTER SCHEMA "app" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "app"."activity_kind" AS ENUM (
    'profile_updated',
    'course_published',
    'lesson_published',
    'service_created',
    'order_paid',
    'seminar_scheduled',
    'room_created',
    'participant_joined',
    'participant_left'
);


ALTER TYPE "app"."activity_kind" OWNER TO "postgres";


CREATE TYPE "app"."enrollment_source" AS ENUM (
    'free_intro',
    'purchase',
    'membership',
    'grant'
);


ALTER TYPE "app"."enrollment_source" OWNER TO "postgres";


CREATE TYPE "app"."event_participant_role" AS ENUM (
    'host',
    'participant'
);


ALTER TYPE "app"."event_participant_role" OWNER TO "postgres";


CREATE TYPE "app"."event_participant_status" AS ENUM (
    'registered',
    'cancelled',
    'attended',
    'no_show'
);


ALTER TYPE "app"."event_participant_status" OWNER TO "postgres";


CREATE TYPE "app"."event_status" AS ENUM (
    'draft',
    'scheduled',
    'live',
    'completed',
    'cancelled'
);


ALTER TYPE "app"."event_status" OWNER TO "postgres";


CREATE TYPE "app"."event_type" AS ENUM (
    'ceremony',
    'live_class',
    'course'
);


ALTER TYPE "app"."event_type" OWNER TO "postgres";


CREATE TYPE "app"."event_visibility" AS ENUM (
    'public',
    'members',
    'invited'
);


ALTER TYPE "app"."event_visibility" OWNER TO "postgres";


CREATE TYPE "app"."notification_audience_type" AS ENUM (
    'all_members',
    'event_participants',
    'course_participants',
    'course_members'
);


ALTER TYPE "app"."notification_audience_type" OWNER TO "postgres";


CREATE TYPE "app"."notification_channel" AS ENUM (
    'in_app',
    'email'
);


ALTER TYPE "app"."notification_channel" OWNER TO "postgres";


CREATE TYPE "app"."notification_delivery_status" AS ENUM (
    'pending',
    'sent',
    'failed'
);


ALTER TYPE "app"."notification_delivery_status" OWNER TO "postgres";


CREATE TYPE "app"."notification_status" AS ENUM (
    'pending',
    'sent',
    'failed'
);


ALTER TYPE "app"."notification_status" OWNER TO "postgres";


CREATE TYPE "app"."notification_type" AS ENUM (
    'manual',
    'scheduled',
    'system'
);


ALTER TYPE "app"."notification_type" OWNER TO "postgres";


CREATE TYPE "app"."order_status" AS ENUM (
    'pending',
    'requires_action',
    'processing',
    'paid',
    'canceled',
    'failed',
    'refunded'
);


ALTER TYPE "app"."order_status" OWNER TO "postgres";


CREATE TYPE "app"."order_type" AS ENUM (
    'one_off',
    'subscription',
    'bundle'
);


ALTER TYPE "app"."order_type" OWNER TO "postgres";


CREATE TYPE "app"."payment_status" AS ENUM (
    'pending',
    'processing',
    'paid',
    'failed',
    'refunded'
);


ALTER TYPE "app"."payment_status" OWNER TO "postgres";


CREATE TYPE "app"."profile_role" AS ENUM (
    'student',
    'teacher',
    'admin'
);


ALTER TYPE "app"."profile_role" OWNER TO "postgres";


CREATE TYPE "app"."review_visibility" AS ENUM (
    'public',
    'private'
);


ALTER TYPE "app"."review_visibility" OWNER TO "postgres";


CREATE TYPE "app"."seminar_session_status" AS ENUM (
    'scheduled',
    'live',
    'ended',
    'failed'
);


ALTER TYPE "app"."seminar_session_status" OWNER TO "postgres";


CREATE TYPE "app"."seminar_status" AS ENUM (
    'draft',
    'scheduled',
    'live',
    'ended',
    'canceled'
);


ALTER TYPE "app"."seminar_status" OWNER TO "postgres";


CREATE TYPE "app"."service_status" AS ENUM (
    'draft',
    'active',
    'paused',
    'archived'
);


ALTER TYPE "app"."service_status" OWNER TO "postgres";


CREATE TYPE "app"."session_visibility" AS ENUM (
    'draft',
    'published'
);


ALTER TYPE "app"."session_visibility" OWNER TO "postgres";


CREATE TYPE "app"."user_role" AS ENUM (
    'user',
    'professional',
    'teacher'
);


ALTER TYPE "app"."user_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."can_access_seminar"("p_seminar_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select app.can_access_seminar(p_seminar_id, auth.uid());
$$;


ALTER FUNCTION "app"."can_access_seminar"("p_seminar_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."can_access_seminar"("p_seminar_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select
    app.is_seminar_host(p_seminar_id, p_user_id)
    or app.is_seminar_attendee(p_seminar_id, p_user_id);
$$;


ALTER FUNCTION "app"."can_access_seminar"("p_seminar_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."enforce_event_status_progression"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  old_rank integer;
  new_rank integer;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.status = new.status then
    return new;
  end if;

  if old.status = 'cancelled' then
    raise exception 'Event status cannot be changed after cancellation';
  end if;

  old_rank := case old.status
    when 'draft' then 1
    when 'scheduled' then 2
    when 'live' then 3
    when 'completed' then 4
    when 'cancelled' then 5
    else null
  end;

  new_rank := case new.status
    when 'draft' then 1
    when 'scheduled' then 2
    when 'live' then 3
    when 'completed' then 4
    when 'cancelled' then 5
    else null
  end;

  if old_rank is null or new_rank is null then
    raise exception 'Invalid event status transition';
  end if;

  
  if new.status = 'cancelled' then
    return new;
  end if;

  if old.status = 'completed' then
    raise exception 'Event status cannot be changed after completion';
  end if;

  if new_rank < old_rank then
    raise exception 'Event status cannot move backwards (% -> %)', old.status, new.status;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "app"."enforce_event_status_progression"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."grade_quiz_and_issue_certificate"("p_quiz_id" "uuid", "p_user_id" "uuid", "p_answers" "jsonb") RETURNS TABLE("passed" boolean, "score" "text", "correct_count" integer, "question_count" integer, "pass_score" integer, "certificate_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'app', 'public'
    AS $_$
declare
  v_user_id uuid;
  v_course_id uuid;
  v_course_title text;
  v_pass_score integer;
  v_correct_count integer := 0;
  v_question_count integer := 0;
  v_score_percent integer := 0;
  v_certificate_id uuid;
  v_answer jsonb;
  v_expected_text text;
  v_expected_int integer;
  v_expected_bool boolean;
  v_expected_arr integer[];
  v_given_int integer;
  v_given_bool boolean;
  v_given_arr integer[];
  caller_role text := auth.role();
  caller_uid uuid := auth.uid();
  q record;
begin
  -- Resolve caller -> user id mapping.
  if caller_role is null then
    v_user_id := p_user_id;
  elsif caller_role = 'service_role' then
    v_user_id := coalesce(p_user_id, caller_uid);
  else
    if caller_uid is null then
      raise insufficient_privilege using message = 'authenticated user required';
    end if;
    if p_user_id is not null and p_user_id <> caller_uid then
      raise insufficient_privilege using message = 'cannot grade for other users';
    end if;
    v_user_id := caller_uid;
  end if;

  if v_user_id is null then
    raise exception 'user_id is required';
  end if;

  select cq.course_id, cq.pass_score, c.title
    into v_course_id, v_pass_score, v_course_title
  from app.course_quizzes cq
  join app.courses c on c.id = cq.course_id
  where cq.id = p_quiz_id;

  if v_course_id is null then
    return query select false, '0%', 0, 0, 0, null::uuid;
    return;
  end if;

  if v_pass_score is null then
    v_pass_score := 0;
  end if;

  for q in
    select id, kind, correct
    from app.quiz_questions
    where quiz_id = p_quiz_id
    order by position
  loop
    v_question_count := v_question_count + 1;
    v_answer := p_answers -> q.id::text;
    v_expected_text := q.correct;

    if q.kind = 'single' then
      v_expected_int := null;
      if v_expected_text is not null and v_expected_text <> '' then
        begin
          v_expected_int := v_expected_text::int;
        exception when others then
          v_expected_int := null;
        end;
      end if;

      v_given_int := null;
      if v_answer is not null then
        begin
          v_given_int := (v_answer #>> '{}')::int;
        exception when others then
          v_given_int := null;
        end;
      end if;

      if v_expected_int is not null and v_given_int is not null and v_expected_int = v_given_int then
        v_correct_count := v_correct_count + 1;
      end if;
    elsif q.kind = 'multi' then
      v_expected_arr := null;
      if v_expected_text is not null and v_expected_text <> '' then
        v_expected_arr := string_to_array(
          regexp_replace(v_expected_text, '[^0-9,]', '', 'g'),
          ','
        )::int[];
      end if;

      v_given_arr := null;
      if v_answer is not null and jsonb_typeof(v_answer) = 'array' then
        select array_agg(distinct value::int order by value::int)
          into v_given_arr
        from jsonb_array_elements_text(v_answer) as value
        where value ~ '^-?\\d+$';
      end if;

      if v_expected_arr is not null then
        select array_agg(distinct value order by value)
          into v_expected_arr
        from unnest(v_expected_arr) as value;
      end if;

      if v_expected_arr is not null and v_given_arr is not null then
        if array_length(v_expected_arr, 1) = array_length(v_given_arr, 1)
           and v_expected_arr <@ v_given_arr
           and v_given_arr <@ v_expected_arr then
          v_correct_count := v_correct_count + 1;
        end if;
      end if;
    else
      v_expected_bool := null;
      if v_expected_text is not null then
        v_expected_bool := lower(v_expected_text) in ('true', 't', '1', 'yes');
      end if;

      v_given_bool := null;
      if v_answer is not null then
        begin
          v_given_bool := (v_answer #>> '{}')::boolean;
        exception when others then
          v_given_bool := null;
        end;
      end if;

      if v_expected_bool is not null and v_given_bool is not null and v_expected_bool = v_given_bool then
        v_correct_count := v_correct_count + 1;
      end if;
    end if;
  end loop;

  if v_question_count > 0 then
    v_score_percent := round(v_correct_count::numeric * 100 / v_question_count)::int;
  else
    v_score_percent := 0;
  end if;

  passed := v_score_percent >= v_pass_score;

  if passed then
    select id
      into v_certificate_id
      from app.certificates
     where user_id = v_user_id
       and course_id = v_course_id
     limit 1;

    if v_certificate_id is null then
      insert into app.certificates (
        user_id,
        course_id,
        title,
        status,
        issued_at,
        metadata,
        created_at,
        updated_at
      )
      values (
        v_user_id,
        v_course_id,
        coalesce(v_course_title, 'Course certificate'),
        'verified',
        now(),
        jsonb_build_object(
          'score_percent', v_score_percent,
          'correct_count', v_correct_count,
          'question_count', v_question_count,
          'pass_score', v_pass_score
        ),
        now(),
        now()
      )
      returning id into v_certificate_id;
    else
      update app.certificates
         set status = 'verified',
             issued_at = coalesce(issued_at, now()),
             metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
               'score_percent', v_score_percent,
               'correct_count', v_correct_count,
               'question_count', v_question_count,
               'pass_score', v_pass_score
             ),
             updated_at = now()
       where id = v_certificate_id;
    end if;
  end if;

  return query
    select passed,
           (v_score_percent::text || '%') as score,
           v_correct_count,
           v_question_count,
           v_pass_score,
           v_certificate_id;
end;
$_$;


ALTER FUNCTION "app"."grade_quiz_and_issue_certificate"("p_quiz_id" "uuid", "p_user_id" "uuid", "p_answers" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."has_course_classroom_access"("p_course_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql"
    AS $$
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
$$;


ALTER FUNCTION "app"."has_course_classroom_access"("p_course_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."is_admin"("p_user" "uuid") RETURNS boolean
    LANGUAGE "sql"
    AS $$
  select exists (
    select 1 from app.profiles
    where user_id = p_user and is_admin = true
  );
$$;


ALTER FUNCTION "app"."is_admin"("p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."is_seminar_attendee"("p_seminar_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select app.is_seminar_attendee(p_seminar_id, auth.uid());
$$;


ALTER FUNCTION "app"."is_seminar_attendee"("p_seminar_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."is_seminar_attendee"("p_seminar_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql"
    AS $$
  select exists(
    select 1
    from app.seminar_attendees sa
    where sa.seminar_id = p_seminar_id
      and sa.user_id = p_user_id
  );
$$;


ALTER FUNCTION "app"."is_seminar_attendee"("p_seminar_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."is_seminar_host"("p_seminar_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select app.is_seminar_host(p_seminar_id, auth.uid());
$$;


ALTER FUNCTION "app"."is_seminar_host"("p_seminar_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."is_seminar_host"("p_seminar_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    AS $$
begin
  if auth.role() <> 'service_role' and auth.uid() is distinct from p_user_id then
    raise insufficient_privilege using message = 'cannot check host status for other users';
  end if;

  return exists(
    select 1 from app.seminars s
    where s.id = p_seminar_id
      and s.host_id = p_user_id
  );
end;
$$;


ALTER FUNCTION "app"."is_seminar_host"("p_seminar_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."is_teacher"("p_user" "uuid") RETURNS boolean
    LANGUAGE "sql"
    AS $$
  select
    app.is_admin(p_user)
    or exists (
      select 1
      from app.profiles p
      where p.user_id = p_user
        and coalesce(p.role_v2, 'user')::text in ('teacher', 'admin')
    )
    or exists (
      select 1
      from app.teacher_permissions tp
      where tp.profile_id = p_user
        and (tp.can_edit_courses = true or tp.can_publish = true)
    )
    or exists (
      select 1
      from app.teacher_approvals ta
      where ta.user_id = p_user
        and ta.approved_at is not null
    );
$$;


ALTER FUNCTION "app"."is_teacher"("p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."normalize_runtime_media_kind"("raw_kind" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case lower(coalesce(trim(raw_kind), 'other'))
    when 'audio' then 'audio'
    when 'video' then 'video'
    when 'image' then 'image'
    when 'pdf' then 'document'
    when 'document' then 'document'
    else 'other'
  end
$$;


ALTER FUNCTION "app"."normalize_runtime_media_kind"("raw_kind" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."runtime_media_lesson_fallback_policy"("lesson_kind" "text", "media_asset_id" "uuid", "media_object_id" "uuid", "legacy_storage_path" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case
    when media_asset_id is null then 'legacy_only'
    when lower(coalesce(trim(lesson_kind), '')) = 'audio' then 'never'
    when media_object_id is not null then 'if_no_ready_asset'
    when nullif(trim(legacy_storage_path), '') is not null then 'if_no_ready_asset'
    else 'never'
  end
$$;


ALTER FUNCTION "app"."runtime_media_lesson_fallback_policy"("lesson_kind" "text", "media_asset_id" "uuid", "media_object_id" "uuid", "legacy_storage_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "app"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."sync_runtime_media_course_context_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  where l.course_id = new.id;
  return new;
end;
$$;


ALTER FUNCTION "app"."sync_runtime_media_course_context_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."sync_runtime_media_lesson_context_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm
  where lm.lesson_id = new.id;
  return new;
end;
$$;


ALTER FUNCTION "app"."sync_runtime_media_lesson_context_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."sync_runtime_media_lesson_media_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  perform app.upsert_runtime_media_for_lesson_media(new.id);
  return new;
end;
$$;


ALTER FUNCTION "app"."sync_runtime_media_lesson_media_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."touch_course_display_priorities"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "app"."touch_course_display_priorities"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."touch_course_entitlements"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end; $$;


ALTER FUNCTION "app"."touch_course_entitlements"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."touch_events"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "app"."touch_events"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."touch_home_player_course_links"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "app"."touch_home_player_course_links"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."touch_home_player_uploads"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "app"."touch_home_player_uploads"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."touch_intro_usage"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "app"."touch_intro_usage"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."touch_livekit_webhook_jobs"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    begin
      new.updated_at = now();
      return new;
    end;
    $$;


ALTER FUNCTION "app"."touch_livekit_webhook_jobs"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."touch_teacher_profile_media"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "app"."touch_teacher_profile_media"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "app"."upsert_runtime_media_for_lesson_media"("target_lesson_media_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
declare
  runtime_id uuid;
begin
  insert into app.runtime_media (
    reference_type,
    auth_scope,
    fallback_policy,
    lesson_media_id,
    teacher_id,
    course_id,
    lesson_id,
    media_asset_id,
    media_object_id,
    legacy_storage_bucket,
    legacy_storage_path,
    kind,
    active,
    created_at,
    updated_at
  )
  select
    'lesson_media',
    'lesson_course',
    app.runtime_media_lesson_fallback_policy(
      lm.kind,
      lm.media_asset_id,
      lm.media_id,
      lm.storage_path
    ),
    lm.id,
    coalesce(c.created_by, ma.owner_id, mo.owner_id),
    l.course_id,
    lm.lesson_id,
    lm.media_asset_id,
    lm.media_id,
    case
      when nullif(trim(lm.storage_path), '') is not null
        then coalesce(nullif(trim(lm.storage_bucket), ''), 'lesson-media')
      else null
    end,
    nullif(trim(lm.storage_path), ''),
    app.normalize_runtime_media_kind(lm.kind),
    true,
    coalesce(lm.created_at, now()),
    now()
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  join app.courses c on c.id = l.course_id
  left join app.media_objects mo on mo.id = lm.media_id
  left join app.media_assets ma on ma.id = lm.media_asset_id
  where lm.id = target_lesson_media_id
  on conflict (lesson_media_id) do update
    set reference_type = excluded.reference_type,
        auth_scope = excluded.auth_scope,
        fallback_policy = excluded.fallback_policy,
        teacher_id = excluded.teacher_id,
        course_id = excluded.course_id,
        lesson_id = excluded.lesson_id,
        media_asset_id = excluded.media_asset_id,
        media_object_id = excluded.media_object_id,
        legacy_storage_bucket = excluded.legacy_storage_bucket,
        legacy_storage_path = excluded.legacy_storage_path,
        kind = excluded.kind,
        active = excluded.active,
        updated_at = now()
  returning id into runtime_id;

  return runtime_id;
end;
$$;


ALTER FUNCTION "app"."upsert_runtime_media_for_lesson_media"("target_lesson_media_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "app"."seminars" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "host_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "status" "app"."seminar_status" DEFAULT 'draft'::"app"."seminar_status" NOT NULL,
    "scheduled_at" timestamp with time zone,
    "duration_minutes" integer,
    "livekit_room" "text",
    "livekit_metadata" "jsonb",
    "recording_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."seminars" OWNER TO "postgres";


COMMENT ON TABLE "app"."seminars" IS 'RLS placeholder: allow public read of scheduled/live/ended seminars, host-owned writes, admin override.';



CREATE OR REPLACE FUNCTION "public"."rest_insert_seminar"("p_host_id" "uuid", "p_title" "text", "p_status" "app"."seminar_status") RETURNS "app"."seminars"
    LANGUAGE "plpgsql"
    AS $$
declare
  created_row app.seminars%rowtype;
begin
  insert into app.seminars (host_id, title, status)
  values (p_host_id, p_title, p_status)
  returning * into created_row;

  return created_row;
end;
$$;


ALTER FUNCTION "public"."rest_insert_seminar"("p_host_id" "uuid", "p_title" "text", "p_status" "app"."seminar_status") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rest_select_seminar"("p_seminar_id" "uuid") RETURNS SETOF "app"."seminars"
    LANGUAGE "sql" STABLE
    AS $$
  select *
  from app.seminars
  where id = p_seminar_id;
$$;


ALTER FUNCTION "public"."rest_select_seminar"("p_seminar_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."seminar_attendees" (
    "seminar_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'participant'::"text" NOT NULL,
    "joined_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "invite_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "left_at" timestamp with time zone,
    "livekit_identity" "text",
    "livekit_participant_sid" "text",
    "livekit_room" "text"
);


ALTER TABLE "app"."seminar_attendees" OWNER TO "postgres";


COMMENT ON TABLE "app"."seminar_attendees" IS 'RLS placeholder: attendees may insert/delete themselves, host/admin manage all.';



CREATE OR REPLACE FUNCTION "public"."rest_select_seminar_attendees"("p_seminar_id" "uuid") RETURNS SETOF "app"."seminar_attendees"
    LANGUAGE "sql" STABLE
    AS $$
  select *
  from app.seminar_attendees
  where seminar_id = p_seminar_id;
$$;


ALTER FUNCTION "public"."rest_select_seminar_attendees"("p_seminar_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rest_update_seminar_description"("p_seminar_id" "uuid", "p_description" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."rest_update_seminar_description"("p_seminar_id" "uuid", "p_description" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."activities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "activity_type" "app"."activity_kind" NOT NULL,
    "actor_id" "uuid",
    "subject_table" "text" NOT NULL,
    "subject_id" "uuid",
    "summary" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."activities" OWNER TO "postgres";


CREATE OR REPLACE VIEW "app"."activities_feed" AS
 SELECT "id",
    "activity_type",
    "actor_id",
    "subject_table",
    "subject_id",
    "summary",
    "metadata",
    "occurred_at"
   FROM "app"."activities" "a";


ALTER VIEW "app"."activities_feed" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."app_config" (
    "id" integer DEFAULT 1 NOT NULL,
    "free_course_limit" integer DEFAULT 5 NOT NULL,
    "platform_fee_pct" numeric DEFAULT 10 NOT NULL
);


ALTER TABLE "app"."app_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."auth_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "email" "text",
    "event" "text" NOT NULL,
    "ip_address" "inet",
    "user_agent" "text",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."auth_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."billing_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "step" "text",
    "info" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "app"."billing_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."certificates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "course_id" "uuid",
    "title" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "notes" "text",
    "evidence_url" "text",
    "issued_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."certificates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."classroom_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "message" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."classroom_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."classroom_presence" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "last_seen" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."classroom_presence" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."course_bundle_courses" (
    "bundle_id" "uuid" NOT NULL,
    "course_id" "uuid" NOT NULL,
    "position" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "app"."course_bundle_courses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."course_bundles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "stripe_product_id" "text",
    "stripe_price_id" "text",
    "price_amount_cents" integer DEFAULT 0 NOT NULL,
    "currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."course_bundles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."course_display_priorities" (
    "teacher_id" "uuid" NOT NULL,
    "priority" integer DEFAULT 1000 NOT NULL,
    "notes" "text",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."course_display_priorities" OWNER TO "postgres";


COMMENT ON TABLE "app"."course_display_priorities" IS 'Controls teacher ordering in course listings and marketing blocks.';



CREATE TABLE IF NOT EXISTS "app"."courses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "cover_url" "text",
    "video_url" "text",
    "branch" "text",
    "is_free_intro" boolean DEFAULT false NOT NULL,
    "price_cents" integer DEFAULT 0 NOT NULL,
    "currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "is_published" boolean DEFAULT false NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stripe_product_id" "text",
    "stripe_price_id" "text",
    "price_amount_cents" integer DEFAULT 0 NOT NULL,
    "cover_media_id" "uuid",
    "journey_step" "text" DEFAULT 'intro'::"text",
    CONSTRAINT "courses_journey_step_check" CHECK (("journey_step" = ANY (ARRAY['intro'::"text", 'step1'::"text", 'step2'::"text", 'step3'::"text"])))
);


ALTER TABLE "app"."courses" OWNER TO "postgres";


COMMENT ON TABLE "app"."courses" IS 'RLS placeholder: course authors (created_by) + admins may manage records; public read for published courses.';



CREATE TABLE IF NOT EXISTS "app"."entitlements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "course_id" "uuid" NOT NULL,
    "source" "text" NOT NULL,
    "stripe_session_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "entitlements_source_check" CHECK (("source" = ANY (ARRAY['purchase'::"text", 'subscription'::"text", 'admin'::"text"])))
);


ALTER TABLE "app"."entitlements" OWNER TO "postgres";


CREATE OR REPLACE VIEW "app"."course_enrollments_view" AS
 SELECT "e"."user_id",
    "e"."course_id",
    "c"."title" AS "course_title",
    "e"."source" AS "purchase_source",
    "e"."created_at"
   FROM ("app"."entitlements" "e"
     JOIN "app"."courses" "c" ON (("c"."id" = "e"."course_id")));


ALTER VIEW "app"."course_enrollments_view" OWNER TO "postgres";


COMMENT ON VIEW "app"."course_enrollments_view" IS 'Derived enrollments from entitlements with course metadata.';



CREATE TABLE IF NOT EXISTS "app"."course_entitlements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "course_slug" "text" NOT NULL,
    "stripe_customer_id" "text",
    "stripe_payment_intent_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "app"."course_entitlements" FORCE ROW LEVEL SECURITY;


ALTER TABLE "app"."course_entitlements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."course_products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "stripe_product_id" "text" NOT NULL,
    "stripe_price_id" "text" NOT NULL,
    "price_amount" integer NOT NULL,
    "price_currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."course_products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."course_quizzes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "title" "text",
    "pass_score" integer DEFAULT 80 NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."course_quizzes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."enrollments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "course_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "source" "app"."enrollment_source" DEFAULT 'purchase'::"app"."enrollment_source" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."enrollments" OWNER TO "postgres";


COMMENT ON TABLE "app"."enrollments" IS 'RLS placeholder: user_id rows visible to the learner, course owners, and admins.';



CREATE TABLE IF NOT EXISTS "app"."event_participants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "app"."event_participant_role" DEFAULT 'participant'::"app"."event_participant_role" NOT NULL,
    "status" "app"."event_participant_status" DEFAULT 'registered'::"app"."event_participant_status" NOT NULL,
    "registered_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."event_participants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type" "app"."event_type" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "image_id" "uuid",
    "start_at" timestamp with time zone NOT NULL,
    "end_at" timestamp with time zone NOT NULL,
    "timezone" "text" NOT NULL,
    "status" "app"."event_status" DEFAULT 'draft'::"app"."event_status" NOT NULL,
    "visibility" "app"."event_visibility" DEFAULT 'invited'::"app"."event_visibility" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "events_end_after_start" CHECK (("end_at" > "start_at")),
    CONSTRAINT "events_timezone_not_empty" CHECK (("length"(TRIM(BOTH FROM "timezone")) > 0)),
    CONSTRAINT "events_title_not_empty" CHECK (("length"(TRIM(BOTH FROM "title")) > 0))
);


ALTER TABLE "app"."events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."follows" (
    "follower_id" "uuid" NOT NULL,
    "followee_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."follows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."guest_claim_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "token" "text" NOT NULL,
    "purchase_id" "uuid",
    "course_id" "uuid",
    "used" boolean DEFAULT false NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."guest_claim_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."home_player_course_links" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "lesson_media_id" "uuid",
    "title" "text" NOT NULL,
    "course_title_snapshot" "text" DEFAULT ''::"text" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."home_player_course_links" OWNER TO "postgres";


COMMENT ON TABLE "app"."home_player_course_links" IS 'Explicit course-media links for the Home player (no file ownership).';



CREATE TABLE IF NOT EXISTS "app"."home_player_uploads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "media_id" "uuid",
    "title" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "media_asset_id" "uuid",
    CONSTRAINT "home_player_uploads_kind_check" CHECK (("kind" = ANY (ARRAY['audio'::"text", 'video'::"text"]))),
    CONSTRAINT "home_player_uploads_media_ref_check" CHECK ((("media_id" IS NULL) <> ("media_asset_id" IS NULL)))
);


ALTER TABLE "app"."home_player_uploads" OWNER TO "postgres";


COMMENT ON TABLE "app"."home_player_uploads" IS 'Teacher-owned uploads dedicated to the Home player (independent of courses).';



CREATE TABLE IF NOT EXISTS "app"."intro_usage" (
    "user_id" "uuid" NOT NULL,
    "year" integer NOT NULL,
    "month" integer NOT NULL,
    "count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "intro_usage_count_check" CHECK (("count" >= 0)),
    CONSTRAINT "intro_usage_month_check" CHECK ((("month" >= 1) AND ("month" <= 12))),
    CONSTRAINT "intro_usage_year_check" CHECK ((("year" >= 2000) AND ("year" <= 9999)))
);


ALTER TABLE "app"."intro_usage" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."lesson_media" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "media_id" "uuid",
    "storage_path" "text",
    "storage_bucket" "text" DEFAULT 'lesson-media'::"text" NOT NULL,
    "duration_seconds" integer,
    "position" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "media_asset_id" "uuid",
    CONSTRAINT "lesson_media_kind_check" CHECK (("kind" = ANY (ARRAY['video'::"text", 'audio'::"text", 'image'::"text", 'pdf'::"text", 'other'::"text"]))),
    CONSTRAINT "lesson_media_path_or_object" CHECK ((("media_id" IS NOT NULL) OR ("storage_path" IS NOT NULL) OR ("media_asset_id" IS NOT NULL)))
);


ALTER TABLE "app"."lesson_media" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."lesson_media_issues" (
    "lesson_media_id" "uuid" NOT NULL,
    "issue" "text" NOT NULL,
    "details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "lesson_media_issues_issue_check" CHECK (("issue" = ANY (ARRAY['missing_object'::"text", 'bucket_mismatch'::"text", 'key_format_drift'::"text", 'unsupported'::"text"])))
);


ALTER TABLE "app"."lesson_media_issues" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."lesson_packages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "stripe_product_id" "text" NOT NULL,
    "stripe_price_id" "text" NOT NULL,
    "price_amount" integer NOT NULL,
    "price_currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."lesson_packages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."lessons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "content_markdown" "text",
    "video_url" "text",
    "duration_seconds" integer,
    "is_intro" boolean DEFAULT false NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "price_amount_cents" integer DEFAULT 0 NOT NULL,
    "price_currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "course_id" "uuid" NOT NULL
);


ALTER TABLE "app"."lessons" OWNER TO "postgres";


COMMENT ON TABLE "app"."lessons" IS 'RLS placeholder: restrict lesson access to course owners and enrolled users once RLS is enabled.';



CREATE TABLE IF NOT EXISTS "app"."live_event_registrations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."live_event_registrations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."live_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "scheduled_at" timestamp with time zone NOT NULL,
    "room_name" "text" NOT NULL,
    "access_type" "text" NOT NULL,
    "course_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "starts_at" timestamp with time zone,
    "ends_at" timestamp with time zone,
    "is_published" boolean DEFAULT false NOT NULL,
    CONSTRAINT "live_events_access_type_check" CHECK (("access_type" = ANY (ARRAY['membership'::"text", 'course'::"text"])))
);


ALTER TABLE "app"."live_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."livekit_webhook_jobs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "attempt" integer DEFAULT 0 NOT NULL,
    "last_error" "text",
    "scheduled_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "locked_at" timestamp with time zone,
    "last_attempt_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "next_run_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."livekit_webhook_jobs" OWNER TO "postgres";


COMMENT ON TABLE "app"."livekit_webhook_jobs" IS 'Persistent job queue for LiveKit event handling.';



CREATE TABLE IF NOT EXISTS "app"."media_assets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid",
    "course_id" "uuid",
    "lesson_id" "uuid",
    "media_type" "text" NOT NULL,
    "ingest_format" "text" NOT NULL,
    "original_object_path" "text" NOT NULL,
    "original_content_type" "text",
    "original_filename" "text",
    "original_size_bytes" bigint,
    "storage_bucket" "text" DEFAULT 'course-media'::"text" NOT NULL,
    "streaming_object_path" "text",
    "streaming_format" "text",
    "duration_seconds" integer,
    "codec" "text",
    "state" "text" NOT NULL,
    "error_message" "text",
    "processing_attempts" integer DEFAULT 0 NOT NULL,
    "processing_locked_at" timestamp with time zone,
    "next_retry_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "purpose" "text" DEFAULT 'lesson_audio'::"text" NOT NULL,
    "streaming_storage_bucket" "text",
    CONSTRAINT "media_assets_media_type_check" CHECK (("media_type" = ANY (ARRAY['audio'::"text", 'document'::"text", 'image'::"text", 'video'::"text"]))),
    CONSTRAINT "media_assets_purpose_check" CHECK (("purpose" = ANY (ARRAY['lesson_audio'::"text", 'course_cover'::"text", 'home_player_audio'::"text", 'lesson_media'::"text"]))),
    CONSTRAINT "media_assets_state_check" CHECK (("state" = ANY (ARRAY['pending_upload'::"text", 'uploaded'::"text", 'processing'::"text", 'ready'::"text", 'failed'::"text"])))
);


ALTER TABLE "app"."media_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."media_objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid",
    "storage_path" "text" NOT NULL,
    "storage_bucket" "text" DEFAULT 'lesson-media'::"text" NOT NULL,
    "content_type" "text",
    "byte_size" bigint DEFAULT 0 NOT NULL,
    "checksum" "text",
    "original_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."media_objects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."media_resolution_failures" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "lesson_media_id" "uuid",
    "mode" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "app"."media_resolution_failures" OWNER TO "postgres";


ALTER TABLE "app"."media_resolution_failures" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "app"."media_resolution_failures_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "app"."meditations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "teacher_id" "uuid",
    "media_id" "uuid",
    "audio_path" "text",
    "duration_seconds" integer,
    "is_public" boolean DEFAULT false NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."meditations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."memberships" (
    "membership_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "plan_interval" "text" NOT NULL,
    "price_id" "text" NOT NULL,
    "stripe_customer_id" "text",
    "stripe_subscription_id" "text",
    "start_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "end_date" timestamp with time zone,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "memberships_plan_interval_check" CHECK (("plan_interval" = ANY (ARRAY['month'::"text", 'year'::"text"])))
);


ALTER TABLE "app"."memberships" OWNER TO "postgres";


COMMENT ON TABLE "app"."memberships" IS 'Stripe billing memberships for subscription access';



CREATE TABLE IF NOT EXISTS "app"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "channel" "text",
    "sender_id" "uuid",
    "recipient_id" "uuid",
    "content" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."music_tracks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "duration_seconds" integer,
    "storage_path" "text" NOT NULL,
    "cover_image_path" "text",
    "access_scope" "text" NOT NULL,
    "course_id" "uuid",
    "is_published" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "music_tracks_access_scope_check" CHECK (("access_scope" = ANY (ARRAY['membership'::"text", 'course'::"text"]))),
    CONSTRAINT "music_tracks_scope_course" CHECK (((("access_scope" = 'course'::"text") AND ("course_id" IS NOT NULL)) OR (("access_scope" = 'membership'::"text") AND ("course_id" IS NULL))))
);


ALTER TABLE "app"."music_tracks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."notification_audiences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "notification_id" "uuid" NOT NULL,
    "audience_type" "app"."notification_audience_type" NOT NULL,
    "event_id" "uuid",
    "course_id" "uuid",
    CONSTRAINT "notification_audiences_target_check" CHECK (((("audience_type" = 'all_members'::"app"."notification_audience_type") AND ("event_id" IS NULL) AND ("course_id" IS NULL)) OR (("audience_type" = 'event_participants'::"app"."notification_audience_type") AND ("event_id" IS NOT NULL) AND ("course_id" IS NULL)) OR (("audience_type" = ANY (ARRAY['course_participants'::"app"."notification_audience_type", 'course_members'::"app"."notification_audience_type"])) AND ("course_id" IS NOT NULL) AND ("event_id" IS NULL))))
);


ALTER TABLE "app"."notification_audiences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."notification_campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type" "app"."notification_type" DEFAULT 'manual'::"app"."notification_type" NOT NULL,
    "channel" "app"."notification_channel" DEFAULT 'in_app'::"app"."notification_channel" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "send_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "status" "app"."notification_status" DEFAULT 'pending'::"app"."notification_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_campaigns_body_not_empty" CHECK (("length"(TRIM(BOTH FROM "body")) > 0)),
    CONSTRAINT "notification_campaigns_title_not_empty" CHECK (("length"(TRIM(BOTH FROM "title")) > 0))
);


ALTER TABLE "app"."notification_campaigns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."notification_deliveries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "notification_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "channel" "app"."notification_channel" NOT NULL,
    "status" "app"."notification_delivery_status" DEFAULT 'pending'::"app"."notification_delivery_status" NOT NULL,
    "sent_at" timestamp with time zone,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."notification_deliveries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "course_id" "uuid",
    "service_id" "uuid",
    "amount_cents" integer NOT NULL,
    "currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "status" "app"."order_status" DEFAULT 'pending'::"app"."order_status" NOT NULL,
    "stripe_checkout_id" "text",
    "stripe_payment_intent" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "order_type" "app"."order_type" DEFAULT 'one_off'::"app"."order_type" NOT NULL,
    "session_id" "uuid",
    "session_slot_id" "uuid",
    "stripe_subscription_id" "text",
    "connected_account_id" "text",
    "stripe_customer_id" "text"
);


ALTER TABLE "app"."orders" OWNER TO "postgres";


COMMENT ON TABLE "app"."orders" IS 'RLS placeholder: buyers can read their own orders; admins and service providers may need scoped access.';



COMMENT ON COLUMN "app"."orders"."order_type" IS 'Differentiate one-off vs subscription orders.';



COMMENT ON COLUMN "app"."orders"."session_id" IS 'Parent session (teacher program) reference.';



COMMENT ON COLUMN "app"."orders"."session_slot_id" IS 'Specific slot booking reference.';



COMMENT ON COLUMN "app"."orders"."stripe_subscription_id" IS 'Stripe subscription ID for billing.';



COMMENT ON COLUMN "app"."orders"."connected_account_id" IS 'Stripe Connect destination account.';



COMMENT ON COLUMN "app"."orders"."stripe_customer_id" IS 'Stripe Customer associated with the buyer.';



CREATE TABLE IF NOT EXISTS "app"."payment_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "processed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "app"."payment_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "provider_reference" "text",
    "status" "app"."payment_status" DEFAULT 'pending'::"app"."payment_status" NOT NULL,
    "amount_cents" integer NOT NULL,
    "currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "raw_payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."payments" OWNER TO "postgres";


COMMENT ON TABLE "app"."payments" IS 'RLS placeholder: restrict payment records to order owners and finance/admin roles.';



CREATE TABLE IF NOT EXISTS "app"."posts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "author_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "media_paths" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."posts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."profiles" (
    "user_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "display_name" "text",
    "role" "app"."profile_role" DEFAULT 'student'::"app"."profile_role" NOT NULL,
    "role_v2" "app"."user_role" DEFAULT 'user'::"app"."user_role" NOT NULL,
    "bio" "text",
    "photo_url" "text",
    "is_admin" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "avatar_media_id" "uuid",
    "stripe_customer_id" "text",
    "provider_name" "text",
    "provider_user_id" "text",
    "provider_email_verified" boolean,
    "provider_avatar_url" "text",
    "last_login_provider" "text",
    "last_login_at" timestamp with time zone
);


ALTER TABLE "app"."profiles" OWNER TO "postgres";


COMMENT ON TABLE "app"."profiles" IS 'RLS placeholder: allow owners + admins to read/write their profile rows when Supabase is enabled.';



CREATE TABLE IF NOT EXISTS "app"."purchases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "order_id" "uuid",
    "stripe_payment_intent" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."purchases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."quiz_questions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid",
    "quiz_id" "uuid",
    "position" integer DEFAULT 0 NOT NULL,
    "kind" "text" DEFAULT 'single'::"text" NOT NULL,
    "prompt" "text" NOT NULL,
    "options" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "correct" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."quiz_questions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."referral_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "free_days" integer,
    "free_months" integer,
    "active" boolean DEFAULT true,
    "redeemed_by_user_id" "uuid",
    "redeemed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "app"."referral_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."refresh_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "jti" "uuid" NOT NULL,
    "token_hash" "text" NOT NULL,
    "issued_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "rotated_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "last_used_at" timestamp with time zone
);


ALTER TABLE "app"."refresh_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid",
    "service_id" "uuid",
    "order_id" "uuid",
    "reviewer_id" "uuid" NOT NULL,
    "rating" integer NOT NULL,
    "comment" "text",
    "visibility" "app"."review_visibility" DEFAULT 'public'::"app"."review_visibility" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "reviews_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "app"."reviews" OWNER TO "postgres";


COMMENT ON TABLE "app"."reviews" IS 'RLS placeholder: reviewers can manage their reviews; admins may moderate.';



CREATE TABLE IF NOT EXISTS "app"."runtime_media" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reference_type" "text" NOT NULL,
    "auth_scope" "text" NOT NULL,
    "fallback_policy" "text" NOT NULL,
    "lesson_media_id" "uuid",
    "home_player_upload_id" "uuid",
    "teacher_id" "uuid",
    "course_id" "uuid",
    "lesson_id" "uuid",
    "media_asset_id" "uuid",
    "media_object_id" "uuid",
    "legacy_storage_bucket" "text",
    "legacy_storage_path" "text",
    "kind" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "runtime_media_auth_scope_check" CHECK (("auth_scope" = ANY (ARRAY['lesson_course'::"text", 'home_teacher_library'::"text"]))),
    CONSTRAINT "runtime_media_auth_shape" CHECK (((("auth_scope" = 'lesson_course'::"text") AND ("lesson_media_id" IS NOT NULL) AND ("course_id" IS NOT NULL) AND ("lesson_id" IS NOT NULL)) OR (("auth_scope" = 'home_teacher_library'::"text") AND ("home_player_upload_id" IS NOT NULL)))),
    CONSTRAINT "runtime_media_fallback_policy_check" CHECK (("fallback_policy" = ANY (ARRAY['never'::"text", 'if_no_ready_asset'::"text", 'legacy_only'::"text"]))),
    CONSTRAINT "runtime_media_kind_check" CHECK (("kind" = ANY (ARRAY['audio'::"text", 'video'::"text", 'image'::"text", 'document'::"text", 'other'::"text"]))),
    CONSTRAINT "runtime_media_legacy_storage_pair" CHECK ((("legacy_storage_path" IS NULL) OR ("legacy_storage_bucket" IS NOT NULL))),
    CONSTRAINT "runtime_media_one_origin" CHECK ((((("lesson_media_id" IS NOT NULL))::integer + (("home_player_upload_id" IS NOT NULL))::integer) = 1)),
    CONSTRAINT "runtime_media_reference_type_check" CHECK (("reference_type" = ANY (ARRAY['lesson_media'::"text", 'home_player_upload'::"text"])))
);


ALTER TABLE "app"."runtime_media" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."seminar_recordings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "seminar_id" "uuid" NOT NULL,
    "session_id" "uuid",
    "asset_url" "text",
    "status" "text" DEFAULT 'processing'::"text" NOT NULL,
    "duration_seconds" integer,
    "byte_size" bigint,
    "published" boolean DEFAULT false NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."seminar_recordings" OWNER TO "postgres";


COMMENT ON TABLE "app"."seminar_recordings" IS 'Stored outputs from webinar/SFU sessions.';



CREATE TABLE IF NOT EXISTS "app"."seminar_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "seminar_id" "uuid" NOT NULL,
    "status" "app"."seminar_session_status" DEFAULT 'scheduled'::"app"."seminar_session_status" NOT NULL,
    "scheduled_at" timestamp with time zone,
    "started_at" timestamp with time zone,
    "ended_at" timestamp with time zone,
    "livekit_room" "text",
    "livekit_sid" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."seminar_sessions" OWNER TO "postgres";


COMMENT ON TABLE "app"."seminar_sessions" IS 'Individual LiveKit sessions spawned for seminars.';



CREATE TABLE IF NOT EXISTS "app"."services" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "provider_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "status" "app"."service_status" DEFAULT 'draft'::"app"."service_status" NOT NULL,
    "price_cents" integer DEFAULT 0 NOT NULL,
    "currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "duration_min" integer,
    "requires_certification" boolean DEFAULT false NOT NULL,
    "certified_area" "text",
    "thumbnail_url" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."services" OWNER TO "postgres";


COMMENT ON TABLE "app"."services" IS 'RLS placeholder: providers manage their own services; public read for active services; admins override.';



CREATE OR REPLACE VIEW "app"."service_orders" AS
 SELECT "o"."id",
    "o"."user_id",
    "buyer"."display_name" AS "buyer_display_name",
    "buyer"."email" AS "buyer_email",
    "o"."service_id",
    "s"."title" AS "service_title",
    "s"."description" AS "service_description",
    "s"."duration_min" AS "service_duration_min",
    "s"."requires_certification" AS "service_requires_certification",
    "s"."certified_area" AS "service_certified_area",
    "s"."provider_id",
    "provider"."display_name" AS "provider_display_name",
    "provider"."email" AS "provider_email",
    "o"."amount_cents",
    "o"."currency",
    "o"."status",
    "o"."stripe_checkout_id",
    "o"."stripe_payment_intent",
    "o"."metadata",
    "o"."created_at",
    "o"."updated_at"
   FROM ((("app"."orders" "o"
     JOIN "app"."services" "s" ON (("s"."id" = "o"."service_id")))
     LEFT JOIN "app"."profiles" "buyer" ON (("buyer"."user_id" = "o"."user_id")))
     LEFT JOIN "app"."profiles" "provider" ON (("provider"."user_id" = "s"."provider_id")))
  WHERE ("o"."service_id" IS NOT NULL);


ALTER VIEW "app"."service_orders" OWNER TO "postgres";


COMMENT ON VIEW "app"."service_orders" IS 'Convenience view joining service orders with buyer/provider details. RLS placeholder: restrict by buyer/provider/admin roles.';



CREATE OR REPLACE VIEW "app"."service_reviews" AS
 SELECT "id",
    "service_id",
    "order_id",
    "reviewer_id",
    "rating",
    "comment",
    "visibility",
    "created_at"
   FROM "app"."reviews" "r"
  WHERE ("service_id" IS NOT NULL);


ALTER VIEW "app"."service_reviews" OWNER TO "postgres";


COMMENT ON VIEW "app"."service_reviews" IS 'RLS placeholder: expose service-specific reviews; lock down via RLS once migrated to Supabase.';



CREATE TABLE IF NOT EXISTS "app"."session_slots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "uuid" NOT NULL,
    "start_at" timestamp with time zone NOT NULL,
    "end_at" timestamp with time zone NOT NULL,
    "seats_total" integer DEFAULT 1 NOT NULL,
    "seats_taken" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "session_slots_seats_taken_check" CHECK (("seats_taken" >= 0)),
    CONSTRAINT "session_slots_seats_total_check" CHECK (("seats_total" >= 0))
);


ALTER TABLE "app"."session_slots" OWNER TO "postgres";


COMMENT ON TABLE "app"."session_slots" IS 'Individual slots for teacher sessions with capacity tracking.';



CREATE TABLE IF NOT EXISTS "app"."sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "start_at" timestamp with time zone,
    "end_at" timestamp with time zone,
    "capacity" integer,
    "price_cents" integer DEFAULT 0 NOT NULL,
    "currency" "text" DEFAULT 'sek'::"text" NOT NULL,
    "visibility" "app"."session_visibility" DEFAULT 'draft'::"app"."session_visibility" NOT NULL,
    "recording_url" "text",
    "stripe_price_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sessions_capacity_check" CHECK ((("capacity" IS NULL) OR ("capacity" >= 0)))
);


ALTER TABLE "app"."sessions" OWNER TO "postgres";


COMMENT ON TABLE "app"."sessions" IS 'Published sessions created by teachers, surfaced in booking flows.';



CREATE TABLE IF NOT EXISTS "app"."stripe_customers" (
    "user_id" "uuid" NOT NULL,
    "customer_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."stripe_customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "subscription_id" "text" NOT NULL,
    "customer_id" "text",
    "price_id" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."tarot_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "requester_id" "uuid" NOT NULL,
    "question" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."tarot_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."teacher_accounts" (
    "user_id" "uuid" NOT NULL,
    "stripe_account_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."teacher_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."teacher_approvals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "reviewer_id" "uuid",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "notes" "text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."teacher_approvals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."teacher_directory" (
    "user_id" "uuid" NOT NULL,
    "headline" "text",
    "specialties" "text"[],
    "rating" numeric(3,2),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."teacher_directory" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."teacher_payout_methods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "reference" "text" NOT NULL,
    "details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."teacher_payout_methods" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."teacher_permissions" (
    "profile_id" "uuid" NOT NULL,
    "can_edit_courses" boolean DEFAULT false NOT NULL,
    "can_publish" boolean DEFAULT false NOT NULL,
    "granted_by" "uuid",
    "granted_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "app"."teacher_permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."teacher_profile_media" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "teacher_id" "uuid" NOT NULL,
    "media_kind" "text" NOT NULL,
    "media_id" "uuid",
    "external_url" "text",
    "title" "text",
    "description" "text",
    "cover_media_id" "uuid",
    "cover_image_url" "text",
    "position" integer DEFAULT 0 NOT NULL,
    "is_published" boolean DEFAULT true NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "enabled_for_home_player" boolean DEFAULT false NOT NULL,
    "visibility_intro_material" boolean DEFAULT false NOT NULL,
    "visibility_course_member" boolean DEFAULT false NOT NULL,
    "home_visibility_intro_material" boolean DEFAULT false NOT NULL,
    "home_visibility_course_member" boolean DEFAULT false NOT NULL,
    CONSTRAINT "teacher_profile_media_media_kind_check" CHECK (("media_kind" = ANY (ARRAY['lesson_media'::"text", 'seminar_recording'::"text", 'external'::"text"])))
);


ALTER TABLE "app"."teacher_profile_media" OWNER TO "postgres";


COMMENT ON TABLE "app"."teacher_profile_media" IS 'Curated media rows surfaced on teacher profile pages (lesson clips, seminar recordings, external links).';



COMMENT ON COLUMN "app"."teacher_profile_media"."enabled_for_home_player" IS 'Explicit teacher opt-in gate for Home player inclusion.';



COMMENT ON COLUMN "app"."teacher_profile_media"."visibility_intro_material" IS 'When enabled_for_home_player is true: visible to active Aveli members (intro material).';



COMMENT ON COLUMN "app"."teacher_profile_media"."visibility_course_member" IS 'When enabled_for_home_player is true: visible to enrolled course members (paid content).';



CREATE TABLE IF NOT EXISTS "app"."teachers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "stripe_connect_account_id" "text",
    "payout_split_pct" integer DEFAULT 100 NOT NULL,
    "onboarded_at" timestamp with time zone,
    "charges_enabled" boolean DEFAULT false NOT NULL,
    "payouts_enabled" boolean DEFAULT false NOT NULL,
    "requirements_due" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "teachers_payout_split_pct_check" CHECK ((("payout_split_pct" >= 0) AND ("payout_split_pct" <= 100)))
);


ALTER TABLE "app"."teachers" OWNER TO "postgres";


COMMENT ON TABLE "app"."teachers" IS 'Stripe Connect metadata per teacher profile.';



CREATE OR REPLACE VIEW "app"."v_meditation_audio_library" AS
 SELECT "lm"."id" AS "media_id",
    "l"."course_id",
    "l"."id" AS "lesson_id",
    "l"."title",
    NULL::"text" AS "description",
    COALESCE("mo"."storage_path", "lm"."storage_path") AS "storage_path",
    COALESCE("mo"."storage_bucket", "lm"."storage_bucket", 'lesson-media'::"text") AS "storage_bucket",
    "lm"."duration_seconds",
    "lm"."created_at"
   FROM (("app"."lesson_media" "lm"
     JOIN "app"."lessons" "l" ON (("l"."id" = "lm"."lesson_id")))
     LEFT JOIN "app"."media_objects" "mo" ON (("mo"."id" = "lm"."media_id")))
  WHERE ("lower"("lm"."kind") = 'audio'::"text");


ALTER VIEW "app"."v_meditation_audio_library" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "app"."welcome_cards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text",
    "body" "text",
    "image_path" "text" NOT NULL,
    "day" integer,
    "month" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "welcome_cards_day_check" CHECK ((("day" >= 1) AND ("day" <= 31))),
    CONSTRAINT "welcome_cards_day_month_pair" CHECK (((("day" IS NULL) AND ("month" IS NULL)) OR (("day" IS NOT NULL) AND ("month" IS NOT NULL)))),
    CONSTRAINT "welcome_cards_month_check" CHECK ((("month" >= 1) AND ("month" <= 12)))
);


ALTER TABLE "app"."welcome_cards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."coupons" (
    "code" "text" NOT NULL,
    "plan_id" "uuid",
    "grants" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "max_redemptions" integer,
    "redeemed_count" integer DEFAULT 0 NOT NULL,
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."coupons" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscription_plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "price_cents" integer NOT NULL,
    "interval" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "stripe_product_id" "text",
    "stripe_price_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "subscription_plans_interval_check" CHECK (("interval" = ANY (ARRAY['month'::"text", 'year'::"text"])))
);


ALTER TABLE "public"."subscription_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "plan_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "current_period_end" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_certifications" (
    "user_id" "uuid" NOT NULL,
    "area" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_certifications" OWNER TO "postgres";


ALTER TABLE ONLY "app"."activities"
    ADD CONSTRAINT "activities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."app_config"
    ADD CONSTRAINT "app_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."auth_events"
    ADD CONSTRAINT "auth_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."billing_logs"
    ADD CONSTRAINT "billing_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."certificates"
    ADD CONSTRAINT "certificates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."classroom_messages"
    ADD CONSTRAINT "classroom_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."classroom_presence"
    ADD CONSTRAINT "classroom_presence_course_id_user_id_key" UNIQUE ("course_id", "user_id");



ALTER TABLE ONLY "app"."classroom_presence"
    ADD CONSTRAINT "classroom_presence_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."course_bundle_courses"
    ADD CONSTRAINT "course_bundle_courses_pkey" PRIMARY KEY ("bundle_id", "course_id");



ALTER TABLE ONLY "app"."course_bundles"
    ADD CONSTRAINT "course_bundles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."course_display_priorities"
    ADD CONSTRAINT "course_display_priorities_pkey" PRIMARY KEY ("teacher_id");



ALTER TABLE ONLY "app"."course_entitlements"
    ADD CONSTRAINT "course_entitlements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."course_entitlements"
    ADD CONSTRAINT "course_entitlements_user_course_key" UNIQUE ("user_id", "course_slug");



ALTER TABLE ONLY "app"."course_products"
    ADD CONSTRAINT "course_products_course_id_key" UNIQUE ("course_id");



ALTER TABLE ONLY "app"."course_products"
    ADD CONSTRAINT "course_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."course_quizzes"
    ADD CONSTRAINT "course_quizzes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."courses"
    ADD CONSTRAINT "courses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."courses"
    ADD CONSTRAINT "courses_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "app"."enrollments"
    ADD CONSTRAINT "enrollments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."enrollments"
    ADD CONSTRAINT "enrollments_user_id_course_id_key" UNIQUE ("user_id", "course_id");



ALTER TABLE ONLY "app"."entitlements"
    ADD CONSTRAINT "entitlements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."event_participants"
    ADD CONSTRAINT "event_participants_event_id_user_id_key" UNIQUE ("event_id", "user_id");



ALTER TABLE ONLY "app"."event_participants"
    ADD CONSTRAINT "event_participants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."events"
    ADD CONSTRAINT "events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."follows"
    ADD CONSTRAINT "follows_pkey" PRIMARY KEY ("follower_id", "followee_id");



ALTER TABLE ONLY "app"."guest_claim_tokens"
    ADD CONSTRAINT "guest_claim_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."guest_claim_tokens"
    ADD CONSTRAINT "guest_claim_tokens_token_key" UNIQUE ("token");



ALTER TABLE ONLY "app"."home_player_course_links"
    ADD CONSTRAINT "home_player_course_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."home_player_course_links"
    ADD CONSTRAINT "home_player_course_links_teacher_id_lesson_media_id_key" UNIQUE ("teacher_id", "lesson_media_id");



ALTER TABLE ONLY "app"."home_player_uploads"
    ADD CONSTRAINT "home_player_uploads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."intro_usage"
    ADD CONSTRAINT "intro_usage_pkey" PRIMARY KEY ("user_id", "year", "month");



ALTER TABLE ONLY "app"."lesson_media_issues"
    ADD CONSTRAINT "lesson_media_issues_pkey" PRIMARY KEY ("lesson_media_id");



ALTER TABLE ONLY "app"."lesson_media"
    ADD CONSTRAINT "lesson_media_lesson_id_position_key" UNIQUE ("lesson_id", "position");



ALTER TABLE ONLY "app"."lesson_media"
    ADD CONSTRAINT "lesson_media_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."lesson_packages"
    ADD CONSTRAINT "lesson_packages_lesson_id_key" UNIQUE ("lesson_id");



ALTER TABLE ONLY "app"."lesson_packages"
    ADD CONSTRAINT "lesson_packages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."lessons"
    ADD CONSTRAINT "lessons_course_id_position_key" UNIQUE ("course_id", "position");



ALTER TABLE ONLY "app"."lessons"
    ADD CONSTRAINT "lessons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."live_event_registrations"
    ADD CONSTRAINT "live_event_registrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."live_events"
    ADD CONSTRAINT "live_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."livekit_webhook_jobs"
    ADD CONSTRAINT "livekit_webhook_jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."media_assets"
    ADD CONSTRAINT "media_assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."media_objects"
    ADD CONSTRAINT "media_objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."media_objects"
    ADD CONSTRAINT "media_objects_storage_path_storage_bucket_key" UNIQUE ("storage_path", "storage_bucket");



ALTER TABLE ONLY "app"."media_resolution_failures"
    ADD CONSTRAINT "media_resolution_failures_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."meditations"
    ADD CONSTRAINT "meditations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."memberships"
    ADD CONSTRAINT "memberships_pkey" PRIMARY KEY ("membership_id");



ALTER TABLE ONLY "app"."memberships"
    ADD CONSTRAINT "memberships_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "app"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."music_tracks"
    ADD CONSTRAINT "music_tracks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."notification_audiences"
    ADD CONSTRAINT "notification_audiences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."notification_campaigns"
    ADD CONSTRAINT "notification_campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."notification_deliveries"
    ADD CONSTRAINT "notification_deliveries_notification_id_user_id_channel_key" UNIQUE ("notification_id", "user_id", "channel");



ALTER TABLE ONLY "app"."notification_deliveries"
    ADD CONSTRAINT "notification_deliveries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."payment_events"
    ADD CONSTRAINT "payment_events_event_id_key" UNIQUE ("event_id");



ALTER TABLE ONLY "app"."payment_events"
    ADD CONSTRAINT "payment_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."posts"
    ADD CONSTRAINT "posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."profiles"
    ADD CONSTRAINT "profiles_email_key" UNIQUE ("email");



ALTER TABLE ONLY "app"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "app"."purchases"
    ADD CONSTRAINT "purchases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."quiz_questions"
    ADD CONSTRAINT "quiz_questions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."referral_codes"
    ADD CONSTRAINT "referral_codes_code_key" UNIQUE ("code");



ALTER TABLE ONLY "app"."referral_codes"
    ADD CONSTRAINT "referral_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_jti_key" UNIQUE ("jti");



ALTER TABLE ONLY "app"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."reviews"
    ADD CONSTRAINT "reviews_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_home_player_upload_id_key" UNIQUE ("home_player_upload_id");



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_lesson_media_id_key" UNIQUE ("lesson_media_id");



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."seminar_attendees"
    ADD CONSTRAINT "seminar_attendees_pkey" PRIMARY KEY ("seminar_id", "user_id");



ALTER TABLE ONLY "app"."seminar_recordings"
    ADD CONSTRAINT "seminar_recordings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."seminar_sessions"
    ADD CONSTRAINT "seminar_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."seminars"
    ADD CONSTRAINT "seminars_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."services"
    ADD CONSTRAINT "services_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."session_slots"
    ADD CONSTRAINT "session_slots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."session_slots"
    ADD CONSTRAINT "session_slots_session_id_start_at_key" UNIQUE ("session_id", "start_at");



ALTER TABLE ONLY "app"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."stripe_customers"
    ADD CONSTRAINT "stripe_customers_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "app"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."subscriptions"
    ADD CONSTRAINT "subscriptions_subscription_id_key" UNIQUE ("subscription_id");



ALTER TABLE ONLY "app"."tarot_requests"
    ADD CONSTRAINT "tarot_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."teacher_accounts"
    ADD CONSTRAINT "teacher_accounts_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "app"."teacher_approvals"
    ADD CONSTRAINT "teacher_approvals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."teacher_approvals"
    ADD CONSTRAINT "teacher_approvals_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "app"."teacher_directory"
    ADD CONSTRAINT "teacher_directory_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "app"."teacher_payout_methods"
    ADD CONSTRAINT "teacher_payout_methods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."teacher_payout_methods"
    ADD CONSTRAINT "teacher_payout_methods_teacher_id_provider_reference_key" UNIQUE ("teacher_id", "provider", "reference");



ALTER TABLE ONLY "app"."teacher_permissions"
    ADD CONSTRAINT "teacher_permissions_pkey" PRIMARY KEY ("profile_id");



ALTER TABLE ONLY "app"."teacher_profile_media"
    ADD CONSTRAINT "teacher_profile_media_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."teacher_profile_media"
    ADD CONSTRAINT "teacher_profile_media_teacher_id_media_kind_media_id_key" UNIQUE ("teacher_id", "media_kind", "media_id");



ALTER TABLE ONLY "app"."teachers"
    ADD CONSTRAINT "teachers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "app"."teachers"
    ADD CONSTRAINT "teachers_profile_id_key" UNIQUE ("profile_id");



ALTER TABLE ONLY "app"."teachers"
    ADD CONSTRAINT "teachers_stripe_connect_account_id_key" UNIQUE ("stripe_connect_account_id");



ALTER TABLE ONLY "app"."welcome_cards"
    ADD CONSTRAINT "welcome_cards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."coupons"
    ADD CONSTRAINT "coupons_pkey" PRIMARY KEY ("code");



ALTER TABLE ONLY "public"."subscription_plans"
    ADD CONSTRAINT "subscription_plans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_certifications"
    ADD CONSTRAINT "user_certifications_pkey" PRIMARY KEY ("user_id", "area");



CREATE INDEX "courses_slug_idx" ON "app"."courses" USING "btree" ("slug");



CREATE INDEX "idx_activities_occurred" ON "app"."activities" USING "btree" ("occurred_at" DESC);



CREATE INDEX "idx_activities_subject" ON "app"."activities" USING "btree" ("subject_table", "subject_id");



CREATE INDEX "idx_activities_type" ON "app"."activities" USING "btree" ("activity_type");



CREATE INDEX "idx_auth_events_created_at" ON "app"."auth_events" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_auth_events_user" ON "app"."auth_events" USING "btree" ("user_id");



CREATE INDEX "idx_certificates_user" ON "app"."certificates" USING "btree" ("user_id");



CREATE INDEX "idx_classroom_messages_course" ON "app"."classroom_messages" USING "btree" ("course_id");



CREATE INDEX "idx_classroom_messages_created" ON "app"."classroom_messages" USING "btree" ("created_at");



CREATE INDEX "idx_classroom_presence_course" ON "app"."classroom_presence" USING "btree" ("course_id");



CREATE INDEX "idx_classroom_presence_last_seen" ON "app"."classroom_presence" USING "btree" ("last_seen");



CREATE INDEX "idx_course_bundle_courses_bundle" ON "app"."course_bundle_courses" USING "btree" ("bundle_id");



CREATE INDEX "idx_course_bundles_active" ON "app"."course_bundles" USING "btree" ("is_active");



CREATE INDEX "idx_course_bundles_teacher" ON "app"."course_bundles" USING "btree" ("teacher_id");



CREATE INDEX "idx_course_display_priorities_priority" ON "app"."course_display_priorities" USING "btree" ("priority");



CREATE INDEX "idx_course_entitlements_user_course" ON "app"."course_entitlements" USING "btree" ("user_id", "course_slug");



CREATE INDEX "idx_course_products_course" ON "app"."course_products" USING "btree" ("course_id");



CREATE INDEX "idx_courses_cover_media" ON "app"."courses" USING "btree" ("cover_media_id");



CREATE INDEX "idx_courses_created_by" ON "app"."courses" USING "btree" ("created_by");



CREATE INDEX "idx_enrollments_course" ON "app"."enrollments" USING "btree" ("course_id");



CREATE INDEX "idx_enrollments_user" ON "app"."enrollments" USING "btree" ("user_id");



CREATE INDEX "idx_entitlements_course" ON "app"."entitlements" USING "btree" ("course_id");



CREATE INDEX "idx_entitlements_user" ON "app"."entitlements" USING "btree" ("user_id");



CREATE INDEX "idx_entitlements_user_course" ON "app"."entitlements" USING "btree" ("user_id", "course_id");



CREATE INDEX "idx_event_participants_event" ON "app"."event_participants" USING "btree" ("event_id");



CREATE INDEX "idx_event_participants_user" ON "app"."event_participants" USING "btree" ("user_id");



CREATE INDEX "idx_events_created_by" ON "app"."events" USING "btree" ("created_by");



CREATE INDEX "idx_events_start_at" ON "app"."events" USING "btree" ("start_at");



CREATE INDEX "idx_events_status" ON "app"."events" USING "btree" ("status");



CREATE INDEX "idx_events_visibility" ON "app"."events" USING "btree" ("visibility");



CREATE INDEX "idx_guest_claim_tokens_expires" ON "app"."guest_claim_tokens" USING "btree" ("expires_at");



CREATE INDEX "idx_guest_claim_tokens_used" ON "app"."guest_claim_tokens" USING "btree" ("used");



CREATE INDEX "idx_home_player_course_links_teacher_created" ON "app"."home_player_course_links" USING "btree" ("teacher_id", "created_at" DESC);



CREATE INDEX "idx_home_player_uploads_media" ON "app"."home_player_uploads" USING "btree" ("media_id");



CREATE INDEX "idx_home_player_uploads_media_asset" ON "app"."home_player_uploads" USING "btree" ("media_asset_id");



CREATE INDEX "idx_home_player_uploads_teacher_created" ON "app"."home_player_uploads" USING "btree" ("teacher_id", "created_at" DESC);



CREATE INDEX "idx_intro_usage_user_month" ON "app"."intro_usage" USING "btree" ("user_id", "year" DESC, "month" DESC);



CREATE INDEX "idx_lesson_media_asset" ON "app"."lesson_media" USING "btree" ("media_asset_id");



CREATE INDEX "idx_lesson_media_issues_issue" ON "app"."lesson_media_issues" USING "btree" ("issue");



CREATE INDEX "idx_lesson_media_lesson" ON "app"."lesson_media" USING "btree" ("lesson_id");



CREATE INDEX "idx_lesson_media_media" ON "app"."lesson_media" USING "btree" ("media_id");



CREATE INDEX "idx_lesson_packages_lesson" ON "app"."lesson_packages" USING "btree" ("lesson_id");



CREATE INDEX "idx_lessons_course" ON "app"."lessons" USING "btree" ("course_id");



CREATE INDEX "idx_live_event_registrations_event" ON "app"."live_event_registrations" USING "btree" ("event_id");



CREATE UNIQUE INDEX "idx_live_event_registrations_unique" ON "app"."live_event_registrations" USING "btree" ("event_id", "user_id");



CREATE INDEX "idx_live_event_registrations_user" ON "app"."live_event_registrations" USING "btree" ("user_id");



CREATE INDEX "idx_live_events_access_type" ON "app"."live_events" USING "btree" ("access_type");



CREATE INDEX "idx_live_events_course" ON "app"."live_events" USING "btree" ("course_id");



CREATE INDEX "idx_live_events_scheduled_at" ON "app"."live_events" USING "btree" ("scheduled_at");



CREATE INDEX "idx_live_events_starts_at" ON "app"."live_events" USING "btree" ("starts_at");



CREATE INDEX "idx_live_events_teacher" ON "app"."live_events" USING "btree" ("teacher_id");



CREATE INDEX "idx_livekit_webhook_jobs_status" ON "app"."livekit_webhook_jobs" USING "btree" ("status", "scheduled_at");



CREATE INDEX "idx_media_assets_course" ON "app"."media_assets" USING "btree" ("course_id");



CREATE INDEX "idx_media_assets_course_cover" ON "app"."media_assets" USING "btree" ("course_id") WHERE ("purpose" = 'course_cover'::"text");



CREATE INDEX "idx_media_assets_lesson" ON "app"."media_assets" USING "btree" ("lesson_id");



CREATE INDEX "idx_media_assets_next_retry" ON "app"."media_assets" USING "btree" ("next_retry_at");



CREATE INDEX "idx_media_assets_purpose" ON "app"."media_assets" USING "btree" ("purpose");



CREATE INDEX "idx_media_assets_state" ON "app"."media_assets" USING "btree" ("state");



CREATE INDEX "idx_media_owner" ON "app"."media_objects" USING "btree" ("owner_id");



CREATE INDEX "idx_media_resolution_failures_created_at" ON "app"."media_resolution_failures" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_media_resolution_failures_lesson_media" ON "app"."media_resolution_failures" USING "btree" ("lesson_media_id");



CREATE INDEX "idx_media_resolution_failures_reason" ON "app"."media_resolution_failures" USING "btree" ("reason");



CREATE INDEX "idx_messages_channel" ON "app"."messages" USING "btree" ("channel");



CREATE INDEX "idx_messages_recipient" ON "app"."messages" USING "btree" ("recipient_id");



CREATE INDEX "idx_music_tracks_course" ON "app"."music_tracks" USING "btree" ("course_id");



CREATE INDEX "idx_music_tracks_created" ON "app"."music_tracks" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_music_tracks_teacher" ON "app"."music_tracks" USING "btree" ("teacher_id");



CREATE INDEX "idx_notification_audiences_course" ON "app"."notification_audiences" USING "btree" ("course_id");



CREATE INDEX "idx_notification_audiences_event" ON "app"."notification_audiences" USING "btree" ("event_id");



CREATE INDEX "idx_notification_audiences_notification_id" ON "app"."notification_audiences" USING "btree" ("notification_id");



CREATE INDEX "idx_notification_campaigns_created_by" ON "app"."notification_campaigns" USING "btree" ("created_by");



CREATE INDEX "idx_notification_campaigns_send_at" ON "app"."notification_campaigns" USING "btree" ("send_at");



CREATE INDEX "idx_notification_campaigns_status" ON "app"."notification_campaigns" USING "btree" ("status");



CREATE INDEX "idx_notification_deliveries_notification_id" ON "app"."notification_deliveries" USING "btree" ("notification_id");



CREATE INDEX "idx_notification_deliveries_status" ON "app"."notification_deliveries" USING "btree" ("status");



CREATE INDEX "idx_notification_deliveries_user" ON "app"."notification_deliveries" USING "btree" ("user_id");



CREATE INDEX "idx_notifications_read" ON "app"."notifications" USING "btree" ("user_id", "read_at");



CREATE INDEX "idx_notifications_user" ON "app"."notifications" USING "btree" ("user_id");



CREATE INDEX "idx_orders_connected_account" ON "app"."orders" USING "btree" ("connected_account_id");



CREATE INDEX "idx_orders_course" ON "app"."orders" USING "btree" ("course_id");



CREATE INDEX "idx_orders_service" ON "app"."orders" USING "btree" ("service_id");



CREATE INDEX "idx_orders_session" ON "app"."orders" USING "btree" ("session_id");



CREATE INDEX "idx_orders_session_slot" ON "app"."orders" USING "btree" ("session_slot_id");



CREATE INDEX "idx_orders_status" ON "app"."orders" USING "btree" ("status");



CREATE INDEX "idx_orders_user" ON "app"."orders" USING "btree" ("user_id");



CREATE INDEX "idx_payments_order" ON "app"."payments" USING "btree" ("order_id");



CREATE INDEX "idx_payments_status" ON "app"."payments" USING "btree" ("status");



CREATE INDEX "idx_payout_methods_teacher" ON "app"."teacher_payout_methods" USING "btree" ("teacher_id");



CREATE INDEX "idx_posts_author" ON "app"."posts" USING "btree" ("author_id");



CREATE INDEX "idx_purchases_order" ON "app"."purchases" USING "btree" ("order_id");



CREATE INDEX "idx_purchases_user" ON "app"."purchases" USING "btree" ("user_id");



CREATE INDEX "idx_quiz_questions_course" ON "app"."quiz_questions" USING "btree" ("course_id");



CREATE INDEX "idx_quiz_questions_quiz" ON "app"."quiz_questions" USING "btree" ("quiz_id");



CREATE INDEX "idx_refresh_tokens_user" ON "app"."refresh_tokens" USING "btree" ("user_id");



CREATE INDEX "idx_reviews_course" ON "app"."reviews" USING "btree" ("course_id");



CREATE INDEX "idx_reviews_order" ON "app"."reviews" USING "btree" ("order_id");



CREATE INDEX "idx_reviews_reviewer" ON "app"."reviews" USING "btree" ("reviewer_id");



CREATE INDEX "idx_reviews_service" ON "app"."reviews" USING "btree" ("service_id");



CREATE INDEX "idx_runtime_media_asset" ON "app"."runtime_media" USING "btree" ("media_asset_id");



CREATE INDEX "idx_runtime_media_course" ON "app"."runtime_media" USING "btree" ("course_id");



CREATE INDEX "idx_runtime_media_lesson" ON "app"."runtime_media" USING "btree" ("lesson_id");



CREATE INDEX "idx_runtime_media_object" ON "app"."runtime_media" USING "btree" ("media_object_id");



CREATE INDEX "idx_runtime_media_teacher_active" ON "app"."runtime_media" USING "btree" ("teacher_id", "active");



CREATE INDEX "idx_seminar_recordings_seminar" ON "app"."seminar_recordings" USING "btree" ("seminar_id");



CREATE INDEX "idx_seminar_sessions_seminar" ON "app"."seminar_sessions" USING "btree" ("seminar_id");



CREATE INDEX "idx_seminars_host" ON "app"."seminars" USING "btree" ("host_id");



CREATE INDEX "idx_seminars_scheduled_at" ON "app"."seminars" USING "btree" ("scheduled_at");



CREATE INDEX "idx_seminars_status" ON "app"."seminars" USING "btree" ("status");



CREATE INDEX "idx_services_provider" ON "app"."services" USING "btree" ("provider_id");



CREATE INDEX "idx_services_status" ON "app"."services" USING "btree" ("status");



CREATE INDEX "idx_session_slots_session" ON "app"."session_slots" USING "btree" ("session_id");



CREATE INDEX "idx_session_slots_time" ON "app"."session_slots" USING "btree" ("start_at", "end_at");



CREATE INDEX "idx_sessions_start_at" ON "app"."sessions" USING "btree" ("start_at");



CREATE INDEX "idx_sessions_teacher" ON "app"."sessions" USING "btree" ("teacher_id");



CREATE INDEX "idx_sessions_visibility" ON "app"."sessions" USING "btree" ("visibility");



CREATE INDEX "idx_subscriptions_user" ON "app"."subscriptions" USING "btree" ("user_id");



CREATE INDEX "idx_teacher_approvals_user" ON "app"."teacher_approvals" USING "btree" ("user_id");



CREATE INDEX "idx_teacher_profile_media_teacher" ON "app"."teacher_profile_media" USING "btree" ("teacher_id", "position");



CREATE INDEX "idx_teachers_connect_account" ON "app"."teachers" USING "btree" ("stripe_connect_account_id");



CREATE INDEX "idx_welcome_cards_active" ON "app"."welcome_cards" USING "btree" ("is_active");



CREATE INDEX "idx_welcome_cards_date" ON "app"."welcome_cards" USING "btree" ("month", "day");



CREATE INDEX "profiles_stripe_customer_idx" ON "app"."profiles" USING "btree" ("lower"("stripe_customer_id"));



CREATE INDEX "idx_coupons_expires" ON "public"."coupons" USING "btree" ("expires_at");



CREATE INDEX "idx_coupons_plan" ON "public"."coupons" USING "btree" ("plan_id");



CREATE INDEX "idx_public_subscriptions_plan" ON "public"."subscriptions" USING "btree" ("plan_id");



CREATE INDEX "idx_public_subscriptions_user" ON "public"."subscriptions" USING "btree" ("user_id");



CREATE INDEX "idx_subscription_plans_active" ON "public"."subscription_plans" USING "btree" ("is_active");



CREATE INDEX "idx_user_certifications_area" ON "public"."user_certifications" USING "btree" ("area");



CREATE OR REPLACE TRIGGER "trg_course_display_priorities_touch" BEFORE UPDATE ON "app"."course_display_priorities" FOR EACH ROW EXECUTE FUNCTION "app"."touch_course_display_priorities"();



CREATE OR REPLACE TRIGGER "trg_course_entitlements_touch" BEFORE UPDATE ON "app"."course_entitlements" FOR EACH ROW EXECUTE FUNCTION "app"."touch_course_entitlements"();



CREATE OR REPLACE TRIGGER "trg_course_products_updated" BEFORE UPDATE ON "app"."course_products" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_courses_touch" BEFORE UPDATE ON "app"."courses" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_events_status_progression" BEFORE UPDATE OF "status" ON "app"."events" FOR EACH ROW EXECUTE FUNCTION "app"."enforce_event_status_progression"();



CREATE OR REPLACE TRIGGER "trg_events_touch" BEFORE UPDATE ON "app"."events" FOR EACH ROW EXECUTE FUNCTION "app"."touch_events"();



CREATE OR REPLACE TRIGGER "trg_home_player_course_links_touch" BEFORE UPDATE ON "app"."home_player_course_links" FOR EACH ROW EXECUTE FUNCTION "app"."touch_home_player_course_links"();



CREATE OR REPLACE TRIGGER "trg_home_player_uploads_touch" BEFORE UPDATE ON "app"."home_player_uploads" FOR EACH ROW EXECUTE FUNCTION "app"."touch_home_player_uploads"();



CREATE OR REPLACE TRIGGER "trg_intro_usage_touch" BEFORE UPDATE ON "app"."intro_usage" FOR EACH ROW EXECUTE FUNCTION "app"."touch_intro_usage"();



CREATE OR REPLACE TRIGGER "trg_lesson_packages_updated" BEFORE UPDATE ON "app"."lesson_packages" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_lessons_touch" BEFORE UPDATE ON "app"."lessons" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_live_events_touch" BEFORE UPDATE ON "app"."live_events" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_livekit_webhook_jobs_touch" BEFORE UPDATE ON "app"."livekit_webhook_jobs" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_music_tracks_updated_at" BEFORE UPDATE ON "app"."music_tracks" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_orders_touch" BEFORE UPDATE ON "app"."orders" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_payments_touch" BEFORE UPDATE ON "app"."payments" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_profiles_touch" BEFORE UPDATE ON "app"."profiles" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_runtime_media_sync_course_context" AFTER UPDATE OF "created_by" ON "app"."courses" FOR EACH ROW EXECUTE FUNCTION "app"."sync_runtime_media_course_context_trigger"();



CREATE OR REPLACE TRIGGER "trg_runtime_media_sync_lesson_context" AFTER UPDATE OF "course_id" ON "app"."lessons" FOR EACH ROW EXECUTE FUNCTION "app"."sync_runtime_media_lesson_context_trigger"();



CREATE OR REPLACE TRIGGER "trg_runtime_media_sync_lesson_media" AFTER INSERT OR UPDATE OF "lesson_id", "kind", "media_id", "storage_path", "storage_bucket", "media_asset_id" ON "app"."lesson_media" FOR EACH ROW EXECUTE FUNCTION "app"."sync_runtime_media_lesson_media_trigger"();



CREATE OR REPLACE TRIGGER "trg_runtime_media_touch" BEFORE UPDATE ON "app"."runtime_media" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_seminar_recordings_touch" BEFORE UPDATE ON "app"."seminar_recordings" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_seminar_sessions_touch" BEFORE UPDATE ON "app"."seminar_sessions" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_seminars_touch" BEFORE UPDATE ON "app"."seminars" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_services_touch" BEFORE UPDATE ON "app"."services" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_session_slots_touch" BEFORE UPDATE ON "app"."session_slots" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_sessions_touch" BEFORE UPDATE ON "app"."sessions" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_subscriptions_touch" BEFORE UPDATE ON "app"."subscriptions" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_teacher_accounts_updated" BEFORE UPDATE ON "app"."teacher_accounts" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_teacher_approvals_touch" BEFORE UPDATE ON "app"."teacher_approvals" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_teacher_payout_methods_touch" BEFORE UPDATE ON "app"."teacher_payout_methods" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_teacher_profile_media_touch" BEFORE UPDATE ON "app"."teacher_profile_media" FOR EACH ROW EXECUTE FUNCTION "app"."touch_teacher_profile_media"();



CREATE OR REPLACE TRIGGER "trg_teachers_touch" BEFORE UPDATE ON "app"."teachers" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_welcome_cards_updated_at" BEFORE UPDATE ON "app"."welcome_cards" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_coupons_touch" BEFORE UPDATE ON "public"."coupons" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_public_subscriptions_touch" BEFORE UPDATE ON "public"."subscriptions" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_subscription_plans_touch" BEFORE UPDATE ON "public"."subscription_plans" FOR EACH ROW EXECUTE FUNCTION "app"."set_updated_at"();



ALTER TABLE ONLY "app"."activities"
    ADD CONSTRAINT "activities_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."auth_events"
    ADD CONSTRAINT "auth_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."certificates"
    ADD CONSTRAINT "certificates_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."certificates"
    ADD CONSTRAINT "certificates_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."classroom_messages"
    ADD CONSTRAINT "classroom_messages_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."classroom_messages"
    ADD CONSTRAINT "classroom_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."classroom_presence"
    ADD CONSTRAINT "classroom_presence_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."classroom_presence"
    ADD CONSTRAINT "classroom_presence_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."course_bundle_courses"
    ADD CONSTRAINT "course_bundle_courses_bundle_id_fkey" FOREIGN KEY ("bundle_id") REFERENCES "app"."course_bundles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."course_bundle_courses"
    ADD CONSTRAINT "course_bundle_courses_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."course_bundles"
    ADD CONSTRAINT "course_bundles_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."course_display_priorities"
    ADD CONSTRAINT "course_display_priorities_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."course_display_priorities"
    ADD CONSTRAINT "course_display_priorities_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."course_entitlements"
    ADD CONSTRAINT "course_entitlements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."course_products"
    ADD CONSTRAINT "course_products_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."course_quizzes"
    ADD CONSTRAINT "course_quizzes_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."course_quizzes"
    ADD CONSTRAINT "course_quizzes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."courses"
    ADD CONSTRAINT "courses_cover_media_id_fkey" FOREIGN KEY ("cover_media_id") REFERENCES "app"."media_assets"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."courses"
    ADD CONSTRAINT "courses_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."enrollments"
    ADD CONSTRAINT "enrollments_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."enrollments"
    ADD CONSTRAINT "enrollments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."entitlements"
    ADD CONSTRAINT "entitlements_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."entitlements"
    ADD CONSTRAINT "entitlements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."event_participants"
    ADD CONSTRAINT "event_participants_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "app"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."event_participants"
    ADD CONSTRAINT "event_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."events"
    ADD CONSTRAINT "events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."events"
    ADD CONSTRAINT "events_image_id_fkey" FOREIGN KEY ("image_id") REFERENCES "app"."media_objects"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."follows"
    ADD CONSTRAINT "follows_followee_id_fkey" FOREIGN KEY ("followee_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."follows"
    ADD CONSTRAINT "follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."guest_claim_tokens"
    ADD CONSTRAINT "guest_claim_tokens_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."guest_claim_tokens"
    ADD CONSTRAINT "guest_claim_tokens_purchase_id_fkey" FOREIGN KEY ("purchase_id") REFERENCES "app"."purchases"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."home_player_course_links"
    ADD CONSTRAINT "home_player_course_links_lesson_media_id_fkey" FOREIGN KEY ("lesson_media_id") REFERENCES "app"."lesson_media"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."home_player_course_links"
    ADD CONSTRAINT "home_player_course_links_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."home_player_uploads"
    ADD CONSTRAINT "home_player_uploads_media_asset_id_fkey" FOREIGN KEY ("media_asset_id") REFERENCES "app"."media_assets"("id");



ALTER TABLE ONLY "app"."home_player_uploads"
    ADD CONSTRAINT "home_player_uploads_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "app"."media_objects"("id");



ALTER TABLE ONLY "app"."home_player_uploads"
    ADD CONSTRAINT "home_player_uploads_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."intro_usage"
    ADD CONSTRAINT "intro_usage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."lesson_media_issues"
    ADD CONSTRAINT "lesson_media_issues_lesson_media_id_fkey" FOREIGN KEY ("lesson_media_id") REFERENCES "app"."lesson_media"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."lesson_media"
    ADD CONSTRAINT "lesson_media_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "app"."lessons"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."lesson_media"
    ADD CONSTRAINT "lesson_media_media_asset_id_fkey" FOREIGN KEY ("media_asset_id") REFERENCES "app"."media_assets"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."lesson_media"
    ADD CONSTRAINT "lesson_media_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "app"."media_objects"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."lesson_packages"
    ADD CONSTRAINT "lesson_packages_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "app"."lessons"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."lessons"
    ADD CONSTRAINT "lessons_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."live_event_registrations"
    ADD CONSTRAINT "live_event_registrations_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "app"."live_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."live_event_registrations"
    ADD CONSTRAINT "live_event_registrations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."live_events"
    ADD CONSTRAINT "live_events_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id");



ALTER TABLE ONLY "app"."live_events"
    ADD CONSTRAINT "live_events_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."media_assets"
    ADD CONSTRAINT "media_assets_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."media_assets"
    ADD CONSTRAINT "media_assets_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "app"."lessons"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."media_assets"
    ADD CONSTRAINT "media_assets_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."media_objects"
    ADD CONSTRAINT "media_objects_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."media_resolution_failures"
    ADD CONSTRAINT "media_resolution_failures_lesson_media_id_fkey" FOREIGN KEY ("lesson_media_id") REFERENCES "app"."lesson_media"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."meditations"
    ADD CONSTRAINT "meditations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."meditations"
    ADD CONSTRAINT "meditations_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "app"."media_objects"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."meditations"
    ADD CONSTRAINT "meditations_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."memberships"
    ADD CONSTRAINT "memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."messages"
    ADD CONSTRAINT "messages_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."messages"
    ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."music_tracks"
    ADD CONSTRAINT "music_tracks_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."music_tracks"
    ADD CONSTRAINT "music_tracks_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."notification_audiences"
    ADD CONSTRAINT "notification_audiences_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."notification_audiences"
    ADD CONSTRAINT "notification_audiences_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "app"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."notification_audiences"
    ADD CONSTRAINT "notification_audiences_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "app"."notification_campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."notification_campaigns"
    ADD CONSTRAINT "notification_campaigns_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."notification_deliveries"
    ADD CONSTRAINT "notification_deliveries_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "app"."notification_campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."notification_deliveries"
    ADD CONSTRAINT "notification_deliveries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."orders"
    ADD CONSTRAINT "orders_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."orders"
    ADD CONSTRAINT "orders_service_id_fkey" FOREIGN KEY ("service_id") REFERENCES "app"."services"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."orders"
    ADD CONSTRAINT "orders_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "app"."sessions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."orders"
    ADD CONSTRAINT "orders_session_slot_id_fkey" FOREIGN KEY ("session_slot_id") REFERENCES "app"."session_slots"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."orders"
    ADD CONSTRAINT "orders_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."payments"
    ADD CONSTRAINT "payments_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "app"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."posts"
    ADD CONSTRAINT "posts_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."profiles"
    ADD CONSTRAINT "profiles_avatar_media_id_fkey" FOREIGN KEY ("avatar_media_id") REFERENCES "app"."media_objects"("id");



ALTER TABLE ONLY "app"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."purchases"
    ADD CONSTRAINT "purchases_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "app"."orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."purchases"
    ADD CONSTRAINT "purchases_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."quiz_questions"
    ADD CONSTRAINT "quiz_questions_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."quiz_questions"
    ADD CONSTRAINT "quiz_questions_quiz_id_fkey" FOREIGN KEY ("quiz_id") REFERENCES "app"."course_quizzes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."reviews"
    ADD CONSTRAINT "reviews_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."reviews"
    ADD CONSTRAINT "reviews_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "app"."orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."reviews"
    ADD CONSTRAINT "reviews_reviewer_id_fkey" FOREIGN KEY ("reviewer_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."reviews"
    ADD CONSTRAINT "reviews_service_id_fkey" FOREIGN KEY ("service_id") REFERENCES "app"."services"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "app"."courses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_home_player_upload_id_fkey" FOREIGN KEY ("home_player_upload_id") REFERENCES "app"."home_player_uploads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "app"."lessons"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_lesson_media_id_fkey" FOREIGN KEY ("lesson_media_id") REFERENCES "app"."lesson_media"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_media_asset_id_fkey" FOREIGN KEY ("media_asset_id") REFERENCES "app"."media_assets"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_media_object_id_fkey" FOREIGN KEY ("media_object_id") REFERENCES "app"."media_objects"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."runtime_media"
    ADD CONSTRAINT "runtime_media_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."seminar_attendees"
    ADD CONSTRAINT "seminar_attendees_seminar_id_fkey" FOREIGN KEY ("seminar_id") REFERENCES "app"."seminars"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."seminar_attendees"
    ADD CONSTRAINT "seminar_attendees_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."seminar_recordings"
    ADD CONSTRAINT "seminar_recordings_seminar_id_fkey" FOREIGN KEY ("seminar_id") REFERENCES "app"."seminars"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."seminar_recordings"
    ADD CONSTRAINT "seminar_recordings_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "app"."seminar_sessions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."seminar_sessions"
    ADD CONSTRAINT "seminar_sessions_seminar_id_fkey" FOREIGN KEY ("seminar_id") REFERENCES "app"."seminars"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."seminars"
    ADD CONSTRAINT "seminars_host_id_fkey" FOREIGN KEY ("host_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."services"
    ADD CONSTRAINT "services_provider_id_fkey" FOREIGN KEY ("provider_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."session_slots"
    ADD CONSTRAINT "session_slots_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "app"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."sessions"
    ADD CONSTRAINT "sessions_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."stripe_customers"
    ADD CONSTRAINT "stripe_customers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."subscriptions"
    ADD CONSTRAINT "subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."tarot_requests"
    ADD CONSTRAINT "tarot_requests_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."teacher_accounts"
    ADD CONSTRAINT "teacher_accounts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."teacher_approvals"
    ADD CONSTRAINT "teacher_approvals_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "app"."profiles"("user_id");



ALTER TABLE ONLY "app"."teacher_approvals"
    ADD CONSTRAINT "teacher_approvals_reviewer_id_fkey" FOREIGN KEY ("reviewer_id") REFERENCES "app"."profiles"("user_id");



ALTER TABLE ONLY "app"."teacher_approvals"
    ADD CONSTRAINT "teacher_approvals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."teacher_directory"
    ADD CONSTRAINT "teacher_directory_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."teacher_payout_methods"
    ADD CONSTRAINT "teacher_payout_methods_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."teacher_permissions"
    ADD CONSTRAINT "teacher_permissions_granted_by_fkey" FOREIGN KEY ("granted_by") REFERENCES "app"."profiles"("user_id");



ALTER TABLE ONLY "app"."teacher_permissions"
    ADD CONSTRAINT "teacher_permissions_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."teacher_profile_media"
    ADD CONSTRAINT "teacher_profile_media_cover_media_id_fkey" FOREIGN KEY ("cover_media_id") REFERENCES "app"."media_objects"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."teacher_profile_media"
    ADD CONSTRAINT "teacher_profile_media_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "app"."lesson_media"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "app"."teacher_profile_media"
    ADD CONSTRAINT "teacher_profile_media_teacher_id_fkey" FOREIGN KEY ("teacher_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."teachers"
    ADD CONSTRAINT "teachers_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "app"."welcome_cards"
    ADD CONSTRAINT "welcome_cards_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "app"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."coupons"
    ADD CONSTRAINT "coupons_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."subscription_plans"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."subscription_plans"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_certifications"
    ADD CONSTRAINT "user_certifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "app"."activities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "activities_read" ON "app"."activities" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "activities_service" ON "app"."activities" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."app_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "attendees_read" ON "app"."seminar_attendees" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."seminars" "s"
  WHERE (("s"."id" = "seminar_attendees"."seminar_id") AND ("s"."host_id" = "auth"."uid"()))))));



CREATE POLICY "attendees_service" ON "app"."seminar_attendees" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "attendees_write" ON "app"."seminar_attendees" TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."seminars" "s"
  WHERE (("s"."id" = "seminar_attendees"."seminar_id") AND ("s"."host_id" = "auth"."uid"())))))) WITH CHECK ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."seminars" "s"
  WHERE (("s"."id" = "seminar_attendees"."seminar_id") AND ("s"."host_id" = "auth"."uid"()))))));



ALTER TABLE "app"."auth_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "auth_events_service" ON "app"."auth_events" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."billing_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "billing_logs_service" ON "app"."billing_logs" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."certificates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "certificates_service" ON "app"."certificates" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."classroom_messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "classroom_messages_access" ON "app"."classroom_messages" TO "authenticated" USING ("app"."has_course_classroom_access"("course_id", "auth"."uid"())) WITH CHECK ("app"."has_course_classroom_access"("course_id", "auth"."uid"()));



CREATE POLICY "classroom_messages_service" ON "app"."classroom_messages" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."classroom_presence" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "classroom_presence_access" ON "app"."classroom_presence" TO "authenticated" USING ("app"."has_course_classroom_access"("course_id", "auth"."uid"())) WITH CHECK ("app"."has_course_classroom_access"("course_id", "auth"."uid"()));



CREATE POLICY "classroom_presence_service" ON "app"."classroom_presence" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."course_bundle_courses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "course_bundle_courses_admin" ON "app"."course_bundle_courses" TO "authenticated" USING ("app"."is_admin"("auth"."uid"())) WITH CHECK ("app"."is_admin"("auth"."uid"()));



CREATE POLICY "course_bundle_courses_owner" ON "app"."course_bundle_courses" USING (("auth"."uid"() IN ( SELECT "course_bundles"."teacher_id"
   FROM "app"."course_bundles"
  WHERE ("course_bundles"."id" = "course_bundle_courses"."bundle_id")))) WITH CHECK (("auth"."uid"() IN ( SELECT "course_bundles"."teacher_id"
   FROM "app"."course_bundles"
  WHERE ("course_bundles"."id" = "course_bundle_courses"."bundle_id"))));



CREATE POLICY "course_bundle_courses_service_role" ON "app"."course_bundle_courses" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."course_bundles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "course_bundles_admin" ON "app"."course_bundles" TO "authenticated" USING ("app"."is_admin"("auth"."uid"())) WITH CHECK ("app"."is_admin"("auth"."uid"()));



CREATE POLICY "course_bundles_owner_write" ON "app"."course_bundles" USING (("auth"."uid"() = "teacher_id")) WITH CHECK (("auth"."uid"() = "teacher_id"));



CREATE POLICY "course_bundles_public_read" ON "app"."course_bundles" FOR SELECT USING (("is_active" = true));



CREATE POLICY "course_bundles_service_role" ON "app"."course_bundles" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "course_display_owner" ON "app"."course_display_priorities" TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."course_display_priorities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "course_display_service" ON "app"."course_display_priorities" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."course_entitlements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "course_entitlements_owner_read" ON "app"."course_entitlements" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "course_entitlements_owner_update" ON "app"."course_entitlements" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "course_entitlements_self_read" ON "app"."course_entitlements" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "course_entitlements_service_role" ON "app"."course_entitlements" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."course_products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "course_products_owner" ON "app"."course_products" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."courses" "c"
  WHERE (("c"."id" = "course_products"."course_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "app"."courses" "c"
  WHERE (("c"."id" = "course_products"."course_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))));



CREATE POLICY "course_products_service_role" ON "app"."course_products" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."course_quizzes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "app"."courses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "courses_owner_write" ON "app"."courses" TO "authenticated" USING ((("created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "courses_public_read" ON "app"."courses" FOR SELECT USING ((("is_published" = true) OR ("created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "courses_service_role" ON "app"."courses" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."enrollments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "enrollments_service" ON "app"."enrollments" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "enrollments_user" ON "app"."enrollments" TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."courses" "c"
  WHERE (("c"."id" = "enrollments"."course_id") AND ("c"."created_by" = "auth"."uid"())))))) WITH CHECK ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."entitlements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "entitlements_service_role" ON "app"."entitlements" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "entitlements_student" ON "app"."entitlements" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "entitlements_teacher" ON "app"."entitlements" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."courses" "c"
  WHERE (("c"."id" = "entitlements"."course_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))));



ALTER TABLE "app"."event_participants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "event_participants_delete" ON "app"."event_participants" FOR DELETE TO "authenticated" USING (("app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."events" "e"
  WHERE (("e"."id" = "event_participants"."event_id") AND (("e"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))) OR (EXISTS ( SELECT 1
   FROM "app"."event_participants" "h"
  WHERE (("h"."event_id" = "h"."event_id") AND ("h"."user_id" = "auth"."uid"()) AND ("h"."role" = 'host'::"app"."event_participant_role") AND ("h"."status" <> 'cancelled'::"app"."event_participant_status"))))));



CREATE POLICY "event_participants_insert" ON "app"."event_participants" FOR INSERT TO "authenticated" WITH CHECK (("app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."events" "e"
  WHERE (("e"."id" = "event_participants"."event_id") AND (("e"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))) OR (("user_id" = "auth"."uid"()) AND ("role" = 'participant'::"app"."event_participant_role"))));



CREATE POLICY "event_participants_read" ON "app"."event_participants" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."events" "e"
  WHERE (("e"."id" = "event_participants"."event_id") AND (("e"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))) OR (EXISTS ( SELECT 1
   FROM "app"."event_participants" "h"
  WHERE (("h"."event_id" = "h"."event_id") AND ("h"."user_id" = "auth"."uid"()) AND ("h"."role" = 'host'::"app"."event_participant_role") AND ("h"."status" <> 'cancelled'::"app"."event_participant_status"))))));



CREATE POLICY "event_participants_service_role" ON "app"."event_participants" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "event_participants_update" ON "app"."event_participants" FOR UPDATE TO "authenticated" USING (("app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."events" "e"
  WHERE (("e"."id" = "event_participants"."event_id") AND (("e"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))) OR (EXISTS ( SELECT 1
   FROM "app"."event_participants" "h"
  WHERE (("h"."event_id" = "h"."event_id") AND ("h"."user_id" = "auth"."uid"()) AND ("h"."role" = 'host'::"app"."event_participant_role") AND ("h"."status" <> 'cancelled'::"app"."event_participant_status")))))) WITH CHECK (("app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."events" "e"
  WHERE (("e"."id" = "event_participants"."event_id") AND (("e"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))) OR (EXISTS ( SELECT 1
   FROM "app"."event_participants" "h"
  WHERE (("h"."event_id" = "h"."event_id") AND ("h"."user_id" = "auth"."uid"()) AND ("h"."role" = 'host'::"app"."event_participant_role") AND ("h"."status" <> 'cancelled'::"app"."event_participant_status"))))));



ALTER TABLE "app"."events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "events_owner_rw" ON "app"."events" TO "authenticated" USING (((("created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK (((("created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "events_read" ON "app"."events" FOR SELECT TO "authenticated" USING ((("created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."event_participants" "ep"
  WHERE (("ep"."event_id" = "ep"."id") AND ("ep"."user_id" = "auth"."uid"()) AND ("ep"."status" <> 'cancelled'::"app"."event_participant_status")))) OR (("status" <> 'draft'::"app"."event_status") AND (("visibility" = 'public'::"app"."event_visibility") OR (("visibility" = 'members'::"app"."event_visibility") AND (EXISTS ( SELECT 1
   FROM "app"."memberships" "m"
  WHERE (("m"."user_id" = "auth"."uid"()) AND ("m"."status" = 'active'::"text") AND (("m"."end_date" IS NULL) OR ("m"."end_date" > "now"()))))))))));



CREATE POLICY "events_service_role" ON "app"."events" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."follows" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "follows_user" ON "app"."follows" TO "authenticated" USING ((("follower_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("follower_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."guest_claim_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "guest_claim_tokens_service_role" ON "app"."guest_claim_tokens" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."home_player_course_links" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "home_player_course_links_owner" ON "app"."home_player_course_links" TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."home_player_uploads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "home_player_uploads_owner" ON "app"."home_player_uploads" TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."lesson_media" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lesson_media_select" ON "app"."lesson_media" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("app"."lessons" "l"
     JOIN "app"."courses" "c" ON (("c"."id" = "l"."course_id")))
  WHERE (("l"."id" = "lesson_media"."lesson_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR ("c"."is_published" AND ("l"."is_intro" = true)) OR (EXISTS ( SELECT 1
           FROM "app"."enrollments" "e"
          WHERE (("e"."course_id" = "c"."id") AND ("e"."user_id" = "auth"."uid"())))))))));



CREATE POLICY "lesson_media_service" ON "app"."lesson_media" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "lesson_media_write" ON "app"."lesson_media" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("app"."lessons" "l"
     JOIN "app"."courses" "c" ON (("c"."id" = "l"."course_id")))
  WHERE (("l"."id" = "lesson_media"."lesson_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("app"."lessons" "l"
     JOIN "app"."courses" "c" ON (("c"."id" = "l"."course_id")))
  WHERE (("l"."id" = "lesson_media"."lesson_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))));



ALTER TABLE "app"."lesson_packages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lesson_packages_owner" ON "app"."lesson_packages" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("app"."lessons" "l"
     JOIN "app"."courses" "c" ON (("c"."id" = "l"."course_id")))
  WHERE (("l"."id" = "lesson_packages"."lesson_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("app"."lessons" "l"
     JOIN "app"."courses" "c" ON (("c"."id" = "l"."course_id")))
  WHERE (("l"."id" = "lesson_packages"."lesson_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))));



CREATE POLICY "lesson_packages_service_role" ON "app"."lesson_packages" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."lessons" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lessons_select" ON "app"."lessons" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."courses" "c"
  WHERE (("c"."id" = "lessons"."course_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR ("c"."is_published" AND ("lessons"."is_intro" = true)) OR (EXISTS ( SELECT 1
           FROM "app"."enrollments" "e"
          WHERE (("e"."course_id" = "c"."id") AND ("e"."user_id" = "auth"."uid"())))))))));



CREATE POLICY "lessons_service_role" ON "app"."lessons" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "lessons_write" ON "app"."lessons" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."courses" "c"
  WHERE (("c"."id" = "lessons"."course_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "app"."courses" "c"
  WHERE (("c"."id" = "lessons"."course_id") AND (("c"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))));



ALTER TABLE "app"."live_event_registrations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "live_event_registrations_read" ON "app"."live_event_registrations" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."live_events" "e"
  WHERE (("e"."id" = "live_event_registrations"."event_id") AND ("e"."teacher_id" = "auth"."uid"()))))));



CREATE POLICY "live_event_registrations_service" ON "app"."live_event_registrations" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "live_event_registrations_write" ON "app"."live_event_registrations" TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."live_events" "e"
  WHERE (("e"."id" = "live_event_registrations"."event_id") AND ("e"."teacher_id" = "auth"."uid"())))))) WITH CHECK ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."live_events" "e"
  WHERE (("e"."id" = "live_event_registrations"."event_id") AND ("e"."teacher_id" = "auth"."uid"()))))));



ALTER TABLE "app"."live_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "live_events_access" ON "app"."live_events" FOR SELECT TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (("is_published" = true) AND (("access_type" = 'membership'::"text") OR (("access_type" = 'course'::"text") AND ("course_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "app"."enrollments" "e"
  WHERE (("e"."user_id" = "auth"."uid"()) AND ("e"."course_id" = "live_events"."course_id")))))))));



CREATE POLICY "live_events_host_rw" ON "app"."live_events" TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "live_events_service" ON "app"."live_events" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "livekit_jobs_service" ON "app"."livekit_webhook_jobs" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."livekit_webhook_jobs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "app"."media_objects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "media_owner_rw" ON "app"."media_objects" TO "authenticated" USING ((("owner_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("owner_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "media_service_role" ON "app"."media_objects" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."meditations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "meditations_service" ON "app"."meditations" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."memberships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "memberships_self" ON "app"."memberships" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "memberships_service" ON "app"."memberships" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "messages_user" ON "app"."messages" TO "authenticated" USING ((("sender_id" = "auth"."uid"()) OR ("recipient_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("sender_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."music_tracks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "music_tracks_entitled_read" ON "app"."music_tracks" FOR SELECT TO "authenticated" USING ((("is_published" = true) AND ((("access_scope" = 'membership'::"text") AND ("auth"."uid"() IS NOT NULL) AND ((EXISTS ( SELECT 1
   FROM "app"."memberships" "m"
  WHERE (("m"."user_id" = "auth"."uid"()) AND ("lower"(COALESCE("m"."status", 'active'::"text")) <> ALL (ARRAY['canceled'::"text", 'unpaid'::"text", 'incomplete_expired'::"text", 'past_due'::"text"]))))) OR true)) OR (("access_scope" = 'course'::"text") AND ("course_id" IS NOT NULL) AND "app"."has_course_classroom_access"("course_id", "auth"."uid"())))));



CREATE POLICY "music_tracks_owner" ON "app"."music_tracks" TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "music_tracks_service" ON "app"."music_tracks" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."notification_audiences" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_audiences_owner_rw" ON "app"."notification_audiences" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."notification_campaigns" "n"
  WHERE (("n"."id" = "notification_audiences"."notification_id") AND ((("n"."created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "app"."notification_campaigns" "n"
  WHERE (("n"."id" = "notification_audiences"."notification_id") AND ((("n"."created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"()))))));



CREATE POLICY "notification_audiences_service_role" ON "app"."notification_audiences" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."notification_campaigns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_campaigns_owner_rw" ON "app"."notification_campaigns" TO "authenticated" USING (((("created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK (((("created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "notification_campaigns_service_role" ON "app"."notification_campaigns" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."notification_deliveries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_deliveries_delete" ON "app"."notification_deliveries" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."notification_campaigns" "n"
  WHERE (("n"."id" = "notification_deliveries"."notification_id") AND ((("n"."created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"()))))));



CREATE POLICY "notification_deliveries_insert" ON "app"."notification_deliveries" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "app"."notification_campaigns" "n"
  WHERE (("n"."id" = "notification_deliveries"."notification_id") AND ((("n"."created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"()))))));



CREATE POLICY "notification_deliveries_read" ON "app"."notification_deliveries" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."notification_campaigns" "n"
  WHERE (("n"."id" = "notification_deliveries"."notification_id") AND (("n"."created_by" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())))))));



CREATE POLICY "notification_deliveries_service_role" ON "app"."notification_deliveries" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "notification_deliveries_update" ON "app"."notification_deliveries" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."notification_campaigns" "n"
  WHERE (("n"."id" = "notification_deliveries"."notification_id") AND ((("n"."created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "app"."notification_campaigns" "n"
  WHERE (("n"."id" = "notification_deliveries"."notification_id") AND ((("n"."created_by" = "auth"."uid"()) AND "app"."is_teacher"("auth"."uid"())) OR "app"."is_admin"("auth"."uid"()))))));



ALTER TABLE "app"."notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notifications_user" ON "app"."notifications" TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orders_service" ON "app"."orders" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "orders_user_read" ON "app"."orders" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "app"."services" "s"
  WHERE (("s"."id" = "orders"."service_id") AND ("s"."provider_id" = "auth"."uid"()))))));



CREATE POLICY "orders_user_write" ON "app"."orders" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."payment_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payment_events_service" ON "app"."payment_events" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."payments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payments_read" ON "app"."payments" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."orders" "o"
  WHERE (("o"."id" = "payments"."order_id") AND (("o"."user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
           FROM "app"."services" "s"
          WHERE (("s"."id" = "o"."service_id") AND ("s"."provider_id" = "auth"."uid"())))))))));



CREATE POLICY "payments_service" ON "app"."payments" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "payout_service" ON "app"."teacher_payout_methods" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "payout_teacher" ON "app"."teacher_payout_methods" TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."posts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "posts_author" ON "app"."posts" TO "authenticated" USING ((("author_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("author_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "posts_service" ON "app"."posts" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_self_read" ON "app"."profiles" FOR SELECT USING ((("auth"."uid"() = "user_id") OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "profiles_self_write" ON "app"."profiles" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "user_id") OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("auth"."uid"() = "user_id") OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."purchases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "purchases_owner_read" ON "app"."purchases" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "purchases_service_role" ON "app"."purchases" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."quiz_questions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quiz_questions_service" ON "app"."quiz_questions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "quizzes_service" ON "app"."course_quizzes" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."refresh_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "refresh_tokens_service" ON "app"."refresh_tokens" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."reviews" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reviews_service" ON "app"."reviews" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "reviews_user" ON "app"."reviews" TO "authenticated" USING ((("reviewer_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("reviewer_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."seminar_attendees" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "app"."seminar_recordings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "seminar_recordings_read" ON "app"."seminar_recordings" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."seminars" "s"
  WHERE (("s"."id" = "seminar_recordings"."seminar_id") AND (("s"."host_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()) OR ("s"."status" = ANY (ARRAY['live'::"app"."seminar_status", 'ended'::"app"."seminar_status"])))))));



CREATE POLICY "seminar_recordings_service" ON "app"."seminar_recordings" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."seminar_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "seminar_sessions_host" ON "app"."seminar_sessions" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."seminars" "s"
  WHERE (("s"."id" = "seminar_sessions"."seminar_id") AND (("s"."host_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "app"."seminars" "s"
  WHERE (("s"."id" = "seminar_sessions"."seminar_id") AND (("s"."host_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))));



CREATE POLICY "seminar_sessions_service" ON "app"."seminar_sessions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."seminars" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "seminars_host_rw" ON "app"."seminars" TO "authenticated" USING ((("host_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("host_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "seminars_public_read" ON "app"."seminars" FOR SELECT USING ((("status" = ANY (ARRAY['scheduled'::"app"."seminar_status", 'live'::"app"."seminar_status", 'ended'::"app"."seminar_status"])) OR ("host_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "seminars_service" ON "app"."seminars" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."activities" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."app_config" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."auth_events" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."billing_logs" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."certificates" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."course_display_priorities" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."course_entitlements" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."course_quizzes" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."courses" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."enrollments" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."follows" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."lesson_media" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."lessons" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."live_event_registrations" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."live_events" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."livekit_webhook_jobs" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."media_objects" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."meditations" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."memberships" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."messages" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."notifications" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."orders" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."payment_events" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."payments" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."posts" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."profiles" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."quiz_questions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."refresh_tokens" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."reviews" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."seminar_attendees" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."seminar_recordings" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."seminar_sessions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."seminars" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."services" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."session_slots" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."sessions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."stripe_customers" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."tarot_requests" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."teacher_approvals" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."teacher_directory" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."teacher_payout_methods" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."teacher_permissions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."teacher_profile_media" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_full_access" ON "app"."teachers" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."services" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "services_owner_rw" ON "app"."services" TO "authenticated" USING ((("provider_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("provider_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "services_public_read" ON "app"."services" FOR SELECT USING ((("status" = 'active'::"app"."service_status") AND ("active" = true)));



CREATE POLICY "services_service" ON "app"."services" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."session_slots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "session_slots_owner" ON "app"."session_slots" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "app"."sessions" "s"
  WHERE (("s"."id" = "session_slots"."session_id") AND (("s"."teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "app"."sessions" "s"
  WHERE (("s"."id" = "session_slots"."session_id") AND (("s"."teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))))));



CREATE POLICY "session_slots_service" ON "app"."session_slots" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sessions_owner" ON "app"."sessions" TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "sessions_public_read" ON "app"."sessions" FOR SELECT USING ((("visibility" = 'published'::"app"."session_visibility") OR ("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "sessions_service" ON "app"."sessions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."stripe_customers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stripe_customers_service" ON "app"."stripe_customers" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."subscriptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscriptions_self_read" ON "app"."subscriptions" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "subscriptions_service_role" ON "app"."subscriptions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."tarot_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tarot_service" ON "app"."tarot_requests" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."teacher_accounts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "teacher_accounts_self" ON "app"."teacher_accounts" TO "authenticated" USING ((("auth"."uid"() = "user_id") OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("auth"."uid"() = "user_id") OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "teacher_accounts_service_role" ON "app"."teacher_accounts" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."teacher_approvals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "teacher_approvals_service" ON "app"."teacher_approvals" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."teacher_directory" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "teacher_directory_service" ON "app"."teacher_directory" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "teacher_meta_service" ON "app"."teacher_permissions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "app"."teacher_payout_methods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "app"."teacher_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "app"."teacher_profile_media" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "app"."teachers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "teachers_owner" ON "app"."teachers" TO "authenticated" USING ((("profile_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("profile_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "teachers_service" ON "app"."teachers" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "tpm_public_read" ON "app"."teacher_profile_media" FOR SELECT USING (("is_published" = true));



CREATE POLICY "tpm_teacher" ON "app"."teacher_profile_media" TO "authenticated" USING ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK ((("teacher_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



ALTER TABLE "app"."welcome_cards" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "welcome_cards_active_read" ON "app"."welcome_cards" FOR SELECT TO "authenticated" USING (("is_active" = true));



CREATE POLICY "welcome_cards_manage" ON "app"."welcome_cards" TO "authenticated" USING (((("created_by" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "app"."profiles" "p"
  WHERE (("p"."user_id" = "auth"."uid"()) AND (("p"."role_v2" = 'teacher'::"app"."user_role") OR ("p"."is_admin" = true)))))) OR "app"."is_admin"("auth"."uid"()))) WITH CHECK (((("created_by" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "app"."profiles" "p"
  WHERE (("p"."user_id" = "auth"."uid"()) AND (("p"."role_v2" = 'teacher'::"app"."user_role") OR ("p"."is_admin" = true)))))) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "welcome_cards_owner_read" ON "app"."welcome_cards" FOR SELECT TO "authenticated" USING (((("created_by" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "app"."profiles" "p"
  WHERE (("p"."user_id" = "auth"."uid"()) AND (("p"."role_v2" = 'teacher'::"app"."user_role") OR ("p"."is_admin" = true)))))) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "welcome_cards_service_role" ON "app"."welcome_cards" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."coupons" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "coupons_service_role" ON "public"."coupons" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "public_subscriptions_self_read" ON "public"."subscriptions" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "public_subscriptions_service_role" ON "public"."subscriptions" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."subscription_plans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscription_plans_public_read" ON "public"."subscription_plans" FOR SELECT USING (("is_active" = true));



CREATE POLICY "subscription_plans_service_role" ON "public"."subscription_plans" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_certifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_certifications_self_read" ON "public"."user_certifications" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "app"."is_admin"("auth"."uid"())));



CREATE POLICY "user_certifications_service_role" ON "public"."user_certifications" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "app" TO "anon";
GRANT USAGE ON SCHEMA "app" TO "authenticated";
GRANT USAGE ON SCHEMA "app" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminars" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminars" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminars" TO "service_role";



GRANT ALL ON FUNCTION "public"."rest_insert_seminar"("p_host_id" "uuid", "p_title" "text", "p_status" "app"."seminar_status") TO "anon";
GRANT ALL ON FUNCTION "public"."rest_insert_seminar"("p_host_id" "uuid", "p_title" "text", "p_status" "app"."seminar_status") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rest_insert_seminar"("p_host_id" "uuid", "p_title" "text", "p_status" "app"."seminar_status") TO "service_role";



GRANT ALL ON FUNCTION "public"."rest_select_seminar"("p_seminar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."rest_select_seminar"("p_seminar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rest_select_seminar"("p_seminar_id" "uuid") TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_attendees" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_attendees" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_attendees" TO "service_role";



GRANT ALL ON FUNCTION "public"."rest_select_seminar_attendees"("p_seminar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."rest_select_seminar_attendees"("p_seminar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rest_select_seminar_attendees"("p_seminar_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."rest_update_seminar_description"("p_seminar_id" "uuid", "p_description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rest_update_seminar_description"("p_seminar_id" "uuid", "p_description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rest_update_seminar_description"("p_seminar_id" "uuid", "p_description" "text") TO "service_role";












GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."activities" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."activities" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."activities" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."activities_feed" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."activities_feed" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."activities_feed" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."app_config" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."app_config" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."app_config" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."auth_events" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."auth_events" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."auth_events" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."billing_logs" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."billing_logs" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."billing_logs" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."certificates" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."certificates" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."certificates" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."classroom_messages" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."classroom_messages" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."classroom_messages" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."classroom_presence" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."classroom_presence" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."classroom_presence" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_bundle_courses" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_bundle_courses" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_bundle_courses" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_bundles" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_bundles" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_bundles" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_display_priorities" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_display_priorities" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_display_priorities" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."courses" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."courses" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."courses" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."entitlements" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."entitlements" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."entitlements" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_enrollments_view" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_enrollments_view" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_enrollments_view" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_entitlements" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_entitlements" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_entitlements" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_products" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_products" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_products" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_quizzes" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_quizzes" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."course_quizzes" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."enrollments" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."enrollments" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."enrollments" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."event_participants" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."event_participants" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."event_participants" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."events" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."events" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."events" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."follows" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."follows" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."follows" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."guest_claim_tokens" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."guest_claim_tokens" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."guest_claim_tokens" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."home_player_course_links" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."home_player_course_links" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."home_player_course_links" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."home_player_uploads" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."home_player_uploads" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."home_player_uploads" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."intro_usage" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."intro_usage" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."intro_usage" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_media" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_media" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_media" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_media_issues" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_media_issues" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_media_issues" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_packages" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_packages" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lesson_packages" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lessons" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lessons" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."lessons" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."live_event_registrations" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."live_event_registrations" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."live_event_registrations" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."live_events" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."live_events" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."live_events" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."livekit_webhook_jobs" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."livekit_webhook_jobs" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."livekit_webhook_jobs" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_assets" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_assets" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_assets" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_objects" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_objects" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_objects" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_resolution_failures" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_resolution_failures" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."media_resolution_failures" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."meditations" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."meditations" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."meditations" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."memberships" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."memberships" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."memberships" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."messages" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."messages" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."messages" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."music_tracks" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."music_tracks" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."music_tracks" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_audiences" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_audiences" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_audiences" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_campaigns" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_campaigns" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_campaigns" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_deliveries" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_deliveries" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notification_deliveries" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notifications" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notifications" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."notifications" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."orders" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."orders" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."orders" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."payment_events" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."payment_events" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."payment_events" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."payments" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."payments" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."payments" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."posts" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."posts" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."posts" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."profiles" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."profiles" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."profiles" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."purchases" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."purchases" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."purchases" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."quiz_questions" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."quiz_questions" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."quiz_questions" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."referral_codes" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."referral_codes" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."referral_codes" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."refresh_tokens" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."refresh_tokens" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."refresh_tokens" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."reviews" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."reviews" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."reviews" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."runtime_media" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."runtime_media" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."runtime_media" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_recordings" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_recordings" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_recordings" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_sessions" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_sessions" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."seminar_sessions" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."services" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."services" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."services" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."service_orders" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."service_orders" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."service_orders" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."service_reviews" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."service_reviews" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."service_reviews" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."session_slots" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."session_slots" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."session_slots" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."sessions" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."sessions" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."sessions" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."stripe_customers" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."stripe_customers" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."stripe_customers" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."subscriptions" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."subscriptions" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."subscriptions" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."tarot_requests" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."tarot_requests" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."tarot_requests" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_accounts" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_accounts" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_accounts" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_approvals" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_approvals" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_approvals" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_directory" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_directory" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_directory" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_payout_methods" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_payout_methods" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_payout_methods" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_permissions" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_permissions" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_permissions" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_profile_media" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_profile_media" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teacher_profile_media" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teachers" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teachers" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."teachers" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."v_meditation_audio_library" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."v_meditation_audio_library" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."v_meditation_audio_library" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."welcome_cards" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."welcome_cards" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "app"."welcome_cards" TO "service_role";









GRANT ALL ON TABLE "public"."coupons" TO "anon";
GRANT ALL ON TABLE "public"."coupons" TO "authenticated";
GRANT ALL ON TABLE "public"."coupons" TO "service_role";



GRANT ALL ON TABLE "public"."subscription_plans" TO "anon";
GRANT ALL ON TABLE "public"."subscription_plans" TO "authenticated";
GRANT ALL ON TABLE "public"."subscription_plans" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."user_certifications" TO "anon";
GRANT ALL ON TABLE "public"."user_certifications" TO "authenticated";
GRANT ALL ON TABLE "public"."user_certifications" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "app" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "app" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "app" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";


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



