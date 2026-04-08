# RCD-008_LEGACY_SURFACE_ISOLATION_SWEEP

- TYPE: `legacy-isolation`
- TITLE: `Isolate or remove non-canonical auth and media surfaces after replacement exists`
- DOMAIN: `legacy / non-canonical surfaces`

## Problem Statement

The repo still contains multiple legacy or stale surfaces that can confuse audits and future implementation work: unmounted auth/media/profile modules, helper-only route modules mistaken for active routers, active-but-disabled legacy studio endpoints, and stale observational assumptions. These surfaces must be isolated only after canonical replacements are clear.

## Primary Authority Reference

- `Aveli_System_Decisions.md`
- `actual_truth/system_runtime_rules.md`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md`
- `actual_truth/contracts/lesson_media_edge_contract.md`

## Implementation Surfaces Affected

- `backend/app/routes/api_auth.py`
- `backend/app/routes/api_profiles.py`
- `backend/app/routes/api_media.py`
- `backend/app/routes/media.py`
- `backend/app/routes/upload.py`
- `backend/app/routes/studio.py`

## DEPENDS_ON

- `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
- `RCD-004_ONBOARDING_MUTATION_SURFACE_ALIGNMENT`
- `RCD-005_ROLE_TEACHER_RIGHTS_RUNTIME_ALIGNMENT`
- `RCD-006_MEDIA_WRITE_ROUTE_ALIGNMENT`
- `RCD-007_MEDIA_READ_COMPOSITION_ALIGNMENT`

## Acceptance Criteria

- Every non-canonical surface is explicitly one of:
  - removed
  - helper-only and non-routable
  - mounted but intentionally blocked with clear isolation semantics
- No stale or duplicate route surface can be mistaken for active canonical truth.
- Legacy auth and media surfaces no longer compete with canonical replacements.

## Stop Conditions

- Stop if canonical replacement behavior is not yet in place for any legacy surface targeted for removal or isolation.
- Stop if a retained helper module is still imported as active route authority.

## Out Of Scope

- Mirror regeneration
- Historical audit rewrites
- Frontend cleanup
