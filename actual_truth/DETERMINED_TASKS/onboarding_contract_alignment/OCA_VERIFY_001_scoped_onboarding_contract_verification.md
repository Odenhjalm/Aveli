## TASK ID
OCA-VERIFY-001

## TITLE
Scoped onboarding contract verification

## TYPE
VERIFICATION

## PURPOSE
Dependency role: GATE.

Verify that the scoped onboarding contract alignment is complete after implementation and tests. This is the final check for the small onboarding drift set only.

## DEPENDS_ON
[OCA-TEST-001]

## TARGET SURFACES
- `actual_truth/contracts/onboarding_contract.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `backend/app/routes/auth.py`
- `backend/app/routes/entry_state.py`
- `backend/app/routes/profiles.py`
- `backend/app/main.py`
- `backend/tests/test_onboarding_state.py`
- `backend/tests/test_route_inventory_entry_authority.py`
- `backend/tests/test_unmounted_surface_guardrails.py`
- `frontend/lib/core/routing/app_router.dart`
- `frontend/lib/core/routing/route_session.dart`
- `frontend/lib/features/onboarding/`
- `frontend/test/routing/app_router_test.dart`
- `frontend/test/widgets/router_bootstrap_test.dart`

## EXPECTED RESULT
- Backend completion guard requires profile name before onboarding completion.
- Backend completion guard does not require bio or profile image.
- Backend completion guard does not grant entry; entry remains governed by `/entry-state`.
- Frontend routes onboarding-needed users to profile before welcome when name is missing.
- Frontend routes onboarding-needed users to welcome when name is present.
- Welcome does not own profile validation.
- Welcome uses exact CTA `Jag förstår hur Aveli fungerar`.
- Welcome may use light presentational pacing only, such as subtle reveal, slight CTA activation delay, scroll framing, visual emphasis, or soft success feedback.
- Presentational pacing does not add a gate, extra click, mandatory scroll, mandatory intro-course choice, mandatory bio, mandatory profile image, or replacement for canonical completion logic.
- The intro course remains optional UX only.
- Home remains post-entry and not part of onboarding.
- Payment remains before profile for non-invite users.
- Invite users skip payment but still require profile and welcome before completion.
- `/community` remains unmounted in backend runtime unless a separate canonical contract explicitly reactivates it.
- Frontend `/community` remains app-entry gated by route auth and must not become a pre-entry onboarding surface.
- No new onboarding states were added.
- No contract files were changed.

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
rg -n "Fortsätt|profileRepositoryProvider|TextField|displayName:|bio:" frontend/lib/features/onboarding/welcome_page.dart
rg -n "community\.router|include_router\(community" backend/app/main.py
```

Expected source-check interpretation:
- The scoped `rg` check against `welcome_page.dart` must not show the old completion CTA, profile repository usage, welcome-owned profile inputs, display-name update payload, or bio update payload.
- The scoped `rg` check against `backend/app/main.py` must return no mounted community router evidence.
