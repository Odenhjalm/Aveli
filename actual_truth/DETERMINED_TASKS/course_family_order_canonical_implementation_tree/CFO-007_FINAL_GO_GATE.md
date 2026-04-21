# CFO-007 FINAL GO GATE

- TYPE: `AGGREGATE`
- GROUP: `FINAL GATE`
- DEPENDS_ON:
  - `CFO-006`

## Problem Statement

The task tree is only execution-ready if the final aggregate audit can confirm
that canonical ownership stayed singular and every required layer now aligns to
the locked contract.

## Contract References

- [SYSTEM_LAWS.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/SYSTEM_LAWS.md)
  - `1. Contract Authority Law`
  - `4. Cross-Domain Determinism Law`
  - `5. No-Fallback And Stop Law`
- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
  - `Final assertion`
- [course_access_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_access_contract.md)
  - `4. PROTECTED COURSE-ACCESS LAW`
- [course_monetization_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_monetization_contract.md)
  - `6. COURSE BUNDLE DOMAIN`
- [commerce_membership_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/commerce_membership_contract.md)
  - `7. COURSE BUNDLES DOMAIN`

## Audit Inputs

- `CFA-01`
- `CFA-02`
- `CFA-03`
- `CFA-04`
- `CFA-05`
- `CFA-06`
- `CFA-07`
- `CFA-08`
- `CFA-09`
- `CFA-10`

## Target Files

- `actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/task_manifest.json`
- `backend/supabase/baseline_v2_slots/*`
- `backend/app/routes/studio.py`
- `backend/app/services/courses_service.py`
- `backend/app/repositories/courses.py`
- `frontend/lib/features/studio/*`
- `frontend/lib/features/courses/*`
- `backend/tests/*`
- `frontend/test/*`

## Expected Outcome

- one canonical owner remains:
  - `course family = app.courses.course_group_id`
  - `course position = app.courses.group_position`
- baseline, backend, API, studio UI, and learner render all consume that owner
  without introducing aliases
- access and commerce boundaries still reject family/order leakage
- implementation is ready for execute-mode work

## Verification Requirement

- rerun scoped contract diff against the targeted surfaces only
- confirm no surviving `step` authority or bundle-as-family behavior
- confirm no surviving singleton-family hardcoding in studio create
- confirm regression coverage exists for all contract-required transitions

## Go Condition

- `CFO-006` passes completely
- no unresolved drift remains in the scoped family/order surfaces

## Blocked Condition

- blocked if any second owner, alias owner, or fallback owner survives
- blocked if any contract-required transition still lacks deterministic
  implementation or deterministic regression coverage

## Out Of Scope

- unrelated course commerce work
- unrelated media/runtime work

