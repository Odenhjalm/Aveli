## TASK ID

OEA-C03

## TITLE

PHASE_C_BASELINE_ALIGNMENT - Add Membership Fail-Closed Constraints

## TYPE

BASELINE_SLOT

## PURPOSE

Add or verify baseline protections that make `app.memberships` fail closed for app-entry authority.

## DEPENDS_ON

- OEA-C01
- OEA-A05
- OEA-A08

## TARGET SURFACES

- `backend/supabase/baseline_slots/0013_memberships_core.sql`
- `backend/supabase/baseline_slots/0026_canonical_app_memberships_authority.sql`
- `backend/supabase/baseline_slots/*`
- `backend/app/repositories/memberships.py`

## EXPECTED RESULT

`app.memberships` supports canonical active states, `source = 'invite'`, required invite expiry, and fail-closed interpretation of all unsupported states.

## INVARIANTS

- Only `active` grants entry without expiry comparison.
- `canceled` grants entry only when `expires_at > now`.
- Missing, unknown, inactive, past_due, expired, and canceled without future `expires_at` MUST deny.
- Invite-created memberships MUST use `source = 'invite'` and MUST set `expires_at`.
- Baseline constraints MUST NOT create fallback authority.

## VERIFICATION

- Verify clean replay enforces supported membership status/source shape.
- Verify invite membership rows require `expires_at`.
- Verify unknown status cannot become app-entry active.
