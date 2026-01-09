# API Endpoint Mapping Notes (2026-01-09)

- Payments: `/payments/*` replaced with `/orders` (create/list/get), `/api/checkout/create` (course/service checkout), and `/api/billing/*` (subscriptions, portal, status).
- Membership status: `/payments/subscription` replaced with `/api/me/entitlements` and `/api/me/membership`.
- Purchase claims: `/payments/purchases/claim` replaced with `/api/me/claim-purchase`.
- Session checkout: `/checkout/session` replaced with `/api/checkout/create` and webview checkout flow.
- Media signing: `/media/presign` replaced with `/media/sign` (signed URLs point to `/media/stream/{token}`).
- Auth reset: `/auth/forgot-password` and `/auth/reset-password` are now mounted under the main `api_auth` router.
