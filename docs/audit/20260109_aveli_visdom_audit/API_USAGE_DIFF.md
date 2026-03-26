# API Usage Diff (Current Frontend vs Mounted Backend)

## Sources
- Current frontend call sites:
  - `frontend/lib/api/api_paths.dart`
  - `frontend/lib/api/auth_repository.dart`
  - `frontend/lib/features/payments/data/payments_repository.dart`
  - `frontend/lib/features/payments/data/billing_api.dart`
  - `frontend/lib/features/payments/services/stripe_service.dart`
  - `frontend/lib/data/repositories/orders_repository.dart`
  - `frontend/lib/features/paywall/data/checkout_api.dart`
  - `frontend/lib/features/paywall/data/customer_portal_api.dart`
  - `frontend/lib/features/paywall/data/entitlements_api.dart`
  - `frontend/lib/features/media/data/media_repository.dart`
  - `frontend/lib/services/media_service.dart`
  - `frontend/lib/mvp/api_client.dart`
- Mounted backend runtime truth:
  - `backend/app/main.py`
  - `backend/app/routes/api_auth.py`
  - `backend/app/routes/api_checkout.py`
  - `backend/app/routes/api_me.py`
  - `backend/app/routes/api_orders.py`
  - `backend/app/routes/billing.py`
  - `backend/app/routes/media.py`
  - `backend/app/routes/api_media.py`
- Historical evidence only:
  - January 2026 audit snapshots under `docs/audit/20260109_aveli_visdom_audit/`

## Current Audited Frontend Paths
| Area | Current frontend paths | Evidence | Mounted backend match |
| --- | --- | --- | --- |
| Auth | `POST /auth/login`, `POST /auth/register`, `POST /auth/request-password-reset`, `POST /auth/reset-password`, `POST /auth/send-verification`, `GET /auth/validate-invite`, `GET /auth/verify-email`, `GET /auth/me`, `POST /api/me/onboarding/welcome-complete` | `frontend/lib/api/auth_repository.dart` | Yes |
| Payments | `GET /api/me/entitlements`, `GET /api/me/membership`, `POST /orders`, `GET /orders/{order_id}`, `GET /orders`, `POST /api/checkout/create`, `POST /api/me/claim-purchase`, `POST /api/billing/create-subscription`, `POST /api/billing/cancel-subscription` | `frontend/lib/features/payments/data/payments_repository.dart`, `frontend/lib/data/repositories/orders_repository.dart` | Yes |
| Paywall | `POST /api/checkout/create`, `POST /api/course-bundles/{bundle_id}/checkout-session`, `POST /api/billing/create-subscription`, `POST /api/billing/customer-portal`, `GET /api/me/entitlements` | `frontend/lib/features/paywall/data/checkout_api.dart`, `frontend/lib/features/paywall/data/customer_portal_api.dart`, `frontend/lib/features/paywall/data/entitlements_api.dart` | Yes |
| MVP client | `POST /auth/login`, `POST /auth/register`, `GET /auth/me`, `GET /courses/me`, `GET /services`, `GET /feed`, `POST /orders`, `GET /orders/{order_id}`, `POST /api/checkout/create`, `POST /sfu/token` | `frontend/lib/mvp/api_client.dart` | Yes |
| Media signing | `POST /api/media/sign` | `frontend/lib/features/media/data/media_repository.dart`, `frontend/lib/services/media_service.dart` | No |

## Active Frontend/Runtime Mismatches
| Method | Path | Current frontend call sites | Mounted backend evidence | Status |
| --- | --- | --- | --- | --- |
| POST | `/api/media/sign` | `frontend/lib/features/media/data/media_repository.dart`, `frontend/lib/services/media_service.dart` | Mounted runtime handler is `POST /media/sign` in `backend/app/routes/media.py` and is included by `backend/app/main.py` | active mismatch |

## Historical Stale Claims Removed From Active Set
These entries appeared in the January 2026 audit snapshot, but they do not match the current repo call sites and must not be treated as current frontend truth.

| Historical claim | Why stale now | Current repo evidence |
| --- | --- | --- |
| `DELETE /auth/me` | Old scan interpreted local logout storage clearing as an HTTP call | `frontend/lib/mvp/api_client.dart` only deletes local token state in `logout()` and uses `GET /auth/me` for profile fetch |
| `GET /payments/orders/{}` | Current payments flows use `/orders/{order_id}` | `frontend/lib/features/payments/data/payments_repository.dart`, `frontend/lib/data/repositories/orders_repository.dart` |
| `GET /payments/plans` | `plans()` no longer issues any API request | `frontend/lib/features/payments/data/payments_repository.dart` |
| `GET /payments/subscription` | Current membership fetch uses `GET /api/me/membership` | `frontend/lib/features/payments/data/payments_repository.dart` |
| `PATCH /studio/quizzes/{}/questions/{}` | Current studio question update uses `PUT` | `frontend/lib/features/studio/data/studio_repository.dart` |
| `POST /api/billing/change-plan` | Current plan changes are handled locally as unsupported and delegated to customer portal | `frontend/lib/features/payments/data/billing_api.dart` |
| `POST /api/billing/create-subscription-sheet` | Current subscription start uses `POST /api/billing/create-subscription` | `frontend/lib/features/payments/data/billing_api.dart`, `frontend/lib/features/paywall/data/checkout_api.dart` |
| `POST /checkout/session` | Current checkout creation uses `POST /api/checkout/create` | `frontend/lib/features/payments/services/stripe_service.dart`, `frontend/lib/data/repositories/orders_repository.dart`, `frontend/lib/features/paywall/data/checkout_api.dart`, `frontend/lib/mvp/api_client.dart` |
| `POST /media/presign` | Current Flutter media signer uses `POST /api/media/sign`; the generic landing helper no longer hardcodes `/media/presign`; lesson uploads use lesson-scoped studio routes | `frontend/lib/services/media_service.dart`, `frontend/landing/lib/media.ts`, `frontend/landing/lib/studioUploads.ts` |
| `POST /payments/coupons/preview` | Current code throws locally and does not call an endpoint | `frontend/lib/features/payments/data/payments_repository.dart` |
| `POST /payments/coupons/redeem` | Current code throws locally and does not call an endpoint | `frontend/lib/features/payments/data/payments_repository.dart` |
| `POST /payments/create-subscription` | Current subscription start uses `POST /api/billing/create-subscription` | `frontend/lib/features/payments/data/payments_repository.dart`, `frontend/lib/features/payments/data/billing_api.dart` |
| `POST /payments/orders/course` | Current course order creation uses `POST /orders` | `frontend/lib/features/payments/data/payments_repository.dart` |
| `POST /payments/orders/service` | Current service order creation uses `POST /orders` | `frontend/lib/features/payments/data/payments_repository.dart`, `frontend/lib/data/repositories/orders_repository.dart`, `frontend/lib/mvp/api_client.dart` |
| `POST /payments/purchases/claim` | Current claim flow uses `POST /api/me/claim-purchase` | `frontend/lib/features/payments/data/payments_repository.dart` |
| `POST /payments/stripe/create-session` | Current checkout creation uses `POST /api/checkout/create` | `frontend/lib/data/repositories/orders_repository.dart`, `frontend/lib/mvp/api_client.dart` |
| `POST /auth/forgot-password` | Current password reset request uses `POST /auth/request-password-reset` | `frontend/lib/api/auth_repository.dart` |

## Mounted Backend Notes
- `backend/app/routes/auth.py` and `backend/app/routes/api_payments.py` still exist in the repo but are not mounted by `backend/app/main.py`.
- `POST /auth/forgot-password` still exists as a mounted legacy alias in `backend/app/routes/api_auth.py`, but it is no longer a current frontend dependency.
- `POST /payments/create-checkout-session` still exists only in unmounted `backend/app/routes/api_payments.py`; it is no longer a current frontend dependency.
- Hidden aliases remain historical/runtime notes only:
  - `GET /courses/` as alias of `/courses`
  - `GET /courses/config/free-course-limit` as alias of `/courses/config/free-limit`
