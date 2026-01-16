-- 020_quiz_grading.sql
-- Grade quiz answers and issue course certificates.

begin;

create or replace function app.grade_quiz_and_issue_certificate(
  p_quiz_id uuid,
  p_user_id uuid,
  p_answers jsonb
)
returns table (
  passed boolean,
  score text,
  correct_count integer,
  question_count integer,
  pass_score integer,
  certificate_id uuid
)
language plpgsql
security definer
set search_path = app, public
as $$
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
$$;

commit;
