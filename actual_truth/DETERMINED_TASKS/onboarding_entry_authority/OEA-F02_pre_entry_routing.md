## TASK ID

OEA-F02

## TITLE

PHASE_F_FRONTEND_ENFORCEMENT - Implement Pre-Entry Route Graph

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Implement a deterministic frontend route graph for identity, onboarding completion, payment capture, invite profile completion, referral redemption, and app-entry based on backend truth.

## DEPENDS_ON

- OEA-F01
- OEA-D03
- OEA-E05

## TARGET SURFACES

- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/core/routing/route_manifest.dart`
- `frontend/lib/core/routing/route_paths.dart`
- `frontend/lib/features/onboarding/welcome_page.dart`
- `frontend/lib/features/payments/presentation/subscribe_screen.dart`

## EXPECTED RESULT

Users are routed to the exact required pre-entry step until backend entry truth says app-entry is allowed.

## INVARIANTS

- Pre-entry routing MUST NOT be app-entry authority.
- Completed onboarding plus active membership MUST be required for app-entry.
- Intro course selection MUST NOT be a hard global app-entry gate.
- Payment return state MUST NOT grant app-entry.
- Invite route state MUST NOT grant app-entry.

## VERIFICATION

- Verify incomplete onboarding routes to onboarding/profile completion.
- Verify missing or inactive membership routes to payment or appropriate pre-entry flow.
- Verify completed onboarding plus active membership routes to app-entry.
