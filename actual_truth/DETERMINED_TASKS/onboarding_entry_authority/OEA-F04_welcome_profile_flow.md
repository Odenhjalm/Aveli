## TASK ID

OEA-F04

## TITLE

PHASE_F_FRONTEND_ENFORCEMENT - Welcome/Profile Completion Non-Authority

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Implement welcome/profile completion as onboarding UX without letting profile completion become entry authority.

## DEPENDS_ON

- OEA-F02

## TARGET SURFACES

- `frontend/lib/features/onboarding/welcome_page.dart`
- `frontend/lib/features/community/presentation/profile_page.dart`
- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/core/auth/auth_controller.dart`

## EXPECTED RESULT

Profile completion and welcome completion update their canonical domains and then rely on backend entry truth for routing.

## INVARIANTS

- Profile completion MUST NEVER grant app-entry.
- Welcome completion MUST NOT grant app-entry unless backend truth confirms completed onboarding plus active membership.
- Onboarding completion MUST remain separate from profile projection.
- Frontend MUST only reflect backend entry truth.

## VERIFICATION

- Verify profile save does not set entry.
- Verify welcome completion without active membership does not enter the app.
- Verify welcome completion with active membership refreshes backend entry truth.
