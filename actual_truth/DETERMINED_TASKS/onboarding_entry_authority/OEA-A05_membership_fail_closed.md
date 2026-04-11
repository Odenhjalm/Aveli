## TASK ID

OEA-A05

## TITLE

PHASE_A_DRIFT_REMOVAL - Remove Fail-Open Membership Status Handling

## TYPE

LEGACY_REMOVAL

## PURPOSE

Remove or isolate membership interpretation paths that can treat unknown, missing, invalid, or fallback state as active access.

## DEPENDS_ON

- OEA-A01

## TARGET SURFACES

- `backend/app/services/subscription_service.py`
- `backend/app/utils/membership_status.py`
- `backend/app/repositories/memberships.py`
- `backend/app/services/membership_grant_service.py`

## EXPECTED RESULT

Only `status = 'active'` or `status = 'canceled' AND expires_at > now` can grant global app-entry.

## INVARIANTS

- Unknown membership status MUST NEVER resolve to active.
- Missing membership MUST NEVER allow app-entry.
- Fallback payment state MUST NEVER grant membership authority.
- Missing, inactive, past_due, expired, and canceled without future `expires_at` MUST deny entry.
- Stripe checkout success MUST NEVER grant app-entry unless canonical `app.memberships` state is active under the entry law.

## VERIFICATION

- Verify all non-active statuses deny app-entry.
- Verify unknown status denies app-entry.
- Verify fallback payment intent state cannot produce active app-entry authority.
