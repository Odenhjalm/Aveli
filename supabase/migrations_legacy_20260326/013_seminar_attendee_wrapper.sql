-- 013_seminar_attendee_wrapper.sql
-- Add auth-aware wrapper for is_seminar_attendee.

begin;

create or replace function app.is_seminar_attendee(p_seminar_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_seminar_attendee(p_seminar_id, auth.uid());
$$;

commit;
