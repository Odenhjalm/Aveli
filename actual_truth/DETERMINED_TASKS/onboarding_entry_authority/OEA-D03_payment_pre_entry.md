## TASK ID

OEA-D03

## TITLE

PHASE_D_ONBOARDING_IMPLEMENTATION - Preserve Payment After Identity Pre-Entry

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Preserve normal payment after identity capture as a pre-entry flow that may create membership authority but cannot itself grant app-entry.

## DEPENDS_ON

- OEA-D02
- OEA-B03

## TARGET SURFACES

- `backend/app/routes/billing.py`
- `backend/app/routes/api_checkout.py`
- `backend/app/services/subscription_service.py`
- `backend/app/routes/stripe_webhooks.py`
- `backend/app/repositories/memberships.py`

## EXPECTED RESULT

Payment flow can create or update canonical `app.memberships`, but app-entry is allowed only after completed onboarding and active membership are both true.

## INVARIANTS

- Payment success MUST NEVER grant app-entry directly.
- Checkout return state MUST NEVER grant app-entry.
- Stripe runtime subscription payload MUST NEVER bypass `app.memberships`.
- Membership created by payment MUST still require onboarding completion before app-entry.
- Missing canonical membership row MUST deny entry even after checkout return.

## VERIFICATION

- Verify checkout success without canonical active membership denies entry.
- Verify active purchase membership plus incomplete onboarding denies entry.
- Verify active purchase membership plus completed onboarding allows entry.
