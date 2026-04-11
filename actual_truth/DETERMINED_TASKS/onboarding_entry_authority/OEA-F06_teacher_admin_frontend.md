## TASK ID

OEA-F06

## TITLE

PHASE_F_FRONTEND_ENFORCEMENT - Frontend Teacher/Admin From Backend Truth

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Ensure teacher/admin frontend routing reflects backend authority and cannot infer role/admin entry locally.

## DEPENDS_ON

- OEA-F01
- OEA-B04

## TARGET SURFACES

- `frontend/lib/core/routing/route_manifest.dart`
- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/domain/models/user_access.dart`
- `frontend/lib/features/studio/*`
- `frontend/lib/features/community/presentation/admin_page.dart`

## EXPECTED RESULT

Teacher/admin routes require backend-confirmed app-entry and backend-confirmed role/admin authorization.

## INVARIANTS

- Frontend MUST NEVER infer teacher/admin entry from local metadata.
- Frontend MUST NEVER use role/admin to bypass onboarding or membership.
- Teacher/admin route access MUST reflect backend truth only.
- No frontend role/admin state may grant membership authority.

## VERIFICATION

- Verify teacher route with backend entry false is denied.
- Verify admin route with backend entry false is denied.
- Verify role/admin UI availability updates only after backend truth refresh.
