# CMT-007_LEGACY_REMOVAL

- TYPE: `OWNER`
- TITLE: `Remove or isolate legacy commerce and membership surfaces once canonical replacements exist`
- DOMAIN: `legacy surface cleanup`
- GROUP: `LEGACY REMOVAL`

## Problem Statement

The repo still carries duplicate membership initiation, portal/cancel semantics rooted in legacy status logic, polymorphic launch checkout, service purchase leakage, subscription-era repositories, coupon helpers, order wrappers outside the locked contract, and stale claim flows. Historical `session-status` polling drift is already resolved: `/api/billing/session-status` is non-mounted and guard-railed by canonical commerce tests.

## Contract References

- `commerce_membership_contract.md` sections `13`, `14`, `15`

## Audit Inputs

- `AUD-03` duplicate initiation
- `AUD-04` session-status runtime surface
  - Resolved note: `/api/billing/session-status` is not mounted, is covered by 404 guardrails in `backend/tests/test_commerce_contract_gate.py`, and the legacy test file is explicitly quarantined in `backend/tests/test_session_status.py`.
- `AUD-05` undeclared portal/cancel surface
- `AUD-06` polymorphic launch checkout with service branch
- `AUD-09` legacy subscription/coupon stack
- `AUD-13` order and claim wrappers
- `AUD-14` direct client-side payment surface

## Implementation Surfaces Affected

- `backend/app/routes/billing.py`
- `backend/app/routes/api_checkout.py`
- `backend/app/services/universal_checkout_service.py`
- `backend/app/repositories/subscriptions.py`
- `backend/app/models.py`
- `frontend/lib/features/payments/data/payments_repository.dart`
- `frontend/lib/features/payments/presentation/claim_purchase_page.dart`
- `frontend/lib/data/repositories/orders_repository.dart`

## DEPENDS_ON

- `CMT-005_ROUTE_ALIGNMENT`
- `CMT-006_FRONTEND_ALIGNMENT`
- `CMT-008_BUNDLE_PRESERVATION`

## Acceptance Criteria

- Duplicate and forbidden launch commerce surfaces are removed or isolated from runtime authority.
- Legacy `subscription` terminology is no longer used as a canonical membership authority surface.
- Polymorphic launch checkout no longer handles membership or service purchase in launch scope.
- Frontend claim/order wrappers do not point at removed or non-canonical backend behavior.

## Stop Conditions

- Stop if a surface still has a live runtime dependency that is not yet replaced by a contract-aligned path.

## Out Of Scope

- New feature work
- Bundle domain removal
