## TASK ID
OCA-BE-001

## TITLE
Backend onboarding completion name guard

## TYPE
BACKEND_ALIGNMENT

## PURPOSE
Dependency role: OWNER.

Align the backend completion safety guard with `actual_truth/contracts/onboarding_contract.md`: onboarding may complete only when the user explicitly completes welcome and `profile.name` is present.

Current evidence:
- `backend/app/routes/auth.py` updates `app.auth_subjects.onboarding_state` in `_complete_onboarding_at_canonical_route`.
- `backend/app/routes/auth.py` calls `_complete_onboarding_at_canonical_route` from `complete_onboarding`.
- No name/display-name guard is applied before the completion update.
- `backend/app/auth.py` already hydrates `current_user["display_name"]` from the canonical profile projection at request time.

## DEPENDS_ON
[]

## TARGET SURFACES
- `backend/app/routes/auth.py`
- `backend/app/auth.py`
- `backend/app/routes/profiles.py`
- `backend/app/repositories/profiles.py`
- `backend/tests/test_onboarding_state.py`

## EXPECTED RESULT
- `POST /auth/onboarding/complete` verifies that the current profile name is present before changing `onboarding_state` to `completed`.
- The guard uses canonical profile projection data, not token claims, role, local state, payment, invite, referral, or email verification.
- A missing, null, or whitespace-only profile name blocks completion with `HTTP_409_CONFLICT` and detail `profile_name_required`.
- The guard runs before `_complete_onboarding_at_canonical_route` and before the `onboarding_completed` auth event is recorded.
- Existing successful behavior remains unchanged when a non-empty profile name is present.
- Idempotent completion remains valid for users who already have `onboarding_state = completed` and a non-empty profile name.
- Bio and profile image remain optional and must not be added as backend completion requirements.
- Payment, invite, referral, profile update, register, login, and email verification still must not complete onboarding.

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

Verification checks:
- Add or update backend tests through `OCA-TEST-001`.
- Confirm a user with `display_name = NULL` or whitespace cannot complete onboarding.
- Confirm blocked completion leaves `app.auth_subjects.onboarding_state = 'incomplete'`.
- Confirm blocked completion does not record an `onboarding_completed` auth event.
- Confirm a user with a non-empty profile name and no bio can complete onboarding.
- Confirm `backend/app/routes/auth.py` contains no completion path that bypasses the name guard.
