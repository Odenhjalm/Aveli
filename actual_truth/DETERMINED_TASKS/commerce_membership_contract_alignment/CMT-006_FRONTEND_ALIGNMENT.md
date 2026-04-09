# CMT-006_FRONTEND_ALIGNMENT

- TYPE: `OWNER`
- TITLE: `Align frontend checkout, return, and management flows to backend-only authority`
- DOMAIN: `frontend commerce behavior`
- GROUP: `FRONTEND ALIGNMENT`

## Problem Statement

The scanned frontend still contains return/deeplink flows that propagate `subscription_status`, treats `trialing` as success, and keeps undeclared portal/cancel/order wrappers plus a dormant direct Stripe PaymentIntent surface. No scanned frontend initiator currently matches the contract's locked launch checkout entrypoints.

## Contract References

- `commerce_membership_contract.md` sections `6`, `10`, `11`, `13`, `14`

## Audit Inputs

- `AUD-12` landing return/deeplink authority leak
- `AUD-13` undeclared frontend billing and order wrappers
- `AUD-14` direct client-side PaymentIntent surface

## Implementation Surfaces Affected

- `frontend/landing/pages/checkout/return.tsx`
- `frontend/lib/core/deeplinks/deep_link_service.dart`
- `frontend/lib/features/paywall/presentation/checkout_webview_page.dart`
- `frontend/lib/features/paywall/presentation/checkout_result_page.dart`
- `frontend/lib/features/paywall/data/customer_portal_api.dart`
- `frontend/lib/features/payments/data/billing_api.dart`
- `frontend/lib/api/api_paths.dart`
- `frontend/lib/features/payments/widgets/payment_panel.dart`

## DEPENDS_ON

- `CMT-002_MEMBERSHIP_PURCHASE_REPAIR`
- `CMT-003_WEBHOOK_REPAIR`
- `CMT-004_ACCESS_LOGIC_REPAIR`
- `CMT-005_ROUTE_ALIGNMENT`

## Acceptance Criteria

- Frontend membership purchase uses only `POST /api/billing/create-subscription`.
- Frontend course purchase uses only `POST /api/checkout/create`.
- Frontend no longer treats Stripe success, `trialing`, or `subscription_status` as authority.
- Frontend checkout response handling matches `{ url, session_id, order_id }`.
- Frontend management UI does not depend on undeclared or removed backend surfaces.

## Stop Conditions

- Stop if any active frontend flow depends on a still-unrepaired backend surface and there is no contract-aligned replacement available.

## Out Of Scope

- Backend webhook settlement
- Legacy code deletion after replacements are stable
