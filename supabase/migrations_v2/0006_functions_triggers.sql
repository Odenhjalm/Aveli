-- 0006_functions_triggers.sql
-- Helper functions and touch triggers.

begin;

-- ---------------------------------------------------------------------------
-- Updated-at helpers
-- ---------------------------------------------------------------------------
create or replace function app.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function app.touch_course_display_priorities()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function app.touch_teacher_profile_media()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function app.touch_course_entitlements()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function app.touch_livekit_webhook_jobs()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Authorization helpers
-- ---------------------------------------------------------------------------
create or replace function app.is_admin(p_user uuid)
returns boolean
language sql
as $$
  select exists (
    select 1 from app.profiles
    where user_id = p_user and is_admin = true
  );
$$;

create or replace function app.is_seminar_host(p_seminar_id uuid, p_user_id uuid)
returns boolean
language plpgsql
stable
as $$
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

create or replace function app.is_seminar_host(p_seminar_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_seminar_host(p_seminar_id, auth.uid());
$$;

create or replace function app.is_seminar_attendee(p_seminar_id uuid, p_user_id uuid)
returns boolean
language sql
as $$
  select exists(
    select 1
    from app.seminar_attendees sa
    where sa.seminar_id = p_seminar_id
      and sa.user_id = p_user_id
  );
$$;

create or replace function app.is_seminar_attendee(p_seminar_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_seminar_attendee(p_seminar_id, auth.uid());
$$;

create or replace function app.can_access_seminar(p_seminar_id uuid, p_user_id uuid)
returns boolean
language sql
stable
as $$
  select
    app.is_seminar_host(p_seminar_id, p_user_id)
    or app.is_seminar_attendee(p_seminar_id, p_user_id);
$$;

create or replace function app.can_access_seminar(p_seminar_id uuid)
returns boolean
language sql
stable
as $$
  select app.can_access_seminar(p_seminar_id, auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- Quiz grading
-- ---------------------------------------------------------------------------
create or replace function app.grade_quiz_and_issue_certificate(
  p_quiz_id uuid,
  p_answers jsonb
)
returns table (passed boolean, score integer)
language plpgsql
as $$
declare
  q record;
  total_questions integer;
  correct_count integer := 0;
  pass_score integer;
  answer jsonb;
  answer_text text;
  correct_int integer;
  correct_bool boolean;
  correct_array int[];
  answer_array int[];
begin
  select cq.pass_score
    into pass_score
    from app.course_quizzes cq
   where cq.id = p_quiz_id;

  if pass_score is null then
    pass_score := 80;
  end if;

  select count(*)
    into total_questions
    from app.quiz_questions
   where quiz_id = p_quiz_id;

  for q in select id, kind, correct from app.quiz_questions where quiz_id = p_quiz_id loop
    answer := p_answers -> q.id::text;
    if answer is null then
      continue;
    end if;

    if q.kind = 'multi' then
      if jsonb_typeof(answer) = 'array' then
        select array_agg(distinct (m[1])::int order by (m[1])::int)
          into correct_array
          from regexp_matches(coalesce(q.correct, ''), '\\d+', 'g') as m;

        select array_agg(distinct value::int order by value::int)
          into answer_array
          from jsonb_array_elements_text(answer) as value;

        if correct_array is not null and answer_array is not null and correct_array = answer_array then
          correct_count := correct_count + 1;
        end if;
      end if;
    elsif q.kind = 'boolean' then
      answer_text := lower(answer #>> '{}');
      if answer_text in ('true', 'false') then
        correct_bool := lower(coalesce(q.correct, '')) = 'true';
        if answer_text = case when correct_bool then 'true' else 'false' end then
          correct_count := correct_count + 1;
        end if;
      end if;
    else
      answer_text := answer #>> '{}';
      if answer_text is not null then
        select nullif(regexp_replace(coalesce(q.correct, ''), '\\D', '', 'g'), '')::int
          into correct_int;
        if correct_int is not null and answer_text ~ '^[0-9]+$' and answer_text::int = correct_int then
          correct_count := correct_count + 1;
        end if;
      end if;
    end if;
  end loop;

  if total_questions is null or total_questions = 0 then
    score := 0;
  else
    score := (correct_count * 100 / total_questions);
  end if;

  passed := score >= pass_score;
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- Touch triggers
-- ---------------------------------------------------------------------------
drop trigger if exists trg_courses_touch on app.courses;
create trigger trg_courses_touch
before update on app.courses
for each row execute function app.set_updated_at();

drop trigger if exists trg_modules_touch on app.modules;
create trigger trg_modules_touch
before update on app.modules
for each row execute function app.set_updated_at();

drop trigger if exists trg_lessons_touch on app.lessons;
create trigger trg_lessons_touch
before update on app.lessons
for each row execute function app.set_updated_at();

drop trigger if exists trg_services_touch on app.services;
create trigger trg_services_touch
before update on app.services
for each row execute function app.set_updated_at();

drop trigger if exists trg_orders_touch on app.orders;
create trigger trg_orders_touch
before update on app.orders
for each row execute function app.set_updated_at();

drop trigger if exists trg_payments_touch on app.payments;
create trigger trg_payments_touch
before update on app.payments
for each row execute function app.set_updated_at();

drop trigger if exists trg_sessions_touch on app.sessions;
create trigger trg_sessions_touch
before update on app.sessions
for each row execute function app.set_updated_at();

drop trigger if exists trg_session_slots_touch on app.session_slots;
create trigger trg_session_slots_touch
before update on app.session_slots
for each row execute function app.set_updated_at();

drop trigger if exists trg_seminars_touch on app.seminars;
create trigger trg_seminars_touch
before update on app.seminars
for each row execute function app.set_updated_at();

drop trigger if exists trg_seminar_sessions_touch on app.seminar_sessions;
create trigger trg_seminar_sessions_touch
before update on app.seminar_sessions
for each row execute function app.set_updated_at();

drop trigger if exists trg_seminar_recordings_touch on app.seminar_recordings;
create trigger trg_seminar_recordings_touch
before update on app.seminar_recordings
for each row execute function app.set_updated_at();

drop trigger if exists trg_livekit_webhook_jobs_touch on app.livekit_webhook_jobs;
create trigger trg_livekit_webhook_jobs_touch
before update on app.livekit_webhook_jobs
for each row execute function app.touch_livekit_webhook_jobs();

drop trigger if exists trg_profiles_touch on app.profiles;
create trigger trg_profiles_touch
before update on app.profiles
for each row execute function app.set_updated_at();

drop trigger if exists trg_teacher_approvals_touch on app.teacher_approvals;
create trigger trg_teacher_approvals_touch
before update on app.teacher_approvals
for each row execute function app.set_updated_at();

drop trigger if exists trg_teacher_payout_methods_touch on app.teacher_payout_methods;
create trigger trg_teacher_payout_methods_touch
before update on app.teacher_payout_methods
for each row execute function app.set_updated_at();

drop trigger if exists trg_teachers_touch on app.teachers;
create trigger trg_teachers_touch
before update on app.teachers
for each row execute function app.set_updated_at();

drop trigger if exists trg_course_display_priorities_touch on app.course_display_priorities;
create trigger trg_course_display_priorities_touch
before update on app.course_display_priorities
for each row execute function app.touch_course_display_priorities();

drop trigger if exists trg_teacher_profile_media_touch on app.teacher_profile_media;
create trigger trg_teacher_profile_media_touch
before update on app.teacher_profile_media
for each row execute function app.touch_teacher_profile_media();

drop trigger if exists trg_course_entitlements_touch on app.course_entitlements;
create trigger trg_course_entitlements_touch
before update on app.course_entitlements
for each row execute function app.touch_course_entitlements();

drop trigger if exists trg_course_products_updated on app.course_products;
create trigger trg_course_products_updated
before update on app.course_products
for each row execute function app.set_updated_at();

commit;
