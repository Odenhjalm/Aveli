-- 014_seminar_host_guard.sql
-- Guarded is_seminar_host to prevent impersonation unless service role.

begin;

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

commit;
