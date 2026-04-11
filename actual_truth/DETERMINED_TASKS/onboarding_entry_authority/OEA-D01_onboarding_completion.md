## TASK ID

OEA-D01

## TITLE

PHASE_D_ONBOARDING_IMPLEMENTATION - Enforce Canonical Onboarding Completion Transition

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Ensure onboarding completion is explicit, idempotent, and owned only by `POST /auth/onboarding/complete`.

## DEPENDS_ON

- OEA-B03
- OEA-C05

## TARGET SURFACES

- `backend/app/routes/auth.py`
- `backend/app/repositories/auth_subjects.py`
- `backend/app/services/onboarding_state.py`
- `backend/app/services/email_verification.py`
- `backend/app/services/membership_grant_service.py`
- `backend/app/services/subscription_service.py`

## EXPECTED RESULT

Only `POST /auth/onboarding/complete` may persist `app.auth_subjects.onboarding_state = 'completed'`.

## INVARIANTS

- Registration MUST NOT complete onboarding.
- Login MUST NOT complete onboarding.
- Token refresh MUST NOT complete onboarding.
- Profile read/update MUST NOT complete onboarding.
- Email verification MUST NOT complete onboarding.
- Invite membership grant MUST NOT complete onboarding.
- Referral redemption MUST NOT complete onboarding.
- Stripe webhook processing MUST NOT complete onboarding.

## VERIFICATION

- Verify direct onboarding completion sets `completed`.
- Verify all other flows leave onboarding state unchanged.
- Verify incomplete onboarding denies app-entry even when membership is active.
