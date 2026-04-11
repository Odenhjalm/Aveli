## TASK ID

OEA-G03

## TITLE

PHASE_G_VERIFICATION - Invite/Referral Baseline Tests

## TYPE

TEST_ALIGNMENT

## PURPOSE

Add tests for invite/referral separation and baseline-backed referral authority.

## DEPENDS_ON

- OEA-C05
- OEA-E01
- OEA-E02
- OEA-E03
- OEA-E04
- OEA-E05

## TARGET SURFACES

- `backend/tests/*`
- `frontend/*`
- `backend/supabase/baseline_slots/*`
- `backend/app/routes/auth.py`
- `backend/app/routes/referrals.py`
- `backend/app/services/referral_service.py`

## EXPECTED RESULT

Tests prove invite creates a time-bounded invite membership, referral is post-auth redeem only, and neither flow bypasses onboarding or app-entry law.

## INVARIANTS

- Invite MUST create `source = 'invite'` membership with `expires_at`.
- Referral MUST NEVER be part of register flow.
- No shared invite/referral parameter handling may exist.
- Missing `app.referral_codes` MUST fail closed.
- Neither invite nor referral may bypass onboarding completion.
- OEA-G03 MUST occur after OEA-E01 and OEA-E05.

## VERIFICATION

- Verify invite acceptance creates the correct membership row.
- Verify `/auth/register` rejects `referral_code`.
- Verify referral link generation and frontend parsing match the redeem flow.
- Verify missing referral substrate fails closed.
