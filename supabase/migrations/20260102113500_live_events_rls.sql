-- 20260102113500_live_events_rls.sql
-- Enable RLS and policies for live events.

begin;

do $do$
begin
  if to_regclass('app.live_events') is null then
    raise notice 'Skipping live_events RLS: missing table app.live_events';
  else
    alter table app.live_events enable row level security;

    -- Live events -------------------------------------------------------------
    drop policy if exists live_events_service on app.live_events;
    create policy live_events_service on app.live_events
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

    drop policy if exists live_events_access on app.live_events;
    create policy live_events_access on app.live_events
      for select to authenticated
      using (
        teacher_id = auth.uid()
        or app.is_admin(auth.uid())
        or (
          access_type = 'membership'
          and exists (
            select 1 from app.memberships m
            where m.user_id = auth.uid()
              and m.status = 'active'
              and (m.end_date is null or m.end_date > now())
          )
        )
        or (
          access_type = 'course'
          and exists (
            select 1 from app.enrollments e
            where e.user_id = auth.uid()
              and e.course_id = course_id
          )
        )
      );

    drop policy if exists live_events_host_rw on app.live_events;
    create policy live_events_host_rw on app.live_events
      for all to authenticated
      using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
      with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));
  end if;
end
$do$;

do $do$
begin
  if to_regclass('app.live_event_registrations') is null then
    raise notice 'Skipping live_event_registrations RLS: missing table app.live_event_registrations';
  elsif to_regclass('app.live_events') is null then
    raise notice 'Skipping live_event_registrations RLS: missing table app.live_events';
  else
    alter table app.live_event_registrations enable row level security;

    -- Live event registrations ------------------------------------------------
    drop policy if exists live_event_registrations_service on app.live_event_registrations;
    create policy live_event_registrations_service on app.live_event_registrations
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

    drop policy if exists live_event_registrations_read on app.live_event_registrations;
    create policy live_event_registrations_read on app.live_event_registrations
      for select to authenticated
      using (
        user_id = auth.uid()
        or app.is_admin(auth.uid())
        or exists (
          select 1 from app.live_events e
          where e.id = event_id
            and e.teacher_id = auth.uid()
        )
      );

    drop policy if exists live_event_registrations_write on app.live_event_registrations;
    create policy live_event_registrations_write on app.live_event_registrations
      for all to authenticated
      using (
        user_id = auth.uid()
        or app.is_admin(auth.uid())
        or exists (
          select 1 from app.live_events e
          where e.id = event_id
            and e.teacher_id = auth.uid()
        )
      )
      with check (
        app.is_admin(auth.uid())
        or exists (
          select 1 from app.live_events e
          where e.id = event_id
            and (
              e.teacher_id = auth.uid()
              or (
                user_id = auth.uid()
                and (
                  (e.access_type = 'membership' and exists (
                    select 1 from app.memberships m
                    where m.user_id = auth.uid()
                      and m.status = 'active'
                      and (m.end_date is null or m.end_date > now())
                  ))
                  or (e.access_type = 'course' and exists (
                    select 1 from app.enrollments en
                    where en.user_id = auth.uid()
                      and en.course_id = e.course_id
                  ))
                )
              )
            )
        )
      );
  end if;
end
$do$;

commit;
