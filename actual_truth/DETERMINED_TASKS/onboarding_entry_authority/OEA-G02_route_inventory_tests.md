## TASK ID

OEA-G02

## TITLE

PHASE_G_VERIFICATION - Route Inventory Dependency Tests

## TYPE

TEST_ALIGNMENT

## PURPOSE

Add route inventory tests that prevent app-entry routes from using non-canonical dependencies.

## DEPENDS_ON

- OEA-B03
- OEA-B04
- OEA-B05
- OEA-B06

## TARGET SURFACES

- `backend/tests/*`
- `backend/app/main.py`
- `backend/app/routes/*`
- `backend/app/auth.py`
- `backend/app/permissions.py`

## EXPECTED RESULT

Any new app-entry route that uses `CurrentUser`, `TeacherUser`, `AdminUser`, or `OptionalCurrentUser` as its entry guard fails tests.

## INVARIANTS

- No app-entry route may use `CurrentUser`.
- No app-entry route may use `TeacherUser`.
- No app-entry route may use `AdminUser`.
- No app-entry route may use `OptionalCurrentUser`.
- Every app-entry route MUST depend on the single canonical app-entry dependency.

## VERIFICATION

- Run route inventory tests against mounted routers.
- Verify public, auth, webhook, payment-return, and diagnostic exceptions are explicitly listed.
- Verify test failure message identifies the route and dependency violation.
