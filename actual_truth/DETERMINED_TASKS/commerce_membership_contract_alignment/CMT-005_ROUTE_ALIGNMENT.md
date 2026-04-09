# CMT-005_ROUTE_ALIGNMENT

- TYPE: `OWNER`
- TITLE: `Mount only contract-aligned launch commerce routes after backend repair`
- DOMAIN: `runtime route exposure`
- GROUP: `ROUTE ALIGNMENT`

## Problem Statement

The contract's canonical launch commerce routes are not mounted in `backend/app/main.py`. Mounting them in their current state would expose non-canonical purchase, webhook, and access logic, so route exposure must be sequenced after backend repairs.

## Contract References

- `commerce_membership_contract.md` sections `3`, `14`, `15`

## Audit Inputs

- `AUD-01` route mounting gap
- `AUD-02` through `AUD-08` backend commerce drift

## Implementation Surfaces Affected

- `backend/app/main.py`
- `backend/app/routes/billing.py`
- `backend/app/routes/api_checkout.py`
- `backend/app/routes/stripe_webhooks.py`
- `backend/app/routes/api_orders.py`
- `backend/app/routes/course_bundles.py`
- `backend/app/routes/api_events.py`
- `backend/app/routes/api_notifications.py`

## DEPENDS_ON

- `CMT-002_MEMBERSHIP_PURCHASE_REPAIR`
- `CMT-003_WEBHOOK_REPAIR`
- `CMT-004_ACCESS_LOGIC_REPAIR`
- `CMT-008_BUNDLE_PRESERVATION`

## Acceptance Criteria

- Canonical launch commerce entrypoints are mounted only after their handlers are contract-aligned.
- Adjacent routes that remain outside the launch contract are mounted only if their behavior is explicit and isolated.
- Runtime exposure no longer points users at orderless membership or mixed-authority surfaces.

## Stop Conditions

- Stop if route mounting occurs in more than one runtime entrypoint and the mounted truth is not deterministic from repo code.

## Out Of Scope

- Frontend UI rewiring
- Test implementation
