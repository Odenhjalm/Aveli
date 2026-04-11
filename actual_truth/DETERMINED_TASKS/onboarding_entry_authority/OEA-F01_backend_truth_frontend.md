## TASK ID

OEA-F01

## TITLE

PHASE_F_FRONTEND_ENFORCEMENT - Replace Frontend Entry State With Backend Truth

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Replace frontend-local entry inference with backend-owned canonical entry truth.

## DEPENDS_ON

- OEA-A02
- OEA-D02
- OEA-E04

## TARGET SURFACES

- `frontend/lib/core/auth/auth_controller.dart`
- `frontend/lib/core/routing/route_session.dart`
- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/api/auth_repository.dart`
- `frontend/lib/gate.dart`

## EXPECTED RESULT

Frontend route gating reflects the backend entry-state response and never computes entry from profile, token, role, or admin data.

## INVARIANTS

- Frontend MUST NEVER infer entry from profile.
- Frontend MUST NEVER infer entry from token.
- Frontend MUST NEVER infer entry from role/admin.
- Frontend MUST only reflect backend entry truth.
- Missing or failed backend entry-state read MUST deny app-entry.

## VERIFICATION

- Verify profile hydration without backend entry truth cannot enter app routes.
- Verify stored token without backend entry truth cannot enter app routes.
- Verify role/admin metadata without backend entry truth cannot enter app routes.
