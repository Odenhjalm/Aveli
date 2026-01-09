# Frontend Review (Flutter + Next)

## Flutter architecture
- Feature modules (routing + UI): `frontend/lib/features/` (auth, community, courses, messages, payments, paywall, profile, seminars, studio, teacher).
- State management: Riverpod providers and StateNotifiers throughout (example: `frontend/lib/core/auth/auth_controller.dart`).
- Navigation + access control: go_router with access levels and redirect logic in `frontend/lib/core/routing/app_router.dart` and `frontend/lib/core/routing/route_manifest.dart`.
- API clients:
  - Dio-based `ApiClient` with auth header injection, refresh-on-401, and 403 notifications in `frontend/lib/api/api_client.dart`.
  - Token storage in `frontend/lib/core/auth/token_storage.dart` (flutter_secure_storage).
  - Additional `http.Client` usage for paywall and checkout flows in `frontend/lib/features/paywall/data/*`.
- Error handling: centralized mapping in `frontend/lib/core/errors/app_failure.dart`, surfaced in UI via snackbars (various feature UIs).

## Auth handling
- Login/register/refresh/profile calls in `frontend/lib/api/auth_repository.dart` and `frontend/lib/core/auth/auth_controller.dart`.
- Auth event handling (session expired, forbidden) emitted from `frontend/lib/core/auth/auth_http_observer.dart` and consumed in `frontend/lib/main.dart` to redirect or show snackbars.
- OAuth/deep link handling uses Supabase session parsing in `frontend/lib/core/deeplinks/deep_link_service.dart`, but backend validation only accepts its own JWTs (`backend/app/auth.py`).

## Environment configuration
- Required runtime keys enforced in `frontend/lib/main.dart` and resolved in `frontend/lib/core/env/env_resolver.dart` (API base URL, Supabase URL/key, Stripe publishable key, OAuth redirect URLs).
- Non-web builds can optionally load dotenv via `DOTENV_FILE` in `frontend/lib/main.dart` (defaults to no file if not provided).

## Payments + subscriptions
- Membership and checkout flows:
  - `/api/checkout/create` and `/api/course-bundles/{id}/checkout-session` via `frontend/lib/features/paywall/data/checkout_api.dart`.
  - Billing portal via `frontend/lib/features/paywall/data/customer_portal_api.dart`.
  - Membership fetch via `frontend/lib/features/payments/data/payments_repository.dart` (uses `/api/me/membership`).
- Legacy endpoints still referenced:
  - `/payments/*` endpoints in `frontend/lib/features/payments/data/payments_repository.dart` and `frontend/lib/data/repositories/orders_repository.dart`.
  - `/checkout/session` in `frontend/lib/features/payments/services/stripe_service.dart`.
- Backend provides `/api/billing/*` and `/api/checkout/*`, but not the `/payments/*` or `/checkout/session` paths. See `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`.

## Media and assets
- Media presign + upload in Flutter uses `/media/presign` in `frontend/lib/services/media_service.dart`.
- Teacher lesson media presign/complete from Next landing uses `/studio/lessons/{id}/media/presign` and `/studio/lessons/{id}/media/complete` in `frontend/landing/lib/studioUploads.ts`.
- Protected images attach Authorization header in `frontend/lib/shared/widgets/app_network_image.dart`.
- Backend exposes `/media/sign` and `/media/stream/{token}` (not `/media/presign`), plus `/api/upload/*` and `/studio/lessons/{id}/media/*` endpoints.

## Observability and analytics (frontend)
- Firebase Analytics + Crashlytics wrappers in `frontend/lib/domain/services/analytics_service.dart`.
- Firebase config is a placeholder in `frontend/lib/firebase_options.dart` and there is no `Firebase.initializeApp` usage in code.
- Landing site uses Sentry for Next.js in `frontend/landing/sentry.client.config.ts` and `frontend/landing/sentry.server.config.ts`.

## Landing (Next.js)
- Checkout status polling uses `NEXT_PUBLIC_API_BASE_URL` to call `/api/billing/session-status` and `/api/me/membership` in `frontend/landing/pages/checkout/return.tsx`.
- Sentry enabled via env (`NEXT_PUBLIC_SENTRY_DSN` or `SENTRY_DSN`).
- Tests in `frontend/landing/tests/` use Vitest; lint via Next ESLint config.

## Gaps and risks
- API mismatches and missing endpoints are concentrated in `/payments/*`, `/checkout/session`, `/media/presign`, and `/api/billing/change-plan` (see `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`).
- Flutter analyze reports missing `package:aveli/*` imports and undefined symbols in multiple files (`lib/features/payments/services/stripe_service.dart`, `lib/features/seminars/presentation/seminar_booking_page.dart`, `lib/features/studio/*`, `lib/services/media_service.dart`).
- OAuth via Supabase is not bridged to backend JWT auth; if OAuth is required for launch, the token exchange flow is missing.
