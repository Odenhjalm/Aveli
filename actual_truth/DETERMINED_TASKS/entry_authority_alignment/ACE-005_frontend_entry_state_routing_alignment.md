## TASK_ID
ACE-005

## TYPE
FRONTEND_ALIGNMENT

## DEPENDS_ON
- ACE-004

## GOAL
Gor frontendens routing helt beroende av `GET /entry-state` och ta bort `/profiles/me` som routing- eller bootstrap-input.

## EXACT CHANGES REQUIRED
- Uppdatera `frontend/lib/domain/models/entry_state.dart` sa att modellen matchar kontraktet och tar bort `isInvite`.
- Uppdatera entry-state parsing och konsumtion for nya falt: `onboarding_state`, `role_v2`, `role`, `is_admin`.
- Uppdatera `frontend/lib/core/routing/route_session.dart` sa routing inte anvander `profileDisplayName` eller annan profile-data for beslut.
- Uppdatera `frontend/lib/core/routing/app_router.dart` sa pre-entry routing endast bygger pa entry-state.
- Uppdatera `frontend/lib/core/auth/auth_controller.dart` sa `/entry-state` hamtas utan att `/profiles/me` kravs for routing.

## ACCEPTANCE CRITERIA
- Routing beslutas utan `profileDisplayName` eller annan `/profiles/me` data.
- Frontend anvander `GET /entry-state` som enda routing-authority.
- `EntryState` modellen matchar kontraktets faltlista och saknar forbjudna falt.

## VERIFICATION STEPS
- Inspektera `frontend/lib/core/routing/route_session.dart` och `frontend/lib/core/routing/app_router.dart` for att bevisa att inga profil-falt deltar i routing.
- Inspektera `frontend/lib/domain/models/entry_state.dart` och verifiera att den matchar kontraktet.
- Inspektera `frontend/lib/core/auth/auth_controller.dart` och verifiera att routing inte blockeras av `/profiles/me`.
