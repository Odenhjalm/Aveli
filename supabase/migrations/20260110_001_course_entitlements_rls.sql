-- 20260110_001_course_entitlements_rls.sql
-- Enable RLS + policies for app.course_entitlements.

begin;

alter table app.course_entitlements enable row level security;
alter table app.course_entitlements force row level security;

drop policy if exists service_role_full_access on app.course_entitlements;
create policy service_role_full_access on app.course_entitlements
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists course_entitlements_self_read on app.course_entitlements;
create policy course_entitlements_self_read on app.course_entitlements
  for select to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()));

commit;
