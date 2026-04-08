# AOI-004 ONBOARDING COMPLETION ROUTE ALIGNMENT

TYPE: `OWNER`  
TASK_TYPE: `BACKEND_ALIGNMENT`  
DEPENDS_ON: `["AOI-001", "AOI-003"]`

## Goal

Implement the single canonical onboarding-completion surface.

## Required Outputs

- `POST /auth/onboarding/complete`
- explicit-action completion only
- success shape `{ "status": "completed", "onboarding_state": "completed", "token_refresh_required": true }`
- writes only `app.auth_subjects.onboarding_state`
- no profile-derived completion path

## Forbidden

- mutating onboarding state through `PATCH /profiles/me`
- implicit completion from verification, membership, referral, or webhook state
- issuing refreshed tokens directly from the completion route

## Exit Criteria

- incomplete-to-completed is owned only by the canonical route
- completed-to-completed is idempotent success
- auth-context refresh remains the responsibility of subsequent `POST /auth/refresh`
