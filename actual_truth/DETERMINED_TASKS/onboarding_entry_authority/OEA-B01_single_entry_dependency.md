## TASK ID

OEA-B01

## TITLE

PHASE_B_ENTRY_ENFORCEMENT - Create Single Backend App-Entry Dependency

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Introduce one mandatory backend dependency for global app-entry. This dependency must enforce identity, canonical auth subject, completed onboarding, and active membership.

## DEPENDS_ON

- OEA-A01
- OEA-A02
- OEA-A03
- OEA-A04
- OEA-A05
- OEA-A06
- OEA-A07
- OEA-A08

## TARGET SURFACES

- `backend/app/auth.py`
- `backend/app/permissions.py`
- `backend/app/repositories/auth_subjects.py`
- `backend/app/repositories/memberships.py`
- `backend/app/utils/membership_status.py`

## EXPECTED RESULT

A single enforced backend dependency exists for app-entry. It is non-optional and is the only way for app-entry routes to authorize global entry.

## INVARIANTS

- App-entry MUST require valid identity, `app.auth_subjects.onboarding_state = 'completed'`, and active membership.
- Active membership MUST mean only `status = 'active'` or `status = 'canceled' AND expires_at > now`.
- Missing, unknown, inactive, past_due, expired, or canceled without future `expires_at` MUST deny entry.
- The dependency MUST NOT be duplicated.
- The dependency MUST NOT be optional.
- `CurrentUser`, `TeacherUser`, and `AdminUser` MUST NOT grant app-entry.

## VERIFICATION

- Verify one canonical app-entry dependency exists.
- Verify unit tests cover all membership status outcomes.
- Verify auth-only identity does not satisfy app-entry.
