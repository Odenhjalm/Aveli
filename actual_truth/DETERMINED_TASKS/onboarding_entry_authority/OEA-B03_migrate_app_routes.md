## TASK ID

OEA-B03

## TITLE

PHASE_B_ENTRY_ENFORCEMENT - Migrate All App-Entry Routes To Canonical Dependency

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Apply the single canonical app-entry dependency to every route classified as global app-entry.

## DEPENDS_ON

- OEA-B02

## TARGET SURFACES

- `backend/app/routes/profiles.py`
- `backend/app/routes/home.py`
- `backend/app/routes/courses.py`
- `backend/app/routes/course_bundles.py`
- `backend/app/routes/api_events.py`
- `backend/app/routes/api_notifications.py`
- `backend/app/routes/studio.py`
- `backend/app/routes/admin.py`

## EXPECTED RESULT

No app-entry route is guarded only by `CurrentUser`, `TeacherUser`, `AdminUser`, `OptionalCurrentUser`, profile reads, frontend state, route-local membership, or role/admin logic.

## INVARIANTS

- No app-entry route may use `CurrentUser`.
- No app-entry route may use `TeacherUser`.
- No app-entry route may use `AdminUser`.
- Every app-entry route MUST depend on the single canonical app-entry dependency.
- App-entry routes MUST fail closed when onboarding is incomplete or membership is not active.

## VERIFICATION

- Verify zero app-entry routes depend on `CurrentUser`, `TeacherUser`, or `AdminUser`.
- Verify auth-only, incomplete onboarding, missing membership, and inactive membership are denied.
- Verify public, auth, webhook, payment-return, and diagnostic routes are not accidentally migrated.
