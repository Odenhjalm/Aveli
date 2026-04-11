## TASK ID

OEA-A01

## TITLE

PHASE_A_DRIFT_REMOVAL - Freeze App-Entry Surface Classification

## TYPE

CONTRACT_ALIGNMENT

## PURPOSE

Classify every mounted backend route and frontend route in scope as public, auth-entry, pre-entry, global app-entry, protected course access, payment-return, webhook, or diagnostic.

## DEPENDS_ON

[]

## TARGET SURFACES

- `backend/app/main.py`
- `backend/app/routes/*`
- `frontend/lib/core/routing/*`
- `actual_truth/contracts/onboarding_entry_authority_contract.md`

## EXPECTED RESULT

Every route in scope has exactly one classification. Routes classified as global app-entry are the only routes that later tasks migrate to canonical app-entry enforcement.

## INVARIANTS

- App-entry MUST require `app.auth_subjects.onboarding_state = 'completed'` and active membership in `app.memberships`.
- Public, auth-entry, payment-return, webhook, and diagnostic routes MUST NEVER be treated as global app-entry proof.
- No fallback authority path may be introduced by classification.
- Profile, token, role, admin, course enrollment, event participation, invite token, and referral link MUST NEVER become global app-entry authority.

## VERIFICATION

- Verify every router mounted in `backend/app/main.py` is represented.
- Verify every frontend route in `frontend/lib/core/routing/route_manifest.dart` is represented.
- Verify no route is unclassified or multiply classified.
