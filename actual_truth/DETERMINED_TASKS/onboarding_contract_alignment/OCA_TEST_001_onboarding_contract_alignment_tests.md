## TASK ID
OCA-TEST-001

## TITLE
Onboarding contract alignment tests

## TYPE
TEST_ALIGNMENT

## PURPOSE
Dependency role: GATE.

Add focused regression coverage for the remaining onboarding contract drift after backend and frontend alignment tasks are implemented.

This task must not broaden scope into payment redesign, home onboarding, entry-law changes, Stripe redesign, intro-course gating, or community reactivation.

This task must also protect the onboarding UX tempo law: onboarding may use light presentational pacing, but pacing must not become a new gate or extra required action.

## DEPENDS_ON
[OCA-BE-001, OCA-FE-001, OCA-FE-002]

## TARGET SURFACES
- `backend/tests/test_onboarding_state.py`
- `backend/tests/test_entry_state.py`
- `backend/tests/test_route_inventory_entry_authority.py`
- `backend/tests/test_unmounted_surface_guardrails.py`
- `frontend/test/routing/app_router_test.dart`
- `frontend/test/widgets/router_bootstrap_test.dart`
- `frontend/test/unit/auth_controller_test.dart`
- Any new focused frontend widget test file under `frontend/test/`

## EXPECTED RESULT
- Backend tests prove onboarding completion fails with `409 profile_name_required` when profile name is null, missing, or whitespace-only.
- Backend tests prove failed completion does not mutate `onboarding_state`.
- Backend tests prove failed completion does not record `onboarding_completed`.
- Backend tests prove completion succeeds when profile name is present and bio is null.
- Backend tests preserve existing checks that register, login, payment, invite, referral, profile update, and email verification do not complete onboarding.
- Frontend routing tests cover both invite and non-invite onboarding-needed users:
  - missing profile name -> `RoutePath.createProfile`
  - present profile name -> `RoutePath.welcome`
  - completed entry -> `RoutePath.home`
  - payment needed -> `RoutePath.subscribe`
- Frontend tests prove bio is optional in the onboarding profile step.
- Frontend tests prove profile image is optional in the onboarding profile step.
- Frontend tests prove the welcome CTA text is exactly `Jag förstår hur Aveli fungerar`.
- Frontend tests prove `WelcomePage` no longer performs profile validation or profile update.
- Frontend tests prove any welcome CTA activation delay or content reveal is presentational only and does not require extra clicks, mandatory scrolling, mandatory intro-course choice, mandatory bio, or mandatory profile image.
- Existing community guardrail tests continue to prove `/community` is not mounted in backend runtime.
- No tests should assert that home is part of onboarding.
- No tests should make intro course selection mandatory.
- No tests should encode a new entry gate based on pacing, animation completion, scroll completion, intro-course selection, bio, or profile image.

## VERIFICATION
MCP BOOTSTRAP BLOCK (required before backend runtime verification):

1. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ops/mcp_bootstrap_gate.ps1
```

2. If the gate does not return `MCP_BOOTSTRAP_GATE_OK`, STOP.
3. Report the failing checks clearly.
4. Do not proceed into MCP-backed audits, backend verification, local backend testing, implementation, or verification while the gate is failing.
5. If the gate returns `MCP_BOOTSTRAP_GATE_OK`, report `MCP_BOOTSTRAP: PASS` and continue with the task-scoped workflow.

Verification commands:

```powershell
.\.venv\Scripts\python.exe -m pytest backend/tests/test_onboarding_state.py backend/tests/test_entry_state.py backend/tests/test_route_inventory_entry_authority.py backend/tests/test_unmounted_surface_guardrails.py
flutter test frontend/test/routing/app_router_test.dart frontend/test/widgets/router_bootstrap_test.dart frontend/test/unit/auth_controller_test.dart
```

If a new frontend widget test file is added for onboarding profile or welcome behavior, include it in the scoped `flutter test` command.
