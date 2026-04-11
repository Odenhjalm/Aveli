## TASK ID

OEA-B02

## TITLE

PHASE_B_ENTRY_ENFORCEMENT - Split Identity Pre-Entry From App-Entry

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Separate identity-only pre-entry routes from global app-entry routes using the route classification from OEA-A01 and the single entry dependency from OEA-B01.

## DEPENDS_ON

- OEA-B01

## TARGET SURFACES

- `backend/app/auth.py`
- `backend/app/routes/auth.py`
- `backend/app/routes/email_verification.py`
- `backend/app/routes/profiles.py`
- `backend/app/routes/billing.py`
- `backend/app/routes/referrals.py`

## EXPECTED RESULT

Auth, invite validation, onboarding completion, referral redemption, profile completion, and payment capture routes are explicitly pre-entry where required and never mistaken for app-entry.

## INVARIANTS

- Identity-only pre-entry routes MUST NEVER grant global app-entry.
- Pre-entry routes MUST NOT use the app-entry dependency unless classified as app-entry.
- App-entry routes MUST use the canonical app-entry dependency.
- No route may treat token, profile, role, admin, invite token, referral code, or Stripe return state as app-entry authority.

## VERIFICATION

- Verify every route in scope uses exactly one classification.
- Verify no route remains ambiguously guarded.
- Verify pre-entry route success does not imply app-entry success.
