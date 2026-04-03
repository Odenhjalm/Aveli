# API Endpoint Mapping Notes (2026-01-09)

- Payments: `/payments/*` replaced with `/orders` (create/list/get), `/api/checkout/create` (course/service checkout), and `/api/billing/*` (subscriptions, portal, status).
- Membership status: legacy `/payments/subscription` and `/api/me/*` status reads were removed; use `/api/billing/session-status` for checkout confirmation and the billing/customer-portal surfaces for active subscription flows.
- Purchase claims: legacy `/payments/purchases/claim` and `/api/me/claim-purchase` were removed; no canonical replacement exists in the active runtime.
- Session checkout: `/checkout/session` replaced with `/api/checkout/create` and webview checkout flow.
- Media signing: `/media/presign` replaced with `/media/sign` (signed URLs point to `/media/stream/{token}`).
- Auth reset: `/auth/forgot-password` and `/auth/reset-password` are now mounted under the main `api_auth` router.
