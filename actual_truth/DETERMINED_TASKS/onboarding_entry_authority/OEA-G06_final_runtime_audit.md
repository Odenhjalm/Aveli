## TASK ID

OEA-G06

## TITLE

PHASE_G_VERIFICATION - Final Contract-Vs-Runtime Audit

## TYPE

VERIFICATION

## PURPOSE

Perform a final contract-vs-runtime audit after all remediation, baseline, backend, frontend, invite/referral, and test tasks are complete.

## DEPENDS_ON

- OEA-G01
- OEA-G02
- OEA-G03
- OEA-G04
- OEA-G05

## TARGET SURFACES

- `actual_truth/contracts/onboarding_entry_authority_contract.md`
- `backend/app/**`
- `backend/supabase/baseline_slots/*`
- `frontend/lib/core/routing/*`
- `frontend/lib/features/auth/*`
- `frontend/lib/features/onboarding/*`

## EXPECTED RESULT

The system passes the canonical app-entry contract or produces a deterministic remaining-drift list.

## INVARIANTS

- App-entry MUST require completed onboarding and active membership.
- No app-entry route may use `CurrentUser`, `TeacherUser`, `AdminUser`, or `OptionalCurrentUser` as entry authority.
- Frontend MUST only reflect backend entry truth.
- Invite MUST create time-bounded `source = 'invite'` membership and must not bypass onboarding.
- Referral MUST remain post-auth redeem only.
- No fallback authority path may exist.

## VERIFICATION

- Re-run route inventory.
- Re-run dependency/middleware audit.
- Re-run baseline/schema audit.
- Re-run frontend redirect/gating audit.
- Re-run forbidden fallback audit.
- Return PASS only if all canonical authority invariants hold.
