## TASK ID

OEA-A04

## TITLE

PHASE_A_DRIFT_REMOVAL - Isolate Route-Local Authority Drift

## TYPE

LEGACY_REMOVAL

## PURPOSE

Isolate route-local access logic, especially event visibility and participation checks, so it cannot act as global app-entry authority.

## DEPENDS_ON

- OEA-A01

## TARGET SURFACES

- `backend/app/routes/api_events.py`
- `backend/app/routes/api_notifications.py`
- `backend/app/repositories/memberships.py`
- `backend/app/utils/membership_status.py`

## EXPECTED RESULT

Members-only event checks remain local feature gates only. Public, host, participant, admin, or event membership logic cannot grant global app-entry.

## INVARIANTS

- Route-local membership checks MUST NEVER replace canonical app-entry enforcement.
- Event host, participant, public visibility, teacher, or admin status MUST NEVER grant global app-entry.
- App-entry MUST require completed onboarding and active membership before any app-entry event route can proceed.
- No fallback authority path may be introduced through event route exceptions.

## VERIFICATION

- Verify event-local checks are evaluated only after canonical entry where the route is app-entry.
- Verify event participation cannot bypass membership or onboarding entry law.
- Verify local event membership logic is not reused as global entry logic.
