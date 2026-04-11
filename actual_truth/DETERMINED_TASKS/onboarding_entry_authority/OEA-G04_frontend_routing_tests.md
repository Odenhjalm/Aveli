## TASK ID

OEA-G04

## TITLE

PHASE_G_VERIFICATION - Frontend Routing Flow Tests

## TYPE

TEST_ALIGNMENT

## PURPOSE

Add frontend tests for canonical pre-entry routing and backend-truth-only app-entry.

## DEPENDS_ON

- OEA-F01
- OEA-F02
- OEA-F03
- OEA-F04
- OEA-F05
- OEA-F06

## TARGET SURFACES

- `frontend/test/*`
- `frontend/lib/core/auth/*`
- `frontend/lib/core/routing/*`
- `frontend/lib/features/auth/*`
- `frontend/lib/features/onboarding/*`
- `frontend/lib/features/payments/*`

## EXPECTED RESULT

Frontend tests prove profile, token, role/admin, checkout result, invite token, and referral code do not grant app-entry.

## INVARIANTS

- Frontend MUST only reflect backend entry truth.
- Frontend MUST NEVER infer entry from profile.
- Frontend MUST NEVER infer entry from token.
- Frontend MUST NEVER infer entry from role/admin.
- Frontend MUST NEVER infer entry from checkout, invite, or referral state.

## VERIFICATION

- Run frontend routing tests for incomplete onboarding, missing membership, inactive membership, invite membership, payment return, teacher route, and admin route.
- Verify intro course offer is non-gating.
- Verify required intro messaging appears in onboarding UX tests.
