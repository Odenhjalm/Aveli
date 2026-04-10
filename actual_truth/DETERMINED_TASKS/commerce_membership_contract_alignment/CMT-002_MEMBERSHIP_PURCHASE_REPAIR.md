# CMT-002_MEMBERSHIP_PURCHASE_REPAIR

- TYPE: `OWNER`
- TITLE: `Make membership purchase order-backed and align the initiation endpoint to contract truth`
- DOMAIN: `membership purchase authority`
- GROUP: `MEMBERSHIP PURCHASE REPAIR`

## Problem Statement

`POST /api/billing/create-subscription` still creates a Stripe session and writes `app.memberships.status='incomplete'` without creating an order. The duplicate `POST /api/billing/create-checkout-session` path remains present, and the current response shape does not match the contract's locked `{ url, session_id, order_id }`.

## Contract References

- `commerce_membership_contract.md` sections `1`, `3`, `5`, `8`, `9`, `13`, `14`

## Audit Inputs

- `AUD-02` orderless `create-subscription`
- `AUD-03` duplicate membership initiation

## Implementation Surfaces Affected

- `backend/app/routes/billing.py`
- `backend/app/services/subscription_service.py`
- `backend/app/schemas/billing.py`
- `backend/app/repositories/orders.py`
- `backend/app/repositories/payments.py`

## DEPENDS_ON

- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`
- `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`

## Acceptance Criteria

- Membership purchase initiation creates a pending order in `app.orders`.
- Stripe subscription checkout metadata carries order linkage.
- Membership initiation leaves `app.memberships` non-access-granting until webhook confirmation.
- `POST /api/billing/create-subscription` is the only canonical membership initiation path.
- Membership purchase response matches `{ url, session_id, order_id }`.

## Stop Conditions

- Stop if the repo contains a second mounted membership purchase initiation path with overlapping launch authority.

## Out Of Scope

- Webhook settlement and payment recording
- Route mounting
- Frontend alignment
