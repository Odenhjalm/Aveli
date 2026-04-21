# COURSE FAMILY ORDER DAG SUMMARY

## STATUS

READY

This DAG is derived from verified repository retrieval and contract comparison.
It is a repair-and-preservation plan for canonical course family and course
position implementation.

## SOURCE CONTRACTS

- [SYSTEM_LAWS.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/SYSTEM_LAWS.md)
- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
- [course_lesson_editor_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_lesson_editor_contract.md)
- [course_access_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_access_contract.md)
- [course_monetization_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [commerce_membership_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/commerce_membership_contract.md)

## CANONICAL OWNER CHECK

Canonical ownership is not ambiguous.

- `AVELI_COURSE_DOMAIN_SPEC.md` owns family and order meaning, invariants,
  transitions, and forbidden states
- `course_lesson_editor_contract.md` owns studio/editor transport surfaces only
- `course_public_surface_contract.md` and `learner_public_edge_contract.md`
  consume response fields only
- `course_access_contract.md` explicitly forbids `group_position` as access
  authority
- `course_monetization_contract.md` and
  `commerce_membership_contract.md` explicitly keep bundles, orders, payments,
  and memberships separate from family/order truth

No conflicting contract owner was found inside `actual_truth/contracts/`.

## VERIFIED DIFF SUMMARY

### CORRECT

- `CFA-01` contract ownership is singular and fail-closed
- `CFA-03` bundle ordering already proves contiguous-trigger patterns belong to
  commerce snapshots only, not course-family truth
- `CFA-04` backend and API payload names already use `course_group_id` and
  `group_position`
- access and commerce contracts already block family/order authority leakage

### MISSING

- `CFA-02` append-only baseline enforcement for contiguous `0..(n-1)` course
  family ordering
- `CFA-05` backend create, reorder, and cross-family move orchestration with
  deterministic sibling shifting
- `CFA-06` backend delete-collapse behavior for remaining family positions
- `CFA-08` studio update authoring for family move/reorder
- `CFA-10` regression coverage for create, move, reorder, delete, and invalid
  state rejection

### NON-CANONICAL

- `CFA-07` studio create forces singleton families via fresh UUID plus
  `group_position = 0`
- `CFA-08` studio save path omits family/order fields entirely
- `CFA-09` learner course rendering hardcodes `step1/step2/step3`
- `CFA-10` `backend/tests/test_api_smoke.py` still creates a new family at
  `group_position = 1`

### PRESERVE

- public and access payloads already expose `course_group_id`,
  `group_position`, and `required_enrollment_source` without using `step`
- `frontend/lib/features/courses/data/courses_repository.dart` already rejects
  legacy `step`

## TASK LIST

1. [CFO-000_BASELINE_FAMILY_ORDER_FOUNDATION.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-000_BASELINE_FAMILY_ORDER_FOUNDATION.md)
2. [CFO-001_BASELINE_REPLAY_FAMILY_ORDER_GATE.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-001_BASELINE_REPLAY_FAMILY_ORDER_GATE.md)
3. [CFO-002_BACKEND_FAMILY_TRANSITION_FOUNDATION.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-002_BACKEND_FAMILY_TRANSITION_FOUNDATION.md)
4. [CFO-003_STUDIO_API_FAMILY_POSITION_ALIGNMENT.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-003_STUDIO_API_FAMILY_POSITION_ALIGNMENT.md)
5. [CFO-004_STUDIO_EDITOR_FAMILY_POSITION_AUTHORING.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-004_STUDIO_EDITOR_FAMILY_POSITION_AUTHORING.md)
6. [CFO-005_FRONTEND_RENDER_PROGRESSIVE_FAMILY_ALIGNMENT.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-005_FRONTEND_RENDER_PROGRESSIVE_FAMILY_ALIGNMENT.md)
7. [CFO-006_VERIFICATION_AND_REGRESSION_GATE.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-006_VERIFICATION_AND_REGRESSION_GATE.md)
8. [CFO-007_FINAL_GO_GATE.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-007_FINAL_GO_GATE.md)

## DEPENDENCY GRAPH

- `CFO-000 -> CFO-001`
- `CFO-001 -> CFO-002`
- `CFO-002 -> CFO-003`
- `CFO-003 -> CFO-004`
- `CFO-003 -> CFO-005`
- `CFO-001 -> CFO-006`
- `CFO-002 -> CFO-006`
- `CFO-003 -> CFO-006`
- `CFO-004 -> CFO-006`
- `CFO-005 -> CFO-006`
- `CFO-006 -> CFO-007`

## TOPOLOGICAL ORDER

1. `CFO-000_BASELINE_FAMILY_ORDER_FOUNDATION`
2. `CFO-001_BASELINE_REPLAY_FAMILY_ORDER_GATE`
3. `CFO-002_BACKEND_FAMILY_TRANSITION_FOUNDATION`
4. `CFO-003_STUDIO_API_FAMILY_POSITION_ALIGNMENT`
5. `CFO-004_STUDIO_EDITOR_FAMILY_POSITION_AUTHORING`
6. `CFO-005_FRONTEND_RENDER_PROGRESSIVE_FAMILY_ALIGNMENT`
7. `CFO-006_VERIFICATION_AND_REGRESSION_GATE`
8. `CFO-007_FINAL_GO_GATE`

## DAG VALIDITY

This DAG is valid.

- baseline enforcement is first
- backend transaction logic depends on baseline truth
- studio/editor work depends on backend-stable transitions
- learner/render alignment is delayed until canonical payload semantics are
  stable
- regression work executes only after all owner tasks complete
- final go/no-go evaluation executes last

No cycle was introduced.
No task depends on a later task.
No second authority owner is introduced.

