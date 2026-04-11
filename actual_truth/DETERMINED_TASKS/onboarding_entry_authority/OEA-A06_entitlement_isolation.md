## TASK ID

OEA-A06

## TITLE

PHASE_A_DRIFT_REMOVAL - Isolate Legacy Entitlement Authority

## TYPE

LEGACY_REMOVAL

## PURPOSE

Ensure legacy `app.entitlements` and entitlement service logic cannot act as global app-entry authority or protected course-access authority.

## DEPENDS_ON

- OEA-A01

## TARGET SURFACES

- `backend/app/services/entitlement_service.py`
- `backend/app/services/*`
- `backend/app/routes/*`
- `backend/app/repositories/*`

## EXPECTED RESULT

Legacy entitlement code is removed, quarantined, or proven unreachable from active runtime authority paths.

## INVARIANTS

- `app.entitlements` MUST NEVER grant global app-entry.
- `app.entitlements` MUST NEVER grant protected course access.
- Protected course access MUST remain governed by `app.course_enrollments`.
- No fallback access path may compensate for missing canonical enrollment or membership authority.

## VERIFICATION

- Verify no mounted route imports or invokes entitlement service logic for access.
- Verify protected lesson access does not consult `app.entitlements`.
- Verify regression coverage fails if entitlement access is reintroduced.
