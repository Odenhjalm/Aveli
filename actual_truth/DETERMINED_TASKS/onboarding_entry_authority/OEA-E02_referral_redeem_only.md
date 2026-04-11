## TASK ID

OEA-E02

## TITLE

PHASE_E_INVITE_REFERRAL - Keep Referral Post-Auth Redeem Only

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Keep referral redemption separate from registration and invite handling.

## DEPENDS_ON

- OEA-C02
- OEA-E01

## TARGET SURFACES

- `backend/app/routes/referrals.py`
- `backend/app/services/referral_service.py`
- `backend/app/repositories/referrals.py`
- `backend/app/routes/auth.py`
- `backend/app/schemas/*`

## EXPECTED RESULT

Referral redemption happens only through authenticated `POST /referrals/redeem`; `/auth/register` does not accept or process referral codes.

## INVARIANTS

- Referral MUST be post-auth redeem only.
- Referral MUST NEVER be part of `/auth/register`.
- Referral MUST NEVER share invite parameter handling.
- Referral code presence MUST NEVER grant membership without redemption.
- Referral redemption MUST NOT complete onboarding.
- Referral redemption MUST NOT bypass app-entry law.

## VERIFICATION

- Verify `/auth/register` rejects `referral_code`.
- Verify referral redemption requires authenticated identity.
- Verify referral redemption can create membership but still requires onboarding completion before entry.
