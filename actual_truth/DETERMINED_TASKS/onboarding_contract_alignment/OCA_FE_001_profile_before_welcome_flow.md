## TASK ID
OCA-FE-001

## TITLE
Frontend profile-before-welcome flow

## TYPE
FRONTEND_ALIGNMENT

## PURPOSE
Dependency role: OWNER.

Align frontend onboarding order with the locked flow:

- non-invite user: checkout -> profile -> welcome -> continue -> onboarding_complete -> home
- invite user: invite -> profile -> welcome -> continue -> onboarding_complete -> home

The frontend may use profile data only to choose the pre-entry onboarding UX step. It must not infer app-entry authority from profile data; app entry remains owned by `/entry-state`.

Onboarding UX tempo law:
- The profile step must feel light, guided, and intentional.
- It must not feel heavy, blocked, or effortful.
- Any pacing is presentational only and must not create an entry gate, add confirmation steps, or make optional fields mandatory.

Current evidence:
- `frontend/lib/core/routing/app_router.dart` sends `needsOnboarding` users directly to `RoutePath.welcome`.
- `_onboardingPreEntryPaths` currently allows `RoutePath.welcome` and `RoutePath.courseIntro`, but not `RoutePath.createProfile`.
- `RoutePath.createProfile` exists but currently builds the full community `ProfilePage`.
- The full community `ProfilePage` contains post-entry profile/community/subscription surfaces and must not become the pre-entry onboarding profile step.
- `frontend/lib/features/onboarding/welcome_page.dart` currently carries profile fields and profile validation, which belongs before welcome.

## DEPENDS_ON
[]

## TARGET SURFACES
- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/core/routing/route_session.dart`
- `frontend/lib/core/routing/route_manifest.dart`
- `frontend/lib/core/routing/route_paths.dart`
- `frontend/lib/core/routing/app_routes.dart`
- `frontend/lib/features/onboarding/`
- `frontend/lib/data/repositories/profile_repository.dart`
- `frontend/test/routing/app_router_test.dart`
- `frontend/test/widgets/router_bootstrap_test.dart`

## EXPECTED RESULT
- Add a lightweight onboarding profile step under `frontend/lib/features/onboarding/` and mount it at `RoutePath.createProfile` / `AppRoute.createProfile`.
- The onboarding profile step requires a non-empty display name before continuing.
- The onboarding profile step allows bio to be empty.
- The onboarding profile step treats profile image as optional and does not require image upload or image presence.
- The onboarding profile step may use soft progression feedback after profile save, but must not add extra clicks beyond saving the required name and continuing to welcome.
- The onboarding profile step updates the existing profile via the canonical profile projection endpoint used by `ProfileRepository.updateMe`.
- After successful profile save and session/profile hydration, the onboarding profile step routes to `RoutePath.welcome`.
- `RouteSessionSnapshot` may expose a derived `hasProfileName` value from `authState.profile?.displayName`, but `canEnterApp` and `isAuthenticated` must remain derived only from `entryState.canEnterApp`.
- `AppRouterNotifier` must route `needsOnboarding && !hasProfileName` to `RoutePath.createProfile`.
- `AppRouterNotifier` must route `needsOnboarding && hasProfileName` to `RoutePath.welcome`.
- `_onboardingPreEntryPaths` must include `RoutePath.createProfile` without making `/profile` or home part of onboarding.
- `RoutePath.courseIntro` remains optional UX only and must not become an entry gate.
- Both invited and non-invited users use the same profile-before-welcome logic; do not branch on invite status except for existing payment behavior.
- Do not create new onboarding states.
- Do not move payment after welcome.
- Do not change entry law or make profile data an app-entry authority.

## VERIFICATION
Verification checks:
- Frontend routing test: `needsOnboarding` with missing/blank profile name redirects private routes to `RoutePath.createProfile`.
- Frontend routing test: `needsOnboarding` with non-empty profile name redirects private routes to `RoutePath.welcome`.
- Frontend routing test: `needsPayment` still redirects to `RoutePath.subscribe`.
- Frontend routing test: `canEnterApp` still redirects pre-entry routes to `RoutePath.home`.
- Frontend widget test: the onboarding profile step blocks empty display name.
- Frontend widget test: the onboarding profile step allows empty bio.
- Frontend widget test or source check: the onboarding profile step does not require profile image and does not add an extra confirmation step after name save.
- Source check: no code path uses profile data to set `canEnterApp` or `isAuthenticated`.
