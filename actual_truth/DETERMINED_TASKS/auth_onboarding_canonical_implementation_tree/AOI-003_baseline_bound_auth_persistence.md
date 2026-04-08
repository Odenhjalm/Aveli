# AOI-003 BASELINE-BOUND AUTH PERSISTENCE

TYPE: `OWNER`  
TASK_TYPE: `BACKEND_ALIGNMENT`  
DEPENDS_ON: `["AOI-001", "AOI-002"]`

## Goal

Bind backend Auth + Onboarding persistence to the baseline-owned substrate only.

## Required Outputs

- auth persistence writes refresh-token state only through `app.refresh_tokens`
- auth persistence writes canonical audit events only through `app.auth_events`
- backend respects operator-only admin bootstrap boundary
- runtime schema introspection is removed from auth/profile authority decisions

## Target Files

- `backend/app/repositories/auth.py`
- `backend/app/repositories/profiles.py`
- `backend/app/models.py`

## Exit Criteria

- no Auth + Onboarding authority depends on `information_schema`
- no hidden runtime fallback remains for missing columns or tables
- backend persistence assumes only canonical baseline objects
