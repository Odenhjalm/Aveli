## TASK ID

OEA-D02

## TITLE

PHASE_D_ONBOARDING_IMPLEMENTATION - Expose Backend-Owned Entry State

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Expose exactly one backend-owned pre-entry read surface for frontend routing truth, separate from profile projection and token claims.

## DEPENDS_ON

- OEA-D01
- OEA-B02

## TARGET SURFACES

- `backend/app/routes/auth.py`
- `backend/app/auth.py`
- `backend/app/schemas/*`
- `backend/app/repositories/auth_subjects.py`
- `backend/app/repositories/memberships.py`

## EXPECTED RESULT

Frontend can query backend-owned entry truth without using `/profiles/me`, JWT claims, role/admin metadata, or local route state as authority.

## INVARIANTS

- The entry-state surface MUST report whether canonical app-entry is allowed.
- The entry-state surface MUST use the same single backend entry evaluator as app-entry routes.
- The entry-state surface MUST NOT duplicate business logic outside the canonical backend entry evaluator.
- The entry-state surface MUST NOT expose profile projection as authority.
- Missing or ambiguous state MUST report no entry.

## VERIFICATION

- Verify entry-state output denies missing membership, inactive membership, unknown membership status, and incomplete onboarding.
- Verify entry-state output allows only completed onboarding plus active membership.
- Verify `/profiles/me` is not used for entry-state truth.
