# CMT-003_WEBHOOK_REPAIR

- TYPE: `OWNER`
- TITLE: `Repair canonical webhook settlement for membership while isolating mixed-domain branches`
- DOMAIN: `payment confirmation`
- GROUP: `WEBHOOK REPAIR`

## Problem Statement

`POST /api/stripe/webhook` is the canonical payment-confirmation path by name, but membership processing still updates `app.memberships` without settling membership orders/payments first, and the route mixes course, bundle, refund, service fallback, and Connect branches.

## Contract References

- `commerce_membership_contract.md` sections `1`, `3`, `4`, `5`, `7`, `8`, `13`

## Audit Inputs

- `AUD-07` mixed webhook with non-canonical membership settlement
- `AUD-02` orderless membership initiation
- `AUD-16` future-domain leakage through Connect handling

## Implementation Surfaces Affected

- `backend/app/routes/stripe_webhooks.py`
- `backend/app/services/subscription_service.py`
- `backend/app/repositories/orders.py`
- `backend/app/repositories/payments.py`

## DEPENDS_ON

- `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
- `CMT-002_MEMBERSHIP_PURCHASE_REPAIR`

## Acceptance Criteria

- Membership webhook flow resolves each canonical membership event back to a membership purchase order.
- Webhook marks the membership order paid before mutating membership state.
- Webhook records membership settlement in `app.payments`.
- Membership update happens only after canonical backend settlement.
- Service fallback purchase creation is removed from the launch webhook path.
- Connect handling is isolated from launch commerce authority.

## Stop Conditions

- Stop if membership webhook events cannot be deterministically mapped back to an order from existing Stripe metadata and contract-allowed identifiers.

## Out Of Scope

- Frontend redirect handling
- Route mounting
- Legacy surface deletion after replacements are live
