-- 020_grade_quiz_and_issue_certificate.sql
-- Add quiz grading helper that issues a course certificate.

begin;

create or replace function app.grade_quiz_and_issue_certificate(
  p_quiz_id uuid,
  p_user_id uuid,
  p_answers jsonb
)
returns table (
  quiz_id uuid,
  course_id uuid,
  user_id uuid,
  score integer,
  pass_score integer,
  total_questions integer,
  correct_answers integer,
  passed boolean,
  certificate_id uuid,
  certificate_status text
)
language plpgsql
as $$
declare
  v_course_id uuid;
  v_pass_score integer;
  v_total integer;
  v_correct integer;
  v_score integer;
  v_cert_id uuid;
  v_status text;
  v_course_title text;
begin
  if p_quiz_id is null or p_user_id is null then
    return query
    select p_quiz_id, null::uuid, p_user_id, 0, null::integer, 0, 0, false, null::uuid, null::text;
    return;
  end if;

  select course_id, pass_score
    into v_course_id, v_pass_score
  from app.course_quizzes
  where id = p_quiz_id
  limit 1;

  if v_course_id is null then
    return query
    select p_quiz_id, null::uuid, p_user_id, 0, v_pass_score, 0, 0, false, null::uuid, null::text;
    return;
  end if;

  select count(*) into v_total
  from app.quiz_questions
  where quiz_id = p_quiz_id;

  if v_total = 0 then
    v_correct := 0;
    v_score := 0;
  else
    select count(*) into v_correct
    from app.quiz_questions q
    where q.quiz_id = p_quiz_id
      and q.correct is not null
      and (p_answers ->> q.id::text) = q.correct;

    v_score := floor((v_correct::numeric / v_total) * 100)::int;
  end if;

  if v_pass_score is null then
    v_pass_score := 80;
  end if;

  if v_score >= v_pass_score then
    select id, status
      into v_cert_id, v_status
    from app.certificates
    where user_id = p_user_id and course_id = v_course_id
    order by updated_at desc
    limit 1;

    if v_cert_id is null then
      select title into v_course_title
      from app.courses
      where id = v_course_id
      limit 1;

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
        p_user_id,
        v_course_id,
        coalesce(v_course_title, 'Course Certificate'),
        'verified',
        now(),
        jsonb_build_object(
          'quiz_id', p_quiz_id,
          'score', v_score,
          'correct', v_correct,
          'total', v_total
        ),
        now(),
        now()
      )
      returning id, status
      into v_cert_id, v_status;
    else
      update app.certificates
         set status = 'verified',
             issued_at = coalesce(issued_at, now()),
             metadata = coalesce(metadata, '{}'::jsonb)
                        || jsonb_build_object(
                             'quiz_id', p_quiz_id,
                             'score', v_score,
                             'correct', v_correct,
                             'total', v_total
                           ),
             updated_at = now()
       where id = v_cert_id
       returning status into v_status;
    end if;
  end if;

  return query
  select p_quiz_id,
         v_course_id,
         p_user_id,
         v_score,
         v_pass_score,
         v_total,
         v_correct,
         (v_score >= v_pass_score),
         v_cert_id,
         v_status;
end;
$$;

create or replace function app.grade_quiz_and_issue_certificate(
  p_quiz_id uuid,
  p_answers jsonb
)
returns table (
  quiz_id uuid,
  course_id uuid,
  user_id uuid,
  score integer,
  pass_score integer,
  total_questions integer,
  correct_answers integer,
  passed boolean,
  certificate_id uuid,
  certificate_status text
)
language sql
as $$
  select *
  from app.grade_quiz_and_issue_certificate(p_quiz_id, auth.uid(), p_answers);
$$;

commit;
