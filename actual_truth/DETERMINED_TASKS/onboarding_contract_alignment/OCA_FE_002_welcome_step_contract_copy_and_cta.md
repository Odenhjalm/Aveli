## TASK ID
OCA-FE-002

## TITLE
Welcome step responsibility and CTA alignment

## TYPE
FRONTEND_ALIGNMENT

## PURPOSE
Dependency role: OWNER.

Align the welcome step with the onboarding contract and locked product decisions:

- welcome is after profile
- welcome does not own profile validation
- intro course selection is optional
- continuing from welcome is the explicit onboarding completion moment
- the completion CTA is exactly `Jag förstår hur Aveli fungerar`
- onboarding UX should feel light, guided, and intentional
- welcome may use presentational pacing only: subtle content reveal/fade-in, slight CTA activation delay, scroll-based information framing, visual emphasis on membership/course information, or soft success/progression feedback

Current evidence:
- `frontend/lib/features/onboarding/welcome_page.dart` owns display-name and bio text controllers.
- `welcome_page.dart` blocks completion when bio is empty, although bio is optional.
- `welcome_page.dart` sends `displayName: null` when the name field is empty.
- `welcome_page.dart` uses the CTA `Fortsätt`, not the contract CTA.
- `welcome_page.dart` already offers an intro course, and that selection is UX-only.

## DEPENDS_ON
[OCA-FE-001]

## TARGET SURFACES
- `frontend/lib/features/onboarding/welcome_page.dart`
- `frontend/lib/features/courses/presentation/course_intro_page.dart`
- `frontend/lib/features/courses/presentation/course_intro_redirect_page.dart`
- `frontend/lib/core/routing/app_router.dart`
- `frontend/test/widgets/router_bootstrap_test.dart`
- `frontend/test/routing/app_router_test.dart`

## EXPECTED RESULT
- Remove profile editing fields and profile update calls from `WelcomePage`.
- Remove the bio-required validation from `WelcomePage`.
- Remove display-name null submission from `WelcomePage`.
- Keep profile name only as read-only greeting input after the profile step has completed.
- Welcome copy greets the user as `Välkommen till Aveli <name>` when a profile name exists.
- Welcome copy explains that introduction courses are released monthly and that each lesson is released weekly.
- Welcome copy explains that the user may optionally choose an intro course.
- Welcome copy explains that the user may optionally choose the whole education bundle for step one, step two, and step three and get every introduction course released at once.
- The intro course selection remains optional UX only and must not affect entry.
- Welcome may introduce a slight CTA activation delay or subtle content reveal, but this must remain presentational only.
- The completion button text is exactly `Jag förstår hur Aveli fungerar`.
- Pressing the completion CTA calls the existing canonical onboarding completion path through `AuthController.completeWelcome`.
- Pressing the completion CTA does not update profile fields.
- Presentational pacing must not delay or replace canonical onboarding completion logic after the defined CTA is activated.
- Presentational pacing must not require additional clicks, confirmation steps, mandatory scrolling, mandatory course selection, mandatory bio, or mandatory profile image.
- Home remains post-entry only and must not be part of onboarding.
- Do not add new onboarding states.

## VERIFICATION
Verification checks:
- Widget test: `WelcomePage` renders `Jag förstår hur Aveli fungerar`.
- Widget test: `WelcomePage` does not render display-name or bio input fields.
- Widget test: pressing `Jag förstår hur Aveli fungerar` calls the auth completion path without requiring bio.
- Widget test: any CTA delay is finite, presentational, and does not require an extra click or confirmation step once active.
- Widget test or source check: `WelcomePage` no longer imports or reads `profileRepositoryProvider`.
- Routing test: opening intro course from welcome does not grant app entry and remains allowed only while `needsOnboarding` is true.
- Source check: `WelcomePage` does not make intro-course selection, bio, profile image, scrolling, or a second confirmation mandatory.
- Source check: no `Fortsätt` CTA remains in `frontend/lib/features/onboarding/welcome_page.dart`.
