# E2E Flows (Phase 3)

## Diagram (high level)
```mermaid
flowchart TB
  subgraph Auth
    A1[Flutter Login/Signup] --> A2[/auth/login, /auth/register]
    A2 --> A3[(auth.users, app.profiles, app.refresh_tokens)]
  end
  subgraph Membership
    M1[Flutter Paywall / Next Checkout Return] --> M2[/api/checkout/create or /api/billing/create-subscription]
    M2 --> M3[Stripe Checkout]
    M3 --> M4[/webhooks/stripe or /api/billing/webhook]
    M4 --> M5[(app.orders, app.memberships, app.billing_logs)]
  end
  subgraph Courses
    C1[Course Catalog + Lesson UI] --> C2[/courses/*, /api/courses/{slug}/pricing]
    C2 --> C3[(app.courses, app.modules, app.lessons, app.enrollments)]
  end
  subgraph Community
    F1[Feed + Messages] --> F2[/feed, /community/*]
    F2 --> F3[(app.activities_feed, app.posts, app.messages, app.notifications)]
  end
  subgraph Seminars
    S1[Seminar UI] --> S2[/seminars/*, /studio/seminars/*]
    S2 --> S3[/sfu/token]
    S3 --> S4[LiveKit]
    S2 --> S5[(app.seminars, app.seminar_sessions, app.seminar_attendees)]
  end
  subgraph Teacher
    T1[Studio + Connect] --> T2[/studio/*, /connect/*]
    T2 --> T3[Stripe Connect]
    T2 --> T4[(app.teachers, app.courses, app.lessons)]
  end
```

## Flow 1: Sign-up / Login / Profile
- Frontend screens: login/signup/forgot/reset flows in Flutter auth UI.
  - `frontend/lib/features/auth/presentation/login_page.dart`, `frontend/lib/features/auth/presentation/signup_page.dart`, `frontend/lib/features/auth/presentation/forgot_password_page.dart`, `frontend/lib/features/auth/presentation/new_password_page.dart`
- Frontend auth state + token handling:
  - `frontend/lib/core/auth/auth_controller.dart`, `frontend/lib/api/auth_repository.dart`, `frontend/lib/core/auth/token_storage.dart`, `frontend/lib/api/api_client.dart`
- Backend endpoints:
  - `backend/app/routes/api_auth.py` (`/auth/register`, `/auth/login`, `/auth/refresh`, `/auth/me`)
- DB tables touched (from API catalog):
  - `auth.users`, `app.profiles`, `app.refresh_tokens`, `app.auth_events`, `app.teacher_approvals`, `app.teacher_permissions` in `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json`
- Gaps / risks:
  - Password reset endpoints (`/auth/forgot-password`, `/auth/reset-password`) live in unmounted router `backend/app/routes/auth.py` and are not included in `backend/app/main.py`.
  - OAuth path `/auth/oauth` is disabled (410) in `backend/app/routes/api_auth.py`.
  - Flutter deep-link OAuth uses Supabase session parsing (`frontend/lib/core/deeplinks/deep_link_service.dart`), but backend JWT validation only accepts its own token format in `backend/app/auth.py`.

## Flow 2: Membership / Subscription
- Frontend (Flutter):
  - Checkout + membership UI: `frontend/lib/features/paywall/`, `frontend/lib/features/payments/`, `frontend/lib/features/profile/presentation/my_subscription_page.dart`
  - Checkout API calls via `frontend/lib/features/paywall/data/checkout_api.dart` and `frontend/lib/features/paywall/data/customer_portal_api.dart`
- Frontend (Landing/Next):
  - Checkout return polling `/api/billing/session-status` and `/api/me/membership` in `frontend/landing/pages/checkout/return.tsx`
- Backend endpoints:
  - `/api/checkout/create` in `backend/app/routes/api_checkout.py`
  - `/api/billing/*` in `backend/app/routes/billing.py`
  - Stripe webhook handlers: `backend/app/routes/stripe_webhooks.py` and `backend/app/routes/stripe_webhook.py`
- DB tables touched (from API catalog):
  - `app.orders`, `app.memberships`, `app.billing_logs`, `app.stripe_customers`
- Integrations:
  - Stripe Checkout + Billing portal in `backend/app/services/subscription_service.py` and `backend/app/services/billing_portal_service.py`
- Gaps / risks:
  - Flutter uses `/payments/*` endpoints that do not exist in mounted backend routes (see `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`).
  - Flutter `BillingApi` expects `/api/billing/create-subscription-sheet` and `/api/billing/change-plan` which are not implemented in backend.

## Flow 3: Course purchase / access / lessons / quizzes
- Frontend screens: catalog, course page, lesson page, quiz UI.
  - `frontend/lib/features/courses/presentation/course_catalog_page.dart`, `frontend/lib/features/courses/presentation/course_page.dart`, `frontend/lib/features/courses/presentation/lesson_page.dart`, `frontend/lib/features/courses/presentation/quiz_take_page.dart`
- Frontend data layer:
  - `frontend/lib/features/courses/data/courses_repository.dart`
  - Pricing + checkout: `frontend/lib/features/paywall/data/course_pricing_api.dart`, `frontend/lib/features/paywall/data/checkout_api.dart`
- Backend endpoints:
  - `/courses/*` and `/api/courses/{slug}/pricing` in `backend/app/routes/courses.py`
  - Course checkout: `/api/checkout/create` in `backend/app/routes/api_checkout.py`
- DB tables touched (from API catalog):
  - `app.courses`, `app.modules`, `app.lessons`, `app.lesson_media`, `app.enrollments`, `app.course_quizzes`, `app.quiz_questions`, `app.certificates`, `app.orders`
- Integrations:
  - Stripe used to validate course prices in `backend/app/services/checkout_service.py` and `backend/app/services/courses_service.py`.
- Gaps / risks:
  - Entitlement gating depends on `app.course_entitlements` (RLS missing, see `docs/audit/20260109_aveli_visdom_audit/RLS_MATRIX.md`).

## Flow 4: Media upload / stream
- Frontend:
  - Teacher media upload in studio uses `/studio/lessons/{id}/media/presign` + `/media/complete` from `frontend/landing/lib/studioUploads.ts` and Flutter studio features.
  - General media presign/stream uses `/media/presign` in `frontend/lib/services/media_service.dart` and `frontend/landing/lib/media.ts`.
- Backend:
  - Signed media: `/media/sign`, `/media/stream/{token}` in `backend/app/routes/media.py`
  - Direct uploads: `/api/upload/*` in `backend/app/routes/upload.py`
  - Lesson media upload for teachers: `/studio/lessons/{lesson_id}/media/*` in `backend/app/routes/studio.py`
- Storage:
  - Local media root `settings.media_root` in `backend/app/config.py`
  - Buckets defined in `supabase/migrations/018_storage_buckets.sql` and `supabase/migrations/20260102113600_storage_public_media.sql`
- Gaps / risks:
  - `/media/presign` does not exist in backend; current backend expects `/media/sign` or studio-specific presign endpoints.

## Flow 5: Community / Feed / Messages
- Frontend:
  - Feed + community UI in `frontend/lib/features/community/` and messages in `frontend/lib/features/messages/`.
  - Data layer: `frontend/lib/data/repositories/feed_repository.dart`, `frontend/lib/features/community/data/messages_repository.dart`
- Backend:
  - `/feed` in `backend/app/routes/api_feed.py`
  - `/community/*` in `backend/app/routes/community.py`
- DB tables touched (from API catalog):
  - `app.activities_feed`, `app.posts`, `app.follows`, `app.messages`, `app.notifications`, `app.reviews`, `app.tarot_requests`
- Gaps / risks:
  - Feed RLS policy is permissive (`activities_read` uses `using (true)` in `supabase/migrations/008_rls_app_policies.sql`).

## Flow 6: Events / Seminars (LiveKit)
- Frontend:
  - Seminar discovery + join UI in `frontend/lib/features/seminars/`.
  - LiveKit token flow in `frontend/lib/features/home/application/livekit_controller.dart` and `frontend/lib/data/repositories/sfu_repository.dart`.
- Backend:
  - `/seminars/*` and `/studio/seminars/*` in `backend/app/routes/seminars.py` and `backend/app/routes/studio.py`.
  - LiveKit token + webhook in `backend/app/routes/api_sfu.py` and `backend/app/routes/livekit_webhooks.py`.
- DB tables touched (from API catalog):
  - `app.seminars`, `app.seminar_sessions`, `app.seminar_attendees`, `app.seminar_recordings`
- Integrations:
  - LiveKit token generation and webhook worker in `backend/app/services/livekit_tokens.py` and `backend/app/services/livekit_events.py`.
- Gaps / risks:
  - LiveKit requires API keys in `backend/app/config.py` and will 503 if missing.

## Flow 7: Teacher onboarding / Stripe Connect
- Frontend:
  - Stripe Connect flow in `frontend/lib/features/studio/data/connect_repository.dart` and teacher studio UI in `frontend/lib/features/studio/presentation/teacher_home_page.dart`.
- Backend:
  - `/connect/onboarding` + `/connect/status` in `backend/app/routes/connect.py`.
  - Stripe Connect service in `backend/app/services/connect_service.py`.
- DB tables touched (from API catalog):
  - `app.teachers`
- Gaps / risks:
  - Missing Stripe Connect configuration (`stripe_connect_client_id`, `stripe_connect_refresh_url`, `stripe_connect_return_url`) will hard-fail onboarding.
