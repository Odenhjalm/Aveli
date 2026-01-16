-- 20260110_90000_rls_baseline_late_tables.sql
-- RLS policies for tables created after 008_rls_app_policies.sql.

begin;

do $do$
begin
  if to_regclass('app.seminar_sessions') is null then
    raise notice 'Skipping missing table app.seminar_sessions';
  else
    alter table app.seminar_sessions enable row level security;

    drop policy if exists seminar_sessions_service on app.seminar_sessions;
    create policy seminar_sessions_service on app.seminar_sessions
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

    drop policy if exists seminar_sessions_host on app.seminar_sessions;
    create policy seminar_sessions_host on app.seminar_sessions
      for all to authenticated
      using (
        exists (
          select 1 from app.seminars s
          where s.id = seminar_id
            and (s.host_id = auth.uid() or app.is_admin(auth.uid()))
        )
      )
      with check (
        exists (
          select 1 from app.seminars s
          where s.id = seminar_id
            and (s.host_id = auth.uid() or app.is_admin(auth.uid()))
        )
      );
  end if;
end
$do$;

do $do$
begin
  if to_regclass('app.seminar_recordings') is null then
    raise notice 'Skipping missing table app.seminar_recordings';
  else
    alter table app.seminar_recordings enable row level security;

    drop policy if exists seminar_recordings_service on app.seminar_recordings;
    create policy seminar_recordings_service on app.seminar_recordings
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

    drop policy if exists seminar_recordings_read on app.seminar_recordings;
    create policy seminar_recordings_read on app.seminar_recordings
      for select to authenticated
      using (
        exists (
          select 1 from app.seminars s
          where s.id = seminar_id
            and (
              s.host_id = auth.uid()
              or app.is_admin(auth.uid())
              or s.status in ('live','ended')
            )
        )
      );
  end if;
end
$do$;

do $do$
begin
  if to_regclass('app.livekit_webhook_jobs') is null then
    raise notice 'Skipping missing table app.livekit_webhook_jobs';
  else
    alter table app.livekit_webhook_jobs enable row level security;

    drop policy if exists livekit_jobs_service on app.livekit_webhook_jobs;
    create policy livekit_jobs_service on app.livekit_webhook_jobs
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
  end if;
end
$do$;

commit;
