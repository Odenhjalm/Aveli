## TASK ID

OEA-A02

## TITLE

PHASE_A_DRIFT_REMOVAL - Remove Profile Hydration Entry Authority

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Remove profile hydration, `/profiles/me` success, and `gate.allow()` as app-entry authority.

## DEPENDS_ON

- OEA-A01

## TARGET SURFACES

- `frontend/lib/core/auth/auth_controller.dart`
- `frontend/lib/gate.dart`
- `frontend/lib/core/routing/route_session.dart`
- `frontend/lib/api/auth_repository.dart`
- `backend/app/routes/profiles.py`

## EXPECTED RESULT

Profile data remains projection only. Frontend session state may hold a profile but must not infer app-entry from it.

## INVARIANTS

- Frontend MUST NEVER infer app-entry from profile presence.
- Frontend MUST NEVER infer app-entry from `/profiles/me` success.
- Frontend MUST NEVER infer app-entry from token presence.
- App-entry MUST require backend-owned canonical entry truth.
- Profile projection MUST NEVER become identity, onboarding, membership, role, admin, or course-access authority.

## VERIFICATION

- Verify `profile != null` no longer evaluates as app-entry.
- Verify `gate.allow()` is not called from profile hydration alone.
- Verify `/profiles/me` is projection only, not global entry.
