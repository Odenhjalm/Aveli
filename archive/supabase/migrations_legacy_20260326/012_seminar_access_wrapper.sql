-- 012_seminar_access_wrapper.sql
-- Add auth-aware wrapper for can_access_seminar.

begin;

create or replace function app.can_access_seminar(p_seminar_id uuid)
returns boolean
language sql
stable
as $$
  select app.can_access_seminar(p_seminar_id, auth.uid());
$$;

commit;
