## TASK ID

OEA-A07

## TITLE

PHASE_A_DRIFT_REMOVAL - Remove Referral Missing-Table Fallback

## TYPE

LEGACY_REMOVAL

## PURPOSE

Remove referral repository behavior that treats missing `app.referral_codes` as a normal no-result condition.

## DEPENDS_ON

- OEA-A01

## TARGET SURFACES

- `backend/app/repositories/referrals.py`
- `backend/app/services/referral_service.py`
- `backend/app/routes/referrals.py`

## EXPECTED RESULT

Referral authority fails closed when canonical referral substrate is missing or unavailable.

## INVARIANTS

- Missing `app.referral_codes` MUST NEVER be treated as no referral found.
- Missing `app.referral_codes` MUST NEVER allow signup, redemption, membership grant, onboarding completion, or app-entry.
- Referral redemption MUST NEVER be part of `/auth/register`.
- Referral link presence MUST NEVER be app-entry authority.

## VERIFICATION

- Verify missing-table behavior raises a deterministic authority/substrate failure.
- Verify no referral path catches missing authority as normal no-result.
- Verify referral redeem remains blocked until `app.referral_codes` exists.
