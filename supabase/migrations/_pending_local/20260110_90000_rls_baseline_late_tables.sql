-- 20260110_90000_rls_baseline_late_tables.sql
-- Baseline RLS + service role policy for late-created tables.

begin;

do $$
declare
  table_list text[] := array[
    'seminar_sessions','seminar_recordings','livekit_webhook_jobs'
  ];
  tbl text;
begin
  foreach tbl in array table_list loop
    if to_regclass(format('app.%I', tbl)) is null then
      raise notice 'Skipping missing table app.%', tbl;
      continue;
    end if;

    execute format('alter table app.%I enable row level security', tbl);
    execute format('drop policy if exists service_role_full_access on app.%I', tbl);
    execute format(
      'create policy service_role_full_access on app.%I for all using (auth.role() = ''service_role'') with check (auth.role() = ''service_role'')',
      tbl
    );
  end loop;
end$$;

commit;
