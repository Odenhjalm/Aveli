# CFO-001 BASELINE REPLAY FAMILY ORDER GATE

- TYPE: `GATE`
- GROUP: `BASELINE`
- DEPENDS_ON:
  - `CFO-000`

## Problem Statement

Baseline enforcement is not complete until replay and schema-dependent tests can
prove the new family-order substrate actually preserves the locked invariants
and transitions.

## Contract References

- [SYSTEM_LAWS.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/SYSTEM_LAWS.md)
  - `4. Cross-Domain Determinism Law`
  - `5. No-Fallback And Stop Law`
- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
  - `7. PROGRESSION MODEL`
  - `11. FORBIDDEN PATTERNS`
  - `12. FAILURE MODEL`

## Audit Inputs

- `CFA-02`
- `CFA-03`
- `CFA-10`

## Target Files

- `backend/tests/test_baseline_v2_course_family_ordering_contract.py`
- `backend/tests/test_api_smoke.py`

## Expected Outcome

- there is baseline-backed proof for:
  - new-family create only at `group_position = 0`
  - create-into-existing-family sibling shifting
  - same-family reorder contiguity
  - cross-family move source-collapse plus target-shift
  - middle delete collapse
  - rejection of duplicate, sparse, negative, or null family positions
- pre-contract drift in smoke coverage is removed

## Verification Requirement

- tests must run against clean baseline-backed schema, not mocked logic only
- at least one replay-backed failure case must prove a new family at
  `group_position = 1` is rejected
- at least one replay-backed success case must prove valid cross-family move is
  transactionally accepted

## Go Condition

- `CFO-000` lands with stable baseline substrate
- replay and tests can target canonical `app.courses` truth directly

## Blocked Condition

- blocked if baseline truth can only be verified through repository code
- blocked if smoke coverage preserves pre-contract invalid create semantics

## Out Of Scope

- studio route/controller changes
- frontend authoring changes

