# RCD-003_ONBOARDING_ROLE_BASELINE_SCHEMA_ALIGNMENT

- TYPE: `baseline-bootstrap`
- TITLE: `Align baseline auth/profile schema to the canonical onboarding and role contract`
- DOMAIN: `onboarding authority and teacher-rights authority`

## Problem Statement

The canonical onboarding and teacher-rights contract defines `onboarding_state = incomplete|completed`, `role_v2 = learner|teacher`, `role` as legacy fallback, and `is_admin` as a separate override. The baseline schema still materializes legacy enums and defaults such as `student`, `user`, `professional`, and five onboarding states. This leaves the local canonical baseline out of alignment with the primary contract.

## Primary Authority Reference

- `actual_truth/contracts/onboarding_teacher_rights_contract.md`
- `AVELI_DATABASE_BASELINE_MANIFEST.md`
- `backend/supabase/baseline_slots/0001_canonical_foundation.sql`
- `backend/supabase/baseline_slots/0013_profiles_core.sql`

## Implementation Surfaces Affected

- `backend/supabase/baseline_slots/0001_canonical_foundation.sql`
- `backend/supabase/baseline_slots/0013_profiles_core.sql`
- `backend/supabase/baseline_slots/0016_auth_runtime_support_core.sql`
- `backend/supabase/baseline_slots.lock.json`

## DEPENDS_ON

- None

## Acceptance Criteria

- Baseline enum values and defaults for `role`, `role_v2`, and `onboarding_state` match the canonical contract.
- Baseline profile constraints reject non-canonical onboarding and role values.
- `backend/supabase/baseline_slots.lock.json` is refreshed if any protected slot content changes.
- Baseline replay remains rooted in `backend/supabase/baseline_slots`.

## Stop Conditions

- Stop if another protected baseline slot reintroduces legacy auth/profile values outside the audited files.
- Stop if canonical onboarding/role values cannot be expressed without contradicting other primary baseline authorities.

## Out Of Scope

- Runtime code changes
- Auth route changes
- Execute-mode replay
