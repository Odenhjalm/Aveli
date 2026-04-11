## TASK ID

OEA-E04

## TITLE

PHASE_E_INVITE_REFERRAL - Align Frontend Invite/Referral Parameters

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Separate frontend invite and referral parameter handling so there is no shared or ambiguous register path.

## DEPENDS_ON

- OEA-E03

## TARGET SURFACES

- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/features/auth/presentation/signup_page.dart`
- `frontend/lib/features/auth/presentation/invite_page.dart`
- `frontend/lib/api/auth_repository.dart`

## EXPECTED RESULT

Frontend passes `invite_token` only to invite/register bootstrap and never passes `referral_code` to `/auth/register`. Referral codes are handled only by the canonical post-auth redemption path.

## INVARIANTS

- Frontend MUST NEVER share invite and referral parameter handling.
- Frontend MUST NEVER send `referral_code` to `/auth/register`.
- Frontend MUST NEVER infer app-entry from invite token or referral code.
- Frontend MUST only reflect backend entry truth.

## VERIFICATION

- Verify invite link parsing uses only invite parameters.
- Verify referral link parsing uses only referral redemption handling.
- Verify signup request body cannot contain `referral_code`.
