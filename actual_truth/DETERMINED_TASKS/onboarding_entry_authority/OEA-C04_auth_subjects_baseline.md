## TASK ID

OEA-C04

## TITLE

PHASE_C_BASELINE_ALIGNMENT - Verify Auth Subjects Onboarding Substrate

## TYPE

VERIFICATION

## PURPOSE

Verify the canonical onboarding substrate remains `app.auth_subjects.onboarding_state` with only `incomplete` and `completed`.

## DEPENDS_ON

- OEA-C01

## TARGET SURFACES

- `backend/supabase/baseline_slots/0014_auth_subjects_core.sql`
- `backend/app/repositories/auth_subjects.py`
- `backend/app/services/onboarding_state.py`

## EXPECTED RESULT

Onboarding authority remains separate from profile projection, membership, role, admin, invite, and referral.

## INVARIANTS

- Onboarding state MUST be stored only in `app.auth_subjects.onboarding_state`.
- Allowed onboarding states MUST be only `incomplete` and `completed`.
- Profile existence MUST NEVER infer onboarding completion.
- Membership existence MUST NEVER infer onboarding completion.
- Invite membership grant MUST NEVER complete onboarding.

## VERIFICATION

- Verify baseline check constraint permits only `incomplete` and `completed`.
- Verify onboarding repository writes do not use profile or membership state.
- Verify no implicit completion path exists in baseline assumptions.
