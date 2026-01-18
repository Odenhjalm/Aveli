-- 20260118020000_postgrest_seminar_rpc.sql
-- PostgREST RPC helpers for seminar RLS smoke tests.

create or replace function public.rest_select_seminar(p_seminar_id uuid)
returns setof app.seminars
language sql
stable
as $$
  select *
  from app.seminars
  where id = p_seminar_id;
$$;

create or replace function public.rest_select_seminar_attendees(p_seminar_id uuid)
returns setof app.seminar_attendees
language sql
stable
as $$
  select *
  from app.seminar_attendees
  where seminar_id = p_seminar_id;
$$;

create or replace function public.rest_insert_seminar(
  p_host_id uuid,
  p_title text,
  p_status app.seminar_status
)
returns app.seminars
language plpgsql
as $$
declare
  created_row app.seminars%rowtype;
begin
  insert into app.seminars (host_id, title, status)
  values (p_host_id, p_title, p_status)
  returning * into created_row;

  return created_row;
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
  updated_row app.seminars%rowtype;
begin
  update app.seminars
  set description = p_description
  where id = p_seminar_id
  returning * into updated_row;

  if not found then
    return jsonb_build_object('id', null, 'description', null);
  end if;

  return to_jsonb(updated_row);
end;
$$;
