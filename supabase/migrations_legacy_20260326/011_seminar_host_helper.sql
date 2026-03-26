-- 011_seminar_host_helper.sql
-- Add auth-aware wrapper for seminar host checks.

begin;

create or replace function app.is_seminar_host(p_seminar_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_seminar_host(p_seminar_id, auth.uid());
$$;

commit;
