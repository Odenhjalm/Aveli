# RCD-005_ROLE_TEACHER_RIGHTS_RUNTIME_ALIGNMENT

- TYPE: `runtime`
- TITLE: `Align effective role and teacher-rights evaluation to canonical precedence`
- DOMAIN: `teacher-rights authority`

## Problem Statement

Mounted runtime logic currently grants teacher rights from multiple paths: `is_admin`, `role_v2 in {'teacher','admin'}`, `teacher_permissions`, and `teacher_approvals`. This conflicts with the canonical contract, which makes `role_v2 = teacher` the only teacher-rights authority and keeps `is_admin` separate from teacher rights.

## Primary Authority Reference

- `actual_truth/contracts/onboarding_teacher_rights_contract.md`

## Implementation Surfaces Affected

- `backend/app/models.py`
- `backend/app/permissions.py`
- `backend/app/routes/auth.py`
- `backend/app/routes/admin.py`
- `backend/app/repositories/profiles.py`

## DEPENDS_ON

- `RCD-003_ONBOARDING_ROLE_BASELINE_SCHEMA_ALIGNMENT`

## Acceptance Criteria

- Teacher-rights reads are derived from canonical role authority instead of admin status or supporting tables.
- `is_admin` remains an admin override only and does not itself grant teacher rights.
- Canonical role precedence is enforced without inventing fallback values.
- Approval writes and runtime reads agree on the same teacher-rights model.

## Stop Conditions

- Stop if any mounted permission surface still requires `role_v2 = admin` or `is_admin = true` to imply teacher rights.
- Stop if supporting tables still act as independent teacher-rights truth after the canonical read model is updated.

## Out Of Scope

- Membership logic
- Frontend role presentation
- Route inventory cleanup
