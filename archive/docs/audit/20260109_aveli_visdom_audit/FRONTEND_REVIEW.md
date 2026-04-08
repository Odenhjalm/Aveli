# Frontend Review (Current Contract Snapshot)

## Flutter architecture
- Feature modules remain centered in `frontend/lib/features/`.
- Primary API access is still split between:
  - Dio-based `frontend/lib/api/api_client.dart`
  - `http.Client` usage in `frontend/lib/features/paywall/data/*`
  - MVP-specific Dio wrapper in `frontend/lib/mvp/api_client.dart`
- Route constants are centralized in `frontend/lib/api/api_paths.dart`.

## Auth handling
- Current auth API usage is:
  - `POST /auth/login`
  - `POST /auth/register`
  - `POST /auth/request-password-reset`
  - `POST /auth/reset-password`
  - `POST /auth/send-verification`
  - `GET /auth/validate-invite`
  - `GET /auth/verify-email`
  - `GET /auth/me`
  - `POST /api/me/onboarding/welcome-complete`
- These paths match mounted backend handlers in `backend/app/routes/api_auth.py`, `backend/app/routes/email_verification.py`, and `backend/app/routes/api_me.py`.
- Older audit claims about frontend dependence on `POST /auth/forgot-password` are historical only. The current frontend uses `POST /auth/request-password-reset`.

## Payments + subscriptions
- Current membership and order flows use canonical routes:
  - `GET /api/me/entitlements`
  - `GET /api/me/membership`
  - `POST /orders`
  - `GET /orders/{order_id}`
  - `GET /orders`
  - `POST /api/checkout/create`
  - `POST /api/billing/create-subscription`
  - `POST /api/billing/cancel-subscription`
  - `POST /api/billing/customer-portal`
  - `POST /api/course-bundles/{bundle_id}/checkout-session`
  - `POST /api/me/claim-purchase`
- Current Flutter payment code no longer issues the old `/payments/*` or `/checkout/session` calls recorded in the January 2026 snapshot.
- Legacy-looking methods that still exist in code but no longer call backend endpoints:
  - `plans()` returns a local empty list
  - coupon preview/redeem methods throw locally
  - `changePlan()` throws locally and points users toward the customer portal

## Media and assets
- Current signed playback/media resolution callers use `POST /api/media/sign` from:
  - `frontend/lib/features/media/data/media_repository.dart`
  - `frontend/lib/services/media_service.dart`
- Mounted backend still exposes `POST /media/sign` in `backend/app/routes/media.py`, so this is the active frontend/runtime mismatch carried into Phase 1.
- Teacher lesson uploads on the landing/studio side use lesson-scoped studio endpoints:
  - `POST /studio/lessons/{lesson_id}/media/presign`
  - `POST /studio/lessons/{lesson_id}/media/complete`
- `frontend/landing/lib/media.ts` is now a route-agnostic upload helper and does not prove a direct `/media/presign` frontend call by itself.

## Landing + paywall
- Checkout and membership paths in landing/paywall code already align with mounted backend routes under `/api/checkout/*`, `/api/billing/*`, `/api/me/*`, and `/api/course-bundles/*`.
- Customer portal creation uses `POST /api/billing/customer-portal`.

## Current gaps and risks
- Active mismatch:
  - `POST /api/media/sign` in current frontend vs mounted `POST /media/sign` in runtime.
- Historical drift that should not be treated as current frontend truth:
  - `/payments/*`
  - `/checkout/session`
  - `/auth/forgot-password`
  - `/media/presign`
  - old PATCH quiz-update claim
- Legacy backend routes still present but not current frontend dependencies:
  - unmounted `backend/app/routes/api_payments.py`
  - unmounted `backend/app/routes/auth.py`
