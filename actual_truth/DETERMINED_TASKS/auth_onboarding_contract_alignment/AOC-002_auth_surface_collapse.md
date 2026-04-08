# AOC-002_AUTH_SURFACE_COLLAPSE

- TYPE: `OWNER`
- TITLE: `Collapse duplicate auth/profile routes and schema surfaces into one canonical implementation surface`
- DOMAIN: `surface authority`
- CLASSIFICATION: `COLLAPSE`

## Problem Statement

The contract forbids duplicate `api_auth.py` and `api_profiles.py` surfaces from acting as canonical truth. The repo still carries duplicate auth/profile routers and duplicate schema definitions, which creates multiple possible interpretations of request and response shape.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md`
- `actual_truth/Aveli_System_Decisions.md:413`

## Drift Evidence

- `backend/app/routes/api_auth.py:463-638` still defines forbidden password-reset and current-user surfaces plus a duplicate avatar surface.
- `backend/app/routes/api_profiles.py:46-67` duplicates current-user profile routes.
- `backend/app/schemas.py` and `backend/app/schemas/__init__.py` both define auth/profile request and response models.
- `backend/app/schemas/__init__.py:98-100` keeps legacy cross-domain fields in the shared profile schema.

## Implementation Surfaces Affected

- `backend/app/routes/auth.py`
- `backend/app/routes/profiles.py`
- `backend/app/routes/email_verification.py`
- `backend/app/routes/admin.py`
- `backend/app/routes/api_auth.py`
- `backend/app/routes/api_profiles.py`
- `backend/app/schemas.py`
- `backend/app/schemas/__init__.py`

## DEPENDS_ON

- `AOC-001`

## Exact Implementation Steps

1. Declare `auth.py`, `email_verification.py`, `profiles.py`, and `admin.py` as the only canonical Auth + Onboarding route modules.
2. Collapse auth/profile request and response models to one schema surface that matches the contract exactly.
3. Remove extra Auth + Onboarding fields from the canonical shared profile schema before any duplicate module remains reachable.
4. Delete or fully de-reference `api_auth.py`, `api_profiles.py`, and any duplicate schema module once no imports remain.
5. Ensure canonical mounted routers do not inherit request or response shape from deleted legacy modules.

## Acceptance Criteria

- Only one schema surface defines Auth + Onboarding request and response shape.
- Only canonical route modules remain importable for Auth + Onboarding runtime.
- No duplicate `api_auth.py` or `api_profiles.py` truth survives.
- No legacy schema file can redefine canonical auth/profile shape.

## Stop Conditions

- Stop if another runtime import path still resolves auth/profile schemas from a duplicate surface.
- Stop if collapsing schema files would broaden scope into non-auth domains without an explicit contract dependency.

## Out Of Scope

- Non-auth route modules
- Non-auth schema families

