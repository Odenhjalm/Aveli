# CMT-001_BASELINE_MEMBERSHIP_FOUNDATION

- TYPE: `OWNER`
- TITLE: `Align membership baseline and persistence surface to contract-required current-state fields`
- DOMAIN: `baseline membership authority`
- GROUP: `BASELINE FIXES`

## Problem Statement

The contract requires a single canonical current-state membership row with explicit source metadata and lifecycle semantics that support `canceled` access-until-expiry. The current baseline exposes only `membership_id`, `user_id`, `status`, `end_date`, `created_at`, and `updated_at`, while runtime code layers Stripe compatibility columns and legacy aliases on top.

## Contract References

- `commerce_membership_contract.md` sections `2`, `5`, `9`, `10`, `11`, `13`

## Audit Inputs

- `AUD-08` membership repository compatibility layer
- `AUD-11` referral grant without explicit contract-grade source metadata

## Implementation Surfaces Affected

- `backend/supabase/baseline_slots/0013_memberships_core.sql`
- `backend/supabase/baseline_slots.lock.json`
- `backend/app/repositories/memberships.py`
- `backend/app/schemas/memberships.py`

## DEPENDS_ON

- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`

## Acceptance Criteria

- Baseline-backed membership shape supports contract-required current-state semantics without relying on Stripe compatibility columns.
- Membership persistence supports explicit membership source metadata for `purchase`, `coupon`, and `invite`.
- Runtime membership repository stops treating Stripe runtime references as canonical membership authority.
- Single-row-per-user current-state authority remains preserved.

## Stop Conditions

- Stop if contract-required current-state fields cannot be represented without an explicit contract amendment.

## Out Of Scope

- Membership purchase flow repair
- Webhook settlement logic
- Frontend changes
