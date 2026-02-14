-- 20260214110000_course_journey_contract.sql
-- Enforce journey grouping + numeric journey step contract for courses.

begin;

alter table app.courses
  add column if not exists journey_group_id text;

update app.courses
   set journey_group_id = coalesce(nullif(trim(journey_group_id), ''), slug, id::text)
 where journey_group_id is null
    or trim(journey_group_id) = '';

alter table app.courses
  alter column journey_group_id set default gen_random_uuid()::text;

alter table app.courses
  alter column journey_group_id set not null;

alter table app.courses
  drop constraint if exists courses_journey_group_id_not_blank;

alter table app.courses
  add constraint courses_journey_group_id_not_blank
    check (char_length(trim(journey_group_id)) > 0);

-- Normalize legacy text values and enforce numeric step placement.
do $$
declare
  journey_step_type text;
begin
  select data_type
    into journey_step_type
    from information_schema.columns
   where table_schema = 'app'
     and table_name = 'courses'
     and column_name = 'journey_step';

  if journey_step_type is null then
    alter table app.courses
      add column journey_step smallint;
  elsif journey_step_type in ('text', 'character varying', 'character') then
    update app.courses
       set journey_step = case lower(trim(coalesce(journey_step::text, '')))
         when 'step1' then '1'
         when 'intro' then '1'
         when 'step2' then '2'
         when 'step3' then '3'
         when '1' then '1'
         when '2' then '2'
         when '3' then '3'
         else null
       end;

    alter table app.courses
      alter column journey_step type smallint
      using nullif(trim(journey_step::text), '')::smallint;
  end if;
end
$$;

update app.courses
   set journey_step = 1
 where journey_step is null
    or journey_step not in (1, 2, 3);

alter table app.courses
  alter column journey_step set default 1;

alter table app.courses
  alter column journey_step set not null;

alter table app.courses
  drop constraint if exists courses_journey_step_check;

alter table app.courses
  add constraint courses_journey_step_check
    check (journey_step in (1, 2, 3));

commit;
