# Commerce + Membership Contract Alignment DAG Summary

## Final State

- STATUS: `TASKS_READY`

## Task IDs

- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`
- `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
- `CMT-002_MEMBERSHIP_PURCHASE_REPAIR`
- `CMT-003_WEBHOOK_REPAIR`
- `CMT-003.5_CANCEL_INTENT`
- `CMT-004_ACCESS_LOGIC_REPAIR`
- `CMT-005_ROUTE_ALIGNMENT`
- `CMT-006_FRONTEND_ALIGNMENT`
- `CMT-007_LEGACY_REMOVAL`
- `CMT-008_BUNDLE_PRESERVATION`
- `CMT-009_TEST_AND_GATE`

## Dependency Graph In Topological Order

1. `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`
2. `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
3. `CMT-002_MEMBERSHIP_PURCHASE_REPAIR`
4. `CMT-003_WEBHOOK_REPAIR`
5. `CMT-003.5_CANCEL_INTENT`
6. `CMT-004_ACCESS_LOGIC_REPAIR`
7. `CMT-008_BUNDLE_PRESERVATION`
8. `CMT-005_ROUTE_ALIGNMENT`
9. `CMT-006_FRONTEND_ALIGNMENT`
10. `CMT-007_LEGACY_REMOVAL`
11. `CMT-009_TEST_AND_GATE`

## Key Dependency Corrections

- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION -> CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION -> CMT-002_MEMBERSHIP_PURCHASE_REPAIR`
- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION -> CMT-003_WEBHOOK_REPAIR`

## Smallest Safe Execution Entrypoint

- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`
- Rationale: the contracts already ratify `app.orders` and `app.payments` as purchase authority, but clean baseline replay does not materialize them. Membership purchase and webhook repair cannot be clean-room canonical before the purchase substrate itself is baseline-backed.

## Highest-Risk Tasks

- `CMT-002_MEMBERSHIP_PURCHASE_REPAIR`
  - Membership purchase is still orderless and currently mutates membership state before canonical payment confirmation.
- `CMT-003_WEBHOOK_REPAIR`
  - The canonical webhook route still mixes membership, course, bundle, refund, service, and Connect branches.
- `CMT-005_ROUTE_ALIGNMENT`
  - Mounting launch commerce routes before backend repairs would expose non-canonical behavior.
- `CMT-006_FRONTEND_ALIGNMENT`
  - Frontend return/deeplink logic still treats Stripe runtime state as meaningful status.

## Domain Partitioning

- Baseline fixes:
  - `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`
  - `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
- Membership purchase repair:
  - `CMT-002_MEMBERSHIP_PURCHASE_REPAIR`
- Webhook repair:
  - `CMT-003_WEBHOOK_REPAIR`
- Webhook repair / intent:
  - `CMT-003.5_CANCEL_INTENT`
- Access logic repair:
  - `CMT-004_ACCESS_LOGIC_REPAIR`
- Route alignment:
  - `CMT-005_ROUTE_ALIGNMENT`
- Frontend alignment:
  - `CMT-006_FRONTEND_ALIGNMENT`
- Legacy removal:
  - `CMT-007_LEGACY_REMOVAL`
- Bundle preservation:
  - `CMT-008_BUNDLE_PRESERVATION`
- Test + gate:
  - `CMT-009_TEST_AND_GATE`

## Audit Notes That Drive The DAG

- `app.orders` and `app.payments` are contract-ratified purchase substrate but currently lack an explicit baseline-owner task.
- `backend/app/main.py` does not mount the launch commerce and adjacent routes required by the contract.
- `POST /api/billing/create-subscription` still creates membership state without an order.
- Membership webhook processing still updates `app.memberships` without settling `app.orders` and `app.payments`.
- Cancellation intent needs its own backend-owned, non-authoritative surface so Stripe cancellation changes can flow back through webhook-driven membership state transitions.
- Access logic still relies on `active|trialing` instead of the contract's `active` or `canceled && current_time < expires_at`.
- Frontend return/deeplink logic still propagates `subscription_status` and treats `trialing` as success.
- Bundle commerce is already order-backed and payment-backed and must remain separated from membership while launch commerce is repaired.
