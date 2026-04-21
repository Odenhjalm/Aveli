# COURSE FAMILY ORDER CANONICAL IMPLEMENTATION TREE

## STATUS

READY

This tree is the canonical generate-mode implementation plan for the locked
course family and course position model.

It is derived only from:

- [SYSTEM_LAWS.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/SYSTEM_LAWS.md)
- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
- [course_lesson_editor_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_lesson_editor_contract.md)
- [course_access_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_access_contract.md)
- [course_monetization_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [commerce_membership_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- verified repository retrieval from baseline, backend, frontend, and tests

This tree is not speculative.
Each task exists because the current repository was audited and found to be
either:

- already correct and needing preservation
- missing contract-required behavior
- non-canonical versus the locked contract
- test drift that must be replaced only after canonical behavior exists

## AUDIT METHOD

Repository retrieval was limited to the surfaces named by the task:

- `backend/supabase/baseline_v2_slots/*`
- `backend/app/schemas/__init__.py`
- `backend/app/routes/studio.py`
- `backend/app/routes/courses.py`
- `backend/app/routes/landing.py`
- `backend/app/services/courses_service.py`
- `backend/app/repositories/courses.py`
- `frontend/lib/features/studio/*`
- `frontend/lib/features/courses/*`
- `backend/tests/*`
- `frontend/test/*`

The audit checked only:

- canonical ownership
- baseline enforcement
- backend transition handling
- API payload alignment
- studio/editor authoring flows
- frontend rendering drift
- verification and regression coverage

## VERIFIED AUDIT IDS

- `CFA-01` canonical ownership is singular: `AVELI_COURSE_DOMAIN_SPEC.md` is the sole course-family and course-position authority; editor/public/access/commerce contracts only consume or constrain that authority
- `CFA-02` Baseline V2 currently enforces only `NOT NULL`, uniqueness, and `group_position >= 0` on `app.courses`; it does not enforce contiguous `0..(n-1)` family ordering or transition semantics
- `CFA-03` `app.bundle_order_courses` already has deferrable contiguous-order enforcement, but it is commerce-only and cannot be reused as course-family authority
- `CFA-04` studio schemas and routes already serialize and accept `course_group_id` and `group_position`
- `CFA-05` backend course create and update still write `course_group_id` and `group_position` directly with no canonical shift/collapse/move transaction logic
- `CFA-06` backend course delete still removes only the target row and does not collapse remaining family positions
- `CFA-07` studio create flow hardcodes a fresh `course_group_id` and `group_position = 0`, forcing singleton-family creation
- `CFA-08` studio save flow does not send `course_group_id` or `group_position`, so family move/reorder cannot be authored from UI
- `CFA-09` learner/frontend journey rendering still encodes `step1/step2/step3` slots and canonizes invalid duplicate positions instead of treating family order as general `group_position`
- `CFA-10` current tests cover field presence and access separation, but they do not cover contract-required family transitions; some tests still encode now-invalid behavior such as creating a new family at `group_position = 1`

## TASK CATEGORIES

- `BASELINE`
- `BACKEND SERVICE/REPOSITORY`
- `STUDIO API`
- `FRONTEND STUDIO`
- `FRONTEND RENDER`
- `VERIFY + GATE`
- `FINAL GATE`

## DAG ENTRYPOINT

Execution order and dependency graph are defined in:

- [DAG_SUMMARY.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/DAG_SUMMARY.md)

The DAG begins with
[CFO-000_BASELINE_FAMILY_ORDER_FOUNDATION.md](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/CFO-000_BASELINE_FAMILY_ORDER_FOUNDATION.md)
because every downstream transition depends on append-only baseline-backed family
ordering enforcement.

Machine-readable task metadata is defined in:

- [task_manifest.json](/C:/Users/Odenh/app/Aveli/actual_truth/DETERMINED_TASKS/course_family_order_canonical_implementation_tree/task_manifest.json)

