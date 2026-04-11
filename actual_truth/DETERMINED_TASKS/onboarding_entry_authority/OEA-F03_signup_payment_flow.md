## TASK ID

OEA-F03

## TITLE

PHASE_F_FRONTEND_ENFORCEMENT - Normal Signup Identity Then Payment Flow

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Implement normal signup routing so identity capture happens before payment capture, while payment state remains non-authoritative.

## DEPENDS_ON

- OEA-F02

## TARGET SURFACES

- `frontend/lib/features/auth/presentation/signup_page.dart`
- `frontend/lib/features/payments/presentation/subscribe_screen.dart`
- `frontend/lib/features/paywall/presentation/checkout_result_page.dart`
- `frontend/lib/api/auth_repository.dart`

## EXPECTED RESULT

Normal signup creates identity first, then routes to payment capture, then refreshes backend entry truth.

## INVARIANTS

- Payment MUST occur after identity capture in the normal flow.
- Checkout success MUST NEVER be app-entry authority.
- Frontend MUST refresh backend entry truth after payment return.
- Frontend MUST NEVER infer membership from checkout UI state.

## VERIFICATION

- Verify normal signup does not attempt payment before identity exists.
- Verify checkout success without backend active membership does not enter the app.
- Verify backend entry truth is refreshed after checkout return.
