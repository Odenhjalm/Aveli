## TASK ID

OEA-F05

## TITLE

PHASE_F_FRONTEND_ENFORCEMENT - Intro Course Offer Non-Gate Messaging

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Add introductory offering UX during onboarding while preserving that intro course selection is not a global app-entry gate.

## DEPENDS_ON

- OEA-F04
- OEA-B05

## TARGET SURFACES

- `frontend/lib/features/onboarding/welcome_page.dart`
- `frontend/lib/features/courses/*`
- `frontend/lib/core/routing/app_router.dart`

## EXPECTED RESULT

Onboarding can present one introduction course offer with clear business messaging: first month is a trial period, one introduction course is offered, and lesson drip is weekly.

## INVARIANTS

- Intro course selection MUST NOT be required for global app-entry.
- Intro course selection MUST NOT mutate `app.memberships` unless separate membership authority applies.
- Intro course selection MUST NOT bypass course enrollment authority.
- Intro messaging MUST communicate first month trial, one introduction course, and weekly lesson drip.

## VERIFICATION

- Verify skipping or not selecting an intro course does not block app-entry when backend entry law is true.
- Verify selecting intro course does not grant app-entry by itself.
- Verify UI copy contains the required business messaging.
