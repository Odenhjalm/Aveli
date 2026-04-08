# AOC-003_LEGACY_SURFACE_ISOLATION

- TYPE: `OWNER`
- TITLE: `Isolate legacy shadow route modules and imports from active validation flow`
- DOMAIN: `legacy authority containment`
- CLASSIFICATION: `ISOLATE`

## Problem Statement

Even unmounted legacy route modules still act as shadow authority because tests and fixtures import them directly. Until those imports are removed, legacy Auth + Onboarding semantics can survive in validation flow and silently re-enter runtime decisions.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md`
- `actual_truth/Aveli_System_Decisions.md:413`

## Drift Evidence

- `backend/tests/test_onboarding_state.py:10` imports `app.routes.api_auth`.
- `backend/tests/test_membership_app_entry_gate.py:12` imports `app.routes.api_profiles`.
- `backend/test_email_verification.py:12` imports `app.routes.api_auth as api_auth_routes`.
- `backend/tests/conftest.py:139` imports `api_auth`.

## Implementation Surfaces Affected

- `backend/tests/test_onboarding_state.py`
- `backend/tests/test_membership_app_entry_gate.py`
- `backend/test_email_verification.py`
- `backend/tests/conftest.py`
- `backend/app/routes/api_auth.py`
- `backend/app/routes/api_profiles.py`

## DEPENDS_ON

- `AOC-002`

## Exact Implementation Steps

1. Rewrite unit tests and fixtures to target canonical services, repositories, or mounted route modules only.
2. Remove direct imports of `api_auth` and `api_profiles` from active validation surfaces.
3. Add a grep gate that fails on new runtime, test, or fixture imports of `api_auth` or `api_profiles`.
4. After all imports are removed, delete the legacy route modules or move them to a non-importable archival location.

## Acceptance Criteria

- No active validation surface imports `api_auth` or `api_profiles`.
- Legacy route modules cannot influence Auth + Onboarding validation outcomes.
- Legacy modules are no longer reachable as competing truth.

## Stop Conditions

- Stop if a canonical replacement import path is missing for a required test scenario.
- Stop if another module re-exports `api_auth` or `api_profiles` after isolation begins.

## Out Of Scope

- Legacy route modules outside Auth + Onboarding scope

