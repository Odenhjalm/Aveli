begin;

alter table app.courses
  add column if not exists step_level text,
  add column if not exists course_family text;

alter table app.courses
  alter column step_level set default 'step1',
  alter column course_family set default 'general';

update app.courses
set step_level = coalesce(
  nullif(trim(step_level), ''),
  nullif(trim(journey_step), ''),
  case when is_free_intro then 'intro' else 'step1' end
)
where step_level is null
   or trim(step_level) = '';

update app.courses
set course_family = coalesce(
  nullif(trim(course_family), ''),
  nullif(lower(regexp_replace(slug, '-(intro|step1|step2|step3)$', '')), ''),
  lower(slug)
)
where course_family is null
   or trim(course_family) = '';

alter table app.courses
  alter column step_level set not null,
  alter column course_family set not null;

alter table app.courses
  drop constraint if exists courses_step_level_check;

alter table app.courses
  add constraint courses_step_level_check
    check (step_level in ('intro', 'step1', 'step2', 'step3'));

alter table app.courses
  drop constraint if exists courses_course_family_check;

alter table app.courses
  add constraint courses_course_family_check
    check (length(trim(course_family)) > 0);

commit;
