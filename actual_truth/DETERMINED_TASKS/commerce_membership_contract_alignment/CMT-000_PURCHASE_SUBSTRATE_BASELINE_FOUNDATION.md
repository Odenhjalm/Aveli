# CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION

- TYPE: `OWNER`
- TITLE: `Materialize canonical purchase substrate baseline for order and payment authority`
- DOMAIN: `baseline purchase authority`
- GROUP: `BASELINE FIXES`

## Problem Statement

The active commerce contracts already ratify `app.orders` as purchase identity/lifecycle authority and `app.payments` as settlement authority tied to orders, but clean baseline replay does not materialize either table. Runtime checkout and webhook settlement therefore depend on non-baseline purchase substrate, which is forbidden under `supabase_integration_boundary_contract.md`.

This task establishes the sole baseline-backed purchase substrate required before any course, bundle, or membership checkout flow can be treated as clean-room canonical. It also classifies `app.stripe_customers` as non-authoritative support substrate, and `app.payment_events` plus `app.billing_logs` as non-authoritative support surfaces that must not be promoted to purchase authority.

## Contract References

- `commerce_membership_contract.md` sections `1`, `2`, `3`, `4`, `5`, `7`, `8`, `13`
- `course_monetization_contract.md` sections `1`, `8`
- `course_access_contract.md` sections `2`, `3`
- `supabase_integration_boundary_contract.md` section `4`

## Audit Inputs

- order/payment authority is contract-ratified but not baseline-backed
- clean baseline replay lacks `app.orders` and `app.payments`
- active checkout runtime depends on `app.stripe_customers`, `app.orders`, and `app.payments`
- `app.payment_events` and `app.billing_logs` are runtime support surfaces only

## Implementation Surfaces Affected

- `backend/supabase/baseline_slots/*`
- `backend/supabase/baseline_slots.lock.json`

## DEPENDS_ON

- None

## Acceptance Criteria

- Baseline-backed `app.orders` exists as canonical purchase identity and lifecycle authority.
- Baseline-backed `app.payments` exists as canonical payment settlement authority tied to orders.
- No runtime checkout or webhook authority depends on purchase tables that are absent from baseline replay.
- `app.stripe_customers` is explicitly classified as non-authoritative support substrate and is not promoted to purchase authority.
- `app.payment_events` and `app.billing_logs` are explicitly classified as non-authoritative support surfaces and not blockers for canonical purchase authority.
- No membership state, course access state, Stripe runtime state, or frontend state becomes purchase authority.

## Stop Conditions

- Stop if purchase authority is assigned to anything other than `app.orders` and `app.payments`.
- Stop if the proposed baseline substrate merges membership current-state authority into purchase authority.
- Stop if the proposed baseline substrate merges course-access authority into purchase authority.
- Stop if `app.stripe_customers`, `app.payment_events`, or `app.billing_logs` are promoted to canonical purchase authority.
- Stop if baseline materialization would rely on non-baseline schema drift or legacy migrations as runtime authority.

## Out Of Scope

- Checkout initiation implementation
- Webhook settlement implementation
- Membership current-state repair
- Frontend alignment
- Entitlement or access logic changes
