-- 0007_rls_enable.sql
-- Enable RLS and add base service role policies for all app tables.

begin;

alter table app.profiles enable row level security;
drop policy if exists service_role_full_access on app.profiles;
create policy service_role_full_access on app.profiles
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.courses enable row level security;
drop policy if exists service_role_full_access on app.courses;
create policy service_role_full_access on app.courses
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.modules enable row level security;
drop policy if exists service_role_full_access on app.modules;
create policy service_role_full_access on app.modules
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.lessons enable row level security;
drop policy if exists service_role_full_access on app.lessons;
create policy service_role_full_access on app.lessons
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.media_objects enable row level security;
drop policy if exists service_role_full_access on app.media_objects;
create policy service_role_full_access on app.media_objects
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.lesson_media enable row level security;
drop policy if exists service_role_full_access on app.lesson_media;
create policy service_role_full_access on app.lesson_media
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.enrollments enable row level security;
drop policy if exists service_role_full_access on app.enrollments;
create policy service_role_full_access on app.enrollments
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.services enable row level security;
drop policy if exists service_role_full_access on app.services;
create policy service_role_full_access on app.services
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.sessions enable row level security;
drop policy if exists service_role_full_access on app.sessions;
create policy service_role_full_access on app.sessions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.session_slots enable row level security;
drop policy if exists service_role_full_access on app.session_slots;
create policy service_role_full_access on app.session_slots
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.orders enable row level security;
drop policy if exists service_role_full_access on app.orders;
create policy service_role_full_access on app.orders
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.payments enable row level security;
drop policy if exists service_role_full_access on app.payments;
create policy service_role_full_access on app.payments
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.memberships enable row level security;
drop policy if exists service_role_full_access on app.memberships;
create policy service_role_full_access on app.memberships
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.subscriptions enable row level security;
drop policy if exists service_role_full_access on app.subscriptions;
create policy service_role_full_access on app.subscriptions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.payment_events enable row level security;
drop policy if exists service_role_full_access on app.payment_events;
create policy service_role_full_access on app.payment_events
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.billing_logs enable row level security;
drop policy if exists service_role_full_access on app.billing_logs;
create policy service_role_full_access on app.billing_logs
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.course_entitlements enable row level security;
alter table app.course_entitlements force row level security;
drop policy if exists service_role_full_access on app.course_entitlements;
create policy service_role_full_access on app.course_entitlements
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.course_products enable row level security;
drop policy if exists service_role_full_access on app.course_products;
create policy service_role_full_access on app.course_products
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.entitlements enable row level security;
drop policy if exists service_role_full_access on app.entitlements;
create policy service_role_full_access on app.entitlements
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.purchases enable row level security;
drop policy if exists service_role_full_access on app.purchases;
create policy service_role_full_access on app.purchases
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.guest_claim_tokens enable row level security;
drop policy if exists service_role_full_access on app.guest_claim_tokens;
create policy service_role_full_access on app.guest_claim_tokens
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.stripe_customers enable row level security;
drop policy if exists service_role_full_access on app.stripe_customers;
create policy service_role_full_access on app.stripe_customers
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.refresh_tokens enable row level security;
drop policy if exists service_role_full_access on app.refresh_tokens;
create policy service_role_full_access on app.refresh_tokens
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.auth_events enable row level security;
drop policy if exists service_role_full_access on app.auth_events;
create policy service_role_full_access on app.auth_events
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.app_config enable row level security;
drop policy if exists service_role_full_access on app.app_config;
create policy service_role_full_access on app.app_config
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.activities enable row level security;
drop policy if exists service_role_full_access on app.activities;
create policy service_role_full_access on app.activities
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.seminars enable row level security;
drop policy if exists service_role_full_access on app.seminars;
create policy service_role_full_access on app.seminars
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.seminar_attendees enable row level security;
drop policy if exists service_role_full_access on app.seminar_attendees;
create policy service_role_full_access on app.seminar_attendees
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.seminar_sessions enable row level security;
drop policy if exists service_role_full_access on app.seminar_sessions;
create policy service_role_full_access on app.seminar_sessions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.seminar_recordings enable row level security;
drop policy if exists service_role_full_access on app.seminar_recordings;
create policy service_role_full_access on app.seminar_recordings
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.livekit_webhook_jobs enable row level security;
drop policy if exists service_role_full_access on app.livekit_webhook_jobs;
create policy service_role_full_access on app.livekit_webhook_jobs
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.teachers enable row level security;
drop policy if exists service_role_full_access on app.teachers;
create policy service_role_full_access on app.teachers
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.teacher_payout_methods enable row level security;
drop policy if exists service_role_full_access on app.teacher_payout_methods;
create policy service_role_full_access on app.teacher_payout_methods
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.teacher_permissions enable row level security;
drop policy if exists service_role_full_access on app.teacher_permissions;
create policy service_role_full_access on app.teacher_permissions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.teacher_directory enable row level security;
drop policy if exists service_role_full_access on app.teacher_directory;
create policy service_role_full_access on app.teacher_directory
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.teacher_approvals enable row level security;
drop policy if exists service_role_full_access on app.teacher_approvals;
create policy service_role_full_access on app.teacher_approvals
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.course_display_priorities enable row level security;
drop policy if exists service_role_full_access on app.course_display_priorities;
create policy service_role_full_access on app.course_display_priorities
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.teacher_profile_media enable row level security;
drop policy if exists service_role_full_access on app.teacher_profile_media;
create policy service_role_full_access on app.teacher_profile_media
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.course_bundles enable row level security;
drop policy if exists service_role_full_access on app.course_bundles;
create policy service_role_full_access on app.course_bundles
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.course_bundle_courses enable row level security;
drop policy if exists service_role_full_access on app.course_bundle_courses;
create policy service_role_full_access on app.course_bundle_courses
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.certificates enable row level security;
drop policy if exists service_role_full_access on app.certificates;
create policy service_role_full_access on app.certificates
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.course_quizzes enable row level security;
drop policy if exists service_role_full_access on app.course_quizzes;
create policy service_role_full_access on app.course_quizzes
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.quiz_questions enable row level security;
drop policy if exists service_role_full_access on app.quiz_questions;
create policy service_role_full_access on app.quiz_questions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.meditations enable row level security;
drop policy if exists service_role_full_access on app.meditations;
create policy service_role_full_access on app.meditations
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.tarot_requests enable row level security;
drop policy if exists service_role_full_access on app.tarot_requests;
create policy service_role_full_access on app.tarot_requests
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.reviews enable row level security;
drop policy if exists service_role_full_access on app.reviews;
create policy service_role_full_access on app.reviews
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.posts enable row level security;
drop policy if exists service_role_full_access on app.posts;
create policy service_role_full_access on app.posts
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.notifications enable row level security;
drop policy if exists service_role_full_access on app.notifications;
create policy service_role_full_access on app.notifications
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.follows enable row level security;
drop policy if exists service_role_full_access on app.follows;
create policy service_role_full_access on app.follows
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table app.messages enable row level security;
drop policy if exists service_role_full_access on app.messages;
create policy service_role_full_access on app.messages
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

commit;
