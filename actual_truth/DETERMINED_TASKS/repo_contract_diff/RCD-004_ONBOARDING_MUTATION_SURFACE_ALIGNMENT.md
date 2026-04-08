# RCD-004_ONBOARDING_MUTATION_SURFACE_ALIGNMENT

- TYPE: `mutation-surface`
- TITLE: `Align mounted onboarding progression to the canonical state contract`
- DOMAIN: `onboarding authority`

## Problem Statement

Mounted runtime code derives and persists legacy onboarding states such as `registered_unverified`, `verified_unpaid`, `access_active_profile_incomplete`, `access_active_profile_complete`, and `welcomed`. Observational docs also refer to a `welcome-complete` endpoint that is not present in mounted backend runtime. The mounted onboarding mutation surface does not currently implement the canonical `incomplete -> completed` model.

## Primary Authority Reference

- `actual_truth/contracts/onboarding_teacher_rights_contract.md`
- `actual_truth/system_runtime_rules.md`

## Implementation Surfaces Affected

- `backend/app/services/onboarding_state.py`
- `backend/app/routes/auth.py`
- `backend/app/routes/email_verification.py`
- `backend/app/routes/profiles.py`
- `backend/app/repositories/profiles.py`

## DEPENDS_ON

- `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
- `RCD-003_ONBOARDING_ROLE_BASELINE_SCHEMA_ALIGNMENT`

## Acceptance Criteria

- Mounted runtime no longer persists legacy onboarding states as contract truth.
- Mounted onboarding progression obeys the canonical allowed transitions.
- No active runtime surface relies on `welcomed` or other non-canonical onboarding states.
- Stale observational claims about onboarding completion routes are either superseded or explicitly marked non-authoritative.

## Stop Conditions

- Stop if mounted runtime still has more than one active onboarding completion path with different semantics.
- Stop if the contract cannot be implemented without inventing a new route or implicit default.

## Out Of Scope

- UI changes
- Frontend navigation changes
- Teacher-rights mutation
