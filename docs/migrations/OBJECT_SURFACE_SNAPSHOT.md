# Object Surface Snapshot (from local migrations)

## Tables (app.*)
- app.activities
- app.app_config
- app.auth_events
- app.billing_logs
- app.certificates
- app.course_bundle_courses
- app.course_bundles
- app.course_display_priorities
- app.course_entitlements
- app.course_products
- app.course_quizzes
- app.courses
- app.entitlements
- app.enrollments
- app.follows
- app.guest_claim_tokens
- app.lesson_media
- app.lessons
- app.livekit_webhook_jobs
- app.media_objects
- app.meditations
- app.memberships
- app.messages
- app.modules
- app.notifications
- app.orders
- app.payment_events
- app.payments
- app.posts
- app.profiles
- app.purchases
- app.quiz_questions
- app.refresh_tokens
- app.reviews
- app.seminar_attendees
- app.seminar_recordings
- app.seminar_sessions
- app.seminars
- app.services
- app.session_slots
- app.sessions
- app.stripe_customers
- app.tarot_requests
- app.teacher_approvals
- app.teacher_directory
- app.teacher_permissions
- app.teacher_profile_media
- app.teacher_payout_methods
- app.teachers

## Views (app.*)
- app.activities_feed
- app.service_orders
- app.service_reviews

## Functions (app.*)
- app.set_updated_at()
- app.is_admin(uuid)
- app.is_seminar_host(uuid, uuid)
- app.is_seminar_host(uuid)
- app.is_seminar_attendee(uuid, uuid)
- app.is_seminar_attendee(uuid)
- app.can_access_seminar(uuid, uuid)
- app.can_access_seminar(uuid)
- app.touch_course_display_priorities()
- app.touch_teacher_profile_media()
- app.touch_course_entitlements()
- app.touch_livekit_webhook_jobs() (guarded by 010_fix_livekit_job_id.sql; not created on a fresh replay)

## Triggers
- trg_courses_touch on app.courses
- trg_modules_touch on app.modules
- trg_lessons_touch on app.lessons
- trg_services_touch on app.services
- trg_orders_touch on app.orders
- trg_payments_touch on app.payments
- trg_seminars_touch on app.seminars
- trg_profiles_touch on app.profiles
- trg_teacher_approvals_touch on app.teacher_approvals
- trg_teacher_payout_methods_touch on app.teacher_payout_methods
- trg_course_display_priorities_touch on app.course_display_priorities
- trg_teacher_profile_media_touch on app.teacher_profile_media
- trg_teachers_touch on app.teachers
- trg_sessions_touch on app.sessions
- trg_session_slots_touch on app.session_slots
- trg_course_entitlements_touch on app.course_entitlements
- trg_livekit_webhook_jobs_touch on app.livekit_webhook_jobs
- trg_seminar_sessions_touch on app.seminar_sessions
- trg_seminar_recordings_touch on app.seminar_recordings
- trg_course_products_updated on app.course_products

## Enums (app.*)
- app.profile_role
- app.user_role
- app.order_status
- app.payment_status
- app.enrollment_source
- app.service_status
- app.seminar_status
- app.activity_kind
- app.review_visibility
- app.session_visibility
- app.order_type
- app.seminar_session_status

## Storage buckets
- public-media (public)
- course-media (private)
- lesson-media (private)

## Backend-Expected Objects (backend/app/** scan)
Referenced by backend:
- app.activities, app.activities_feed, app.app_config, app.auth_events, app.billing_logs, app.certificates, app.course_bundle_courses, app.course_bundles, app.course_display_priorities, app.course_entitlements, app.course_quizzes, app.courses, app.enrollments, app.follows, app.guest_claim_tokens, app.lesson_media, app.lessons, app.livekit_webhook_jobs, app.media_objects, app.meditations, app.memberships, app.messages, app.modules, app.notifications, app.orders, app.payment_events, app.payments, app.posts, app.profiles, app.purchases, app.quiz_questions, app.refresh_tokens, app.reviews, app.seminar_attendees, app.seminar_recordings, app.seminar_sessions, app.seminars, app.services, app.session_slots, app.sessions, app.stripe_customers, app.tarot_requests, app.teacher_approvals, app.teacher_directory, app.teacher_permissions, app.teacher_profile_media, app.teachers, app.service_status (enum), app.grade_quiz_and_issue_certificate (function), app.subscriptions (table).

Missing in migrations:
- app.subscriptions (table referenced in backend models).
- app.grade_quiz_and_issue_certificate (function referenced in backend course logic).

Schema mismatches vs backend expectations:
- app.livekit_webhook_jobs is created with job_id/attempts/error/last_attempted_at in 20251215090000, but backend queries expect id/attempt/last_error/last_attempt_at/next_run_at. Normalization migrations run before the table is created and are skipped on fresh replay.

Other missing objects referenced by migrations:
- app.live_events and app.live_event_registrations are referenced by 20260102113500_live_events_rls.sql but are not created in local migrations.
