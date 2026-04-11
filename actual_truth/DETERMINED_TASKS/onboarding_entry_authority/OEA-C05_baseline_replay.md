## TASK ID

OEA-C05

## TITLE

PHASE_C_BASELINE_ALIGNMENT - Replay Baseline Authority Substrate

## TYPE

VERIFICATION

## PURPOSE

Verify clean baseline replay after authority substrate alignment.

## DEPENDS_ON

- OEA-C02
- OEA-C03
- OEA-C04

## TARGET SURFACES

- `backend/supabase/baseline_slots/*`
- local baseline replay tooling
- backend readiness and schema validation checks

## EXPECTED RESULT

Clean replay materializes all canonical authority substrates required for onboarding entry authority.

## INVARIANTS

- Baseline replay MUST include `auth.users`, `app.auth_subjects`, `app.memberships`, `app.course_enrollments`, and `app.referral_codes`.
- Baseline replay MUST be deterministic.
- Baseline replay MUST NOT rely on pre-existing database state.
- Baseline replay MUST NOT modify accepted baseline slots in place; fixes must be append-only.

## VERIFICATION

- Run clean baseline replay in the canonical local verification environment.
- Verify schema objects exist with required constraints.
- Verify backend readiness does not fail due to missing authority substrate.
