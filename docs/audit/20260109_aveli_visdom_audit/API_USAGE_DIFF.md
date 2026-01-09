# API Usage Diff (Frontend vs Backend)

## Sources
- Backend catalog: `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json` (FastAPI routes in `backend/app/routes/*`).
- Frontend scan: Flutter `frontend/lib/**` + Next `frontend/landing/**` (static string scan with manual additions for `http.Client` usage).
- Router mounts: `backend/app/main.py` (used to flag unmounted routers).

## Frontend endpoints missing on backend
| Method | Path | Frontend call sites |
| --- | --- | --- |
| DELETE | `/auth/me` | `frontend/lib/mvp/api_client.dart:70` |
| GET | `/payments/orders/{}` | `frontend/lib/features/payments/data/payments_repository.dart:187` |
| GET | `/payments/plans` | `frontend/lib/features/payments/data/payments_repository.dart:39` |
| GET | `/payments/subscription` | `frontend/lib/features/payments/data/payments_repository.dart:53` |
| PATCH | `/studio/quizzes/{}/questions/{}` | `frontend/lib/features/studio/data/studio_repository.dart:386` |
| POST | `/api/billing/change-plan` | `frontend/lib/features/payments/data/billing_api.dart:61` |
| POST | `/api/billing/create-subscription-sheet` | `frontend/lib/features/payments/data/billing_api.dart:27` |
| POST | `/checkout/session` | `frontend/lib/features/payments/services/stripe_service.dart:26` |
| POST | `/media/presign` | `frontend/landing/lib/media.ts:30`, `frontend/lib/services/media_service.dart:54`, `frontend/lib/services/media_service.dart:119` |
| POST | `/payments/coupons/preview` | `frontend/lib/features/payments/data/payments_repository.dart:104` |
| POST | `/payments/coupons/redeem` | `frontend/lib/features/payments/data/payments_repository.dart:126` |
| POST | `/payments/create-subscription` | `frontend/lib/features/payments/data/payments_repository.dart:258` |
| POST | `/payments/orders/course` | `frontend/lib/features/payments/data/payments_repository.dart:148` |
| POST | `/payments/orders/service` | `frontend/lib/features/payments/data/payments_repository.dart:170` |
| POST | `/payments/purchases/claim` | `frontend/lib/features/payments/data/payments_repository.dart:243` |
| POST | `/payments/stripe/create-session` | `frontend/lib/data/repositories/orders_repository.dart:39`, `frontend/lib/mvp/api_client.dart:122` |

## Backend endpoints not referenced by frontend scan
| Method | Path | Backend source |
| --- | --- | --- |
| DELETE | `/studio/sessions/{}` | `backend/app/routes/studio_sessions.py:52` |
| GET | `/admin/teacher-requests` | `backend/app/routes/admin.py:48` |
| GET | `/api/files/{}` | `backend/app/routes/upload.py:358` |
| GET | `/auth/avatar/{}` | `backend/app/routes/api_auth.py:337` |
| GET | `/community/certificates/verified-count` | `backend/app/routes/community.py:194` |
| GET | `/community/meditations/audio` | `backend/app/routes/community.py:167` |
| GET | `/community/teachers/{}/certificates` | `backend/app/routes/community.py:127` |
| GET | `/config/free-course-limit` | `backend/app/routes/courses.py:201` |
| GET | `/courses/config/free-limit` | `backend/app/routes/courses.py:187` |
| GET | `/courses/{}/enrollment` | `backend/app/routes/courses.py:127` |
| GET | `/courses/{}/latest-order` | `backend/app/routes/courses.py:174` |
| GET | `/courses/{}/pricing` | `backend/app/routes/courses.py:46` |
| GET | `/landing/intro-courses` | `backend/app/routes/landing.py:10` |
| GET | `/landing/popular-courses` | `backend/app/routes/landing.py:18` |
| GET | `/landing/services` | `backend/app/routes/landing.py:32` |
| GET | `/landing/teachers` | `backend/app/routes/landing.py:26` |
| GET | `/media/stream/{}` | `backend/app/routes/media.py:153` |
| GET | `/profiles/avatar/{}` | `backend/app/routes/api_profiles.py:129` |
| GET | `/profiles/me` | `backend/app/routes/api_profiles.py:21` |
| PATCH | `/profiles/me` | `backend/app/routes/api_profiles.py:31` |
| PATCH | `/studio/sessions/{}/slots/{}` | `backend/app/routes/studio_sessions.py:89` |
| POST | `/admin/teacher-requests/{}/approve` | `backend/app/routes/admin.py:63` |
| POST | `/admin/teacher-requests/{}/reject` | `backend/app/routes/admin.py:78` |
| POST | `/api/ai/execute` | `backend/app/routes/api_ai.py:152` |
| POST | `/api/ai/execute-built` | `backend/app/routes/api_ai.py:184` |
| POST | `/api/ai/plan-and-execute` | `backend/app/routes/api_ai.py:360` |
| POST | `/api/ai/plan-and-execute-v1` | `backend/app/routes/api_ai.py:498` |
| POST | `/api/ai/tool-call` | `backend/app/routes/api_ai.py:289` |
| POST | `/api/billing/create-checkout-session` | `backend/app/routes/billing.py:57` |
| POST | `/api/billing/create-subscription` | `backend/app/routes/billing.py:26` |
| POST | `/api/billing/webhook` | `backend/app/routes/stripe_webhook.py:11` |
| POST | `/api/context7/build` | `backend/app/routes/api_context7.py:34` |
| POST | `/auth/me/avatar` | `backend/app/routes/api_auth.py:254` |
| POST | `/auth/oauth` | `backend/app/routes/api_auth.py:53` |
| POST | `/courses/{}/bind-price` | `backend/app/routes/courses.py:61` |
| POST | `/media/sign` | `backend/app/routes/media.py:134` |
| POST | `/profiles/me/avatar` | `backend/app/routes/api_profiles.py:46` |
| POST | `/sfu/webhooks/livekit` | `backend/app/routes/api_sfu.py:104` |
| POST | `/studio/lessons/{}/media` | `backend/app/routes/studio.py:880` |
| POST | `/studio/sessions` | `backend/app/routes/studio_sessions.py:29` |
| POST | `/studio/sessions/{}/slots` | `backend/app/routes/studio_sessions.py:72` |
| POST | `/webhooks/livekit` | `backend/app/routes/livekit_webhooks.py:18` |
| POST | `/webhooks/stripe` | `backend/app/routes/stripe_webhooks.py:66` |
| PUT | `/studio/quizzes/{}/questions/{}` | `backend/app/routes/studio.py:1049` |
| PUT | `/studio/sessions/{}` | `backend/app/routes/studio_sessions.py:38` |

## Unmounted / hidden routes
- Unmounted routers (present in code but not mounted in `backend/app/main.py`): `backend/app/routes/auth.py`, `backend/app/routes/api_payments.py`.
  - Frontend references that depend on these routers:
    - `frontend/lib/api/auth_repository.dart:68` `/auth/forgot-password`
    - `frontend/lib/api/auth_repository.dart:86` `/auth/reset-password`
    - `frontend/lib/features/payments/data/payments_repository.dart:226` `/payments/create-checkout-session`
- Hidden from OpenAPI schema (include_in_schema=False):
  - `backend/app/routes/courses.py:42` `GET /courses/` (alias of `/courses`)
  - `backend/app/routes/courses.py:192` `GET /courses/config/free-course-limit` (alias of `/courses/config/free-limit`)
