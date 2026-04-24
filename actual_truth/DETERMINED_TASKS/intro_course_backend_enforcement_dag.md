# INTRO COURSE BACKEND ENFORCEMENT DAG

## 1. EXECUTIVE VERDICT

Status: GENERATED.

This is a backend-first deterministic DAG for materializing the intro-course selection and progression contract into executable implementation work.
This tree does not implement code.
This tree does not allow frontend work before backend authority is complete.

## 2. NO-CODE AUDIT OF EXISTING PLAN

- No existing intro-course backend enforcement DAG or `ICE-*` task set exists in `actual_truth/DETERMINED_TASKS/`.
- The current backend enforcement plan already identifies the correct implementation lanes:
  - lesson completion authority
  - selection lock enforcement
  - drip worker completion
  - intro selection read model
  - classification hardening
  - aggregate validation
  - frontend cleanup
- The prompt's minimum dependency seeds do not fully enforce the required stage order because `ICE-005`, `ICE-008`, and `ICE-014` would otherwise be root-capable.
- This DAG tightens those dependencies so execution is locked to:
  - COMPLETION
  - SELECTION LOCK
  - DRIP
  - READ MODEL
  - CLASSIFICATION
  - AGGREGATE
  - FRONTEND

## 3. DETERMINISTIC TASK TREE

### GROUP 1 - COMPLETION AUTHORITY (BLOCKING)

#### ICE-001
- ID: ICE-001
- TYPE: OWNER
- DESCRIPTION: Create the backend repository for canonical lesson completion over `app.lesson_completions`.
- DEPENDS ON: []
- OUTPUT: A backend repository exists for canonical lesson completion create/read operations, and app-layer completion persistence is isolated to this surface.

#### ICE-002
- ID: ICE-002
- TYPE: OWNER
- DESCRIPTION: Create the backend lesson completion service enforcing valid lesson access before completion and no duplicate completion.
- DEPENDS ON: [ICE-001]
- OUTPUT: A canonical service exists that validates lesson access, rejects duplicate completion, and emits typed backend completion outcomes.

#### ICE-003
- ID: ICE-003
- TYPE: OWNER
- DESCRIPTION: Add `POST /courses/lessons/{lesson_id}/complete` as a backend-only completion route using the canonical service only.
- DEPENDS ON: [ICE-002]
- OUTPUT: A mounted learner completion route exists and completion writes can occur only through the canonical service.

#### ICE-004
- ID: ICE-004
- TYPE: GATE
- DESCRIPTION: Add completion tests proving completion requires valid access and persists correctly.
- DEPENDS ON: [ICE-003]
- OUTPUT: Source tests exist covering access-required completion, duplicate rejection, and canonical persistence.

### GROUP 2 - SELECTION LOCK ENFORCEMENT

#### ICE-005
- ID: ICE-005
- TYPE: OWNER
- DESCRIPTION: Map canonical SQL intro-selection failures into typed backend domain errors with stable internal reasons.
- DEPENDS ON: [ICE-004]
- OUTPUT: Backend error translation exists for at least `incomplete_drip` and `incomplete_completion` intro-selection failures.

#### ICE-006
- ID: ICE-006
- TYPE: OWNER
- DESCRIPTION: Map intro-selection domain errors to deterministic HTTP `409` responses with stable reason codes while preserving non-selection access denials.
- DEPENDS ON: [ICE-005]
- OUTPUT: Intro enrollment routes return stable `409` denial payloads for selection lock and preserve `403` for purchase-required or app-entry denial paths.

#### ICE-007
- ID: ICE-007
- TYPE: GATE
- DESCRIPTION: Add selection-lock tests proving incomplete drip denies selection and incomplete completion denies selection.
- DEPENDS ON: [ICE-006]
- OUTPUT: Source tests exist covering both intro-selection lock branches and their stable denial reasons.

### GROUP 3 - DRIP WORKER COMPLETION (CRITICAL)

#### ICE-008
- ID: ICE-008
- TYPE: OWNER
- DESCRIPTION: Extend the drip worker so canonical advancement covers all drip modes, not only `drip_enabled = true`.
- DEPENDS ON: [ICE-007]
- OUTPUT: Worker candidate selection covers legacy uniform drip and custom lesson-offset drip, while immediate-access mode remains a no-op.

#### ICE-009
- ID: ICE-009
- TYPE: OWNER
- DESCRIPTION: Implement backend-only final-lesson auto-completion after canonical final unlock plus the 7-day window.
- DEPENDS ON: [ICE-008]
- OUTPUT: A backend-only auto-completion path exists that writes canonical `auto_final_lesson` completions after final unlock and waiting-window satisfaction.

#### ICE-010
- ID: ICE-010
- TYPE: GATE
- DESCRIPTION: Add worker tests proving custom offsets progress correctly and final lesson auto-completes correctly.
- DEPENDS ON: [ICE-009]
- OUTPUT: Source tests exist covering custom-offset progression and final-lesson auto-completion behavior.

### GROUP 4 - INTRO SELECTION STATE (READ MODEL ONLY)

#### ICE-011
- ID: ICE-011
- TYPE: AGGREGATE
- DESCRIPTION: Create the intro selection service computing `selection_locked`, `selection_lock_reason`, and `eligible_courses` from canonical enrollments, drip state, and completion state only.
- DEPENDS ON: [ICE-004, ICE-010]
- OUTPUT: A backend read-model service exists that derives intro-selection state without frontend inference and without any active-intro-course abstraction.

#### ICE-012
- ID: ICE-012
- TYPE: OWNER
- DESCRIPTION: Add `GET /courses/intro/selection-state` as the backend-authoritative intro selection state route.
- DEPENDS ON: [ICE-011]
- OUTPUT: A mounted route exists returning backend-authored intro selection state only.

#### ICE-013
- ID: ICE-013
- TYPE: AGGREGATE
- DESCRIPTION: Extend course access responses with backend-authored `is_intro_course` and `selection_locked` fields.
- DEPENDS ON: [ICE-011]
- OUTPUT: Course access responses project intro classification and selection lock from backend authority only.

### GROUP 5 - CLASSIFICATION HARDENING

#### ICE-014
- ID: ICE-014
- TYPE: OWNER
- DESCRIPTION: Remove non-canonical intro classification from backend-authoritative surfaces. Eliminate `group_position` usage and implicit `enrollable` classification from backend helpers, read models, and route-facing response logic.
- DEPENDS ON: [ICE-012, ICE-013]
- OUTPUT: Backend-authoritative intro classification uses only `required_enrollment_source`, and backend no longer exposes classification logic that depends on `group_position` or implicit `enrollable` inference.

#### ICE-015
- ID: ICE-015
- TYPE: GATE
- DESCRIPTION: Add classification tests proving only `required_enrollment_source` is used for intro classification.
- DEPENDS ON: [ICE-014]
- OUTPUT: Source tests exist proving intro classification ignores `group_position`, price, naming, tags, and implicit enrollability.

### GROUP 6 - AGGREGATE VALIDATION

#### ICE-016
- ID: ICE-016
- TYPE: GATE
- DESCRIPTION: Add the full contract integration test covering intro selection, drip progression, lesson completion, and selection unlock.
- DEPENDS ON: [ICE-004, ICE-007, ICE-010, ICE-013, ICE-015]
- OUTPUT: An integration test exists proving the full backend-controlled intro lifecycle from initial selection to next-selection unlock.

#### ICE-017
- ID: ICE-017
- TYPE: AGGREGATE
- DESCRIPTION: Perform final aggregate verification proving all intro-course rules are enforced in backend and no frontend authority is required.
- DEPENDS ON: [ICE-016]
- OUTPUT: A final verification artifact exists proving backend-first authority completion and blocking frontend shortcut execution before signoff.

### GROUP 7 - FRONTEND (BLOCKED UNTIL COMPLETE)

#### ICE-018
- ID: ICE-018
- TYPE: OWNER
- DESCRIPTION: Remove frontend intro inference and local progress storage after backend authority completion.
- DEPENDS ON: [ICE-017]
- OUTPUT: Frontend no longer infers intro status, selection eligibility, active course, or progression from local state, and becomes a pure render/input-dispatch layer over backend authority.

## 4. DAG VALIDATION

- Roots: ICE-001
- Terminal node: ICE-018
- Critical stage gates:
  - ICE-004 -> ICE-005
  - ICE-007 -> ICE-008
  - ICE-012, ICE-013 -> ICE-014
  - ICE-017 -> ICE-018
- Topologically valid order:
  1. ICE-001
  2. ICE-002
  3. ICE-003
  4. ICE-004
  5. ICE-005
  6. ICE-006
  7. ICE-007
  8. ICE-008
  9. ICE-009
  10. ICE-010
  11. ICE-011
  12. ICE-012
  13. ICE-013
  14. ICE-014
  15. ICE-015
  16. ICE-016
  17. ICE-017
  18. ICE-018
- No dependency points forward to a later prerequisite.
- No cycles exist.
- No frontend task is reachable before final backend aggregate verification succeeds.

## 5. STOP CONDITIONS

- STOP if any task introduces an active intro course abstraction.
- STOP if intro behavior is derived from `group_position`, price, naming, tags, `enrollable`, or any non-canonical field.
- STOP if selection, progression, access, or classification logic is delegated to frontend.
- STOP if new backend authority is introduced outside enrollment, drip, or lesson completion.
