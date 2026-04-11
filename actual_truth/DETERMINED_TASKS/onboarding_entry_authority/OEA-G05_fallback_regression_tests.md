## TASK ID

OEA-G05

## TITLE

PHASE_G_VERIFICATION - Forbidden Fallback Regression Tests

## TYPE

TEST_ALIGNMENT

## PURPOSE

Add regression tests for forbidden fallback and legacy paths discovered in the diff audit.

## DEPENDS_ON

- OEA-A04
- OEA-A05
- OEA-A06
- OEA-A07
- OEA-G01

## TARGET SURFACES

- `backend/tests/*`
- `backend/app/services/subscription_service.py`
- `backend/app/services/entitlement_service.py`
- `backend/app/repositories/referrals.py`
- `backend/app/routes/api_events.py`

## EXPECTED RESULT

Tests fail if legacy entitlements, route-local event authority, missing-table referral fallback, unknown-as-active membership, or payment fallback reappear as authority.

## INVARIANTS

- No fallback authority path may exist.
- Unknown membership MUST deny entry.
- Missing referral authority table MUST fail closed.
- Legacy entitlement logic MUST NOT grant app-entry or protected course access.
- Route-local event checks MUST NOT grant global app-entry.

## VERIFICATION

- Run regression tests for each forbidden fallback.
- Verify tests identify exact fallback surface on failure.
- Verify no test normalizes a fallback path as accepted behavior.
