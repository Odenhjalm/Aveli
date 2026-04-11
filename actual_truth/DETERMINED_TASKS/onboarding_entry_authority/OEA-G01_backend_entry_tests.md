## TASK ID

OEA-G01

## TITLE

PHASE_G_VERIFICATION - Backend Entry Law Tests

## TYPE

TEST_ALIGNMENT

## PURPOSE

Add regression coverage for canonical backend app-entry law.

## DEPENDS_ON

- OEA-B03
- OEA-B04
- OEA-D01
- OEA-C05
- OEA-E01

## TARGET SURFACES

- `backend/tests/*`
- `backend/app/auth.py`
- `backend/app/permissions.py`
- `backend/app/routes/*`

## EXPECTED RESULT

Backend tests prove app-entry requires completed onboarding and active membership.

## INVARIANTS

- No app-entry without completed onboarding.
- No app-entry without active membership.
- Only `active` or `canceled` with future `expires_at` grants entry.
- Teacher/admin cannot bypass canonical entry law.
- Invite membership without onboarding completion cannot enter.

## VERIFICATION

- Run backend tests covering missing membership, inactive, past_due, expired, unknown, canceled past, canceled future, active, and invite membership.
- Verify app-entry routes deny auth-only users.
- Verify teacher/admin users fail until entry law is true.
