# CFO-006 VERIFICATION AND REGRESSION GATE

- TYPE: `GATE`
- GROUP: `VERIFY + GATE`
- DEPENDS_ON:
  - `CFO-001`
  - `CFO-002`
  - `CFO-003`
  - `CFO-004`
  - `CFO-005`

## Problem Statement

The current repository has coverage for course field presence and access
separation, but it does not yet verify the locked family-order transition model
end to end.

Implementation must not proceed to closure until regression coverage proves the
new baseline, backend, studio, and rendering behavior all align to the same
canonical owner.

## Contract References

- [SYSTEM_LAWS.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/SYSTEM_LAWS.md)
  - `4. Cross-Domain Determinism Law`
  - `5. No-Fallback And Stop Law`
- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
  - `7. PROGRESSION MODEL`
  - `11. FORBIDDEN PATTERNS`
  - `12. FAILURE MODEL`
- [course_access_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_access_contract.md)
  - `4. PROTECTED COURSE-ACCESS LAW`
- [course_lesson_editor_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_lesson_editor_contract.md)
  - `11. FRONTEND ALIGNMENT TARGET`

## Audit Inputs

- `CFA-01`
- `CFA-02`
- `CFA-04`
- `CFA-05`
- `CFA-06`
- `CFA-07`
- `CFA-08`
- `CFA-09`
- `CFA-10`

## Target Files

- `backend/tests/test_baseline_v2_course_family_ordering_contract.py`
- `backend/tests/test_course_family_transition_service.py`
- `backend/tests/test_courses_studio.py`
- `backend/tests/test_api_smoke.py`
- `backend/tests/test_course_access_authority.py`
- `backend/tests/test_course_detail_view_contract.py`
- `frontend/test/unit/studio_repository_course_create_test.dart`
- `frontend/test/widgets/studio_course_family_position_authoring_test.dart`
- `frontend/test/unit/course_journey_layout_test.dart`
- `frontend/test/widgets/course_catalog_journey_layout_test.dart`
- `frontend/test/widgets/courses_showcase_section_order_test.dart`

## Expected Outcome

- regression coverage exists for:
  - new-family create at `0`
  - create-into-existing-family shift
  - same-family reorder
  - cross-family move
  - delete collapse
  - `group_position` non-authority for access
  - studio payload correctness
  - frontend rendering of general family order
- tests no longer encode pre-contract invalid behavior

## Verification Requirement

- baseline-backed tests prove contiguous family order
- API tests prove canonical studio surfaces expose deterministic errors and
  success states
- frontend tests prove both authoring and rendering use backend-authored family
  data only
- contract tests continue to reject legacy `step`

## Go Condition

- all owner tasks complete and expose stable canonical behavior
- no remaining major drift exists in baseline, backend, studio, or learner
  render surfaces

## Blocked Condition

- blocked if any transition remains untestable through canonical surfaces
- blocked if any test still canonizes `step1/step2/step3` or singleton-family
  assumptions
- blocked if access tests regress into `group_position`-based gating

## Out Of Scope

- unrelated commerce flows
- unrelated lesson/media authority work

