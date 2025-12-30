-- 022_postgrest_seminar_rpcs.sql
-- PostgREST RPC helpers for seminar RLS smoke tests.

begin;

create or replace function public.rest_select_seminar(p_seminar_id uuid)
returns setof app.seminars
language sql
as $$
  select *
  from app.seminars
  where id = p_seminar_id;
$$;

create or replace function public.rest_select_seminar_attendees(p_seminar_id uuid)
returns setof app.seminar_attendees
language sql
as $$
  select *
  from app.seminar_attendees
  where seminar_id = p_seminar_id;
$$;

create or replace function public.rest_insert_seminar(
  p_host_id uuid,
  p_title text,
  p_status text
)
returns jsonb
language plpgsql
as $$
declare
  result jsonb;
begin
  insert into app.seminars as s (host_id, title, status)
  values (p_host_id, p_title, p_status::app.seminar_status)
  returning to_jsonb(s.*) into result;
  return result;
end;
$$;

create or replace function public.rest_update_seminar_description(
  p_seminar_id uuid,
  p_description text
)
returns jsonb
language plpgsql
as $$
declare
  result jsonb;
begin
  update app.seminars as s
     set description = p_description,
         updated_at = now()
   where s.id = p_seminar_id
   returning to_jsonb(s.*) into result;

  if result is null then
    return jsonb_build_object('id', null);
  end if;

  return result;
end;
$$;

commit;
