## TASK ID

OEA-A03

## TITLE

PHASE_A_DRIFT_REMOVAL - Remove Role/Admin Entry Authority

## TYPE

LEGACY_REMOVAL

## PURPOSE

Remove teacher role and admin flag as alternative global app-entry authorities.

## DEPENDS_ON

- OEA-A01

## TARGET SURFACES

- `backend/app/permissions.py`
- `backend/app/models.py`
- `backend/app/routes/admin.py`
- `backend/app/routes/studio.py`
- `backend/app/routes/course_bundles.py`
- `backend/app/routes/api_notifications.py`
- `frontend/lib/core/routing/route_manifest.dart`
- `frontend/lib/domain/models/user_access.dart`

## EXPECTED RESULT

Teacher/admin checks become secondary permission checks that run only after canonical app-entry is satisfied for app-entry routes.

## INVARIANTS

- Role/admin MUST NEVER grant global app-entry.
- Teacher/admin routes that are app-entry routes MUST depend on canonical entry enforcement before role/admin evaluation.
- Frontend teacher/admin metadata MUST NEVER override backend authority.
- No app-entry route may depend on `TeacherUser` or `AdminUser` as its only guard.

## VERIFICATION

- Verify teacher/admin users without completed onboarding and active membership cannot enter app-entry routes.
- Verify role/admin checks are not membership authority.
- Verify frontend teacher/admin routes reflect backend truth only.
