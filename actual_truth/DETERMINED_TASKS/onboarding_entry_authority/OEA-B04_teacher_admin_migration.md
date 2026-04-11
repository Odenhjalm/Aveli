## TASK ID

OEA-B04

## TITLE

PHASE_B_ENTRY_ENFORCEMENT - Migrate Teacher/Admin Routes To Entry Plus Role

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Make teacher/admin routes require canonical app-entry first and then role/admin authority from `app.auth_subjects`.

## DEPENDS_ON

- OEA-B03

## TARGET SURFACES

- `backend/app/permissions.py`
- `backend/app/routes/admin.py`
- `backend/app/routes/studio.py`
- `backend/app/routes/course_bundles.py`
- `backend/app/routes/api_notifications.py`
- `backend/app/routes/api_events.py`

## EXPECTED RESULT

Teacher/admin routes use canonical entry plus role/admin checks. Role/admin can never replace entry.

## INVARIANTS

- Teacher/admin access MUST require canonical app-entry on app-entry routes.
- Role/admin checks MUST run only after canonical entry is satisfied.
- Role/admin MUST NEVER grant membership authority.
- Role/admin MUST NEVER complete onboarding.
- No app-entry route may depend directly on `TeacherUser` or `AdminUser`.

## VERIFICATION

- Verify teacher without completed onboarding is denied.
- Verify admin without active membership is denied.
- Verify teacher/admin role still gates teacher/admin actions after app-entry passes.
