## TASK ID

OEA-E03

## TITLE

PHASE_E_INVITE_REFERRAL - Align Referral Link Generation To Redeem Flow

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Remove referral signup parameter drift by aligning generated referral links with the actual post-auth redemption flow.

## DEPENDS_ON

- OEA-E02

## TARGET SURFACES

- `backend/app/services/referral_service.py`
- `backend/app/routes/referrals.py`

## EXPECTED RESULT

Backend no longer generates `/signup?referral_code=...` as if referral belonged to registration.

## INVARIANTS

- Generated referral links MUST point to the canonical referral redemption flow.
- Referral links MUST NOT be treated as signup authority.
- Referral code MUST NOT be accepted by `/auth/register`.
- Referral link presence MUST NOT grant membership, onboarding completion, or app-entry.

## VERIFICATION

- Verify generated referral link target matches frontend parsing and backend redemption.
- Verify no generated referral link uses `referral_code` as a register parameter.
- Verify referral redemption still requires authenticated post-auth handling.
