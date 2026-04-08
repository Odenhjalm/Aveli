-- 007_rls_policies.sql
-- Enable RLS on all app tables with a strict service role policy.

begin;

do $$
declare
  table_list text[] := array[
    'profiles','courses','modules','lessons','media_objects','lesson_media',
    'enrollments','services','orders','payments','teacher_payout_methods',
    'seminars','seminar_attendees','seminar_sessions','seminar_recordings',
    'activities','refresh_tokens','auth_events','posts','notifications','follows',
    'app_config','messages','stripe_customers','teacher_permissions','teacher_directory',
    'teacher_approvals','certificates','course_quizzes','quiz_questions','meditations',
    'tarot_requests','reviews','course_display_priorities','teacher_profile_media',
    'teachers','sessions','session_slots','memberships','payment_events','billing_logs',
    'livekit_webhook_jobs'
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
