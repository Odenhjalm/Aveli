-- 20260203120000_course_journey_step.sql
-- Add explicit journey step classification for course placement.

begin;

alter table app.courses
  add column if not exists journey_step text;

alter table app.courses
  alter column journey_step set default 'intro';

alter table app.courses
  drop constraint if exists courses_journey_step_check;

alter table app.courses
  add constraint courses_journey_step_check
    check (
      journey_step is null
      or journey_step in ('intro', 'step1', 'step2', 'step3')
    );

commit;

