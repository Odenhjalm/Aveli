## TASK ID

OEA-C02

## TITLE

PHASE_C_BASELINE_ALIGNMENT - Add Referral Codes Baseline Substrate

## TYPE

BASELINE_SLOT

## PURPOSE

Create the missing canonical baseline substrate for `app.referral_codes`.

## DEPENDS_ON

- OEA-C01
- OEA-A07
- OEA-A08

## TARGET SURFACES

- `backend/supabase/baseline_slots/*`
- `backend/app/repositories/referrals.py`
- `backend/app/services/referral_service.py`

## EXPECTED RESULT

Clean baseline replay materializes `app.referral_codes` with the columns and constraints required by the referral runtime authority.

## INVARIANTS

- Referral authority MUST be stored in `app.referral_codes`.
- Referral MUST remain post-auth redeem only.
- Referral MUST NEVER be part of `/auth/register`.
- Missing `app.referral_codes` MUST NEVER be treated as normal no-result behavior.
- Referral substrate MUST NOT redefine invite authority.

## VERIFICATION

- Verify clean replay creates `app.referral_codes`.
- Verify repository reads and writes match the baseline shape.
- Verify missing-table fallback tests fail closed.
