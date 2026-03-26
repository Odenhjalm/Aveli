## TASK ID

courses_resolve_virtual_module_contract

---

## PROBLEM

- Course docs and import mental model still imply persisted modules as the primary runtime structure
- Current runtime uses `_virtual_module()` in `backend/app/routes/courses.py` because lessons now belong directly to courses
- Equivalent evidence expected in: `backend/app/routes/courses.py`, `backend/app/repositories/courses.py`, `backend/app/services/courses_service.py`, `docs/README.md`, `frontend/lib/features/courses/presentation/course_page.dart`, `frontend/lib/features/courses/presentation/lesson_page.dart`

---

## SYSTEM DECISION

- Existing runtime behavior is canonical until explicitly redesigned
- No new course business logic is allowed
- Documentation must describe current runtime structure accurately

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open source files:
  `backend/app/routes/courses.py`, `backend/app/repositories/courses.py`, `backend/app/services/courses_service.py`, `docs/README.md`, `frontend/lib/features/courses/presentation/course_page.dart`, `frontend/lib/features/courses/presentation/lesson_page.dart`

- Identify the exact runtime contract for course -> module -> lesson traversal

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected contract MUST:

- describe the current virtual-module runtime accurately
- preserve current course and lesson behavior
- NOT reintroduce persisted-module assumptions without proof

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be markdown contract output
- identify the virtual-module compatibility layer explicitly
- describe how clients should interpret module and lesson data today

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected contract MUST:

- match current runtime code
- NOT describe obsolete persisted-module behavior as active truth
- NOT require schema redesign in this task

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF docs and runtime disagree:

- prefer current runtime code
- keep historical module model only as background context

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create updated course-structure contract artifacts describing the virtual-module runtime

#### STEP 3B — Adapter rules

Contract update MUST:

- preserve current API behavior
- NOT change course access logic
- NOT add new module storage semantics

#### STEP 3C — Request/response passthrough

- Current course and lesson payloads MUST remain unchanged
- Virtual-module behavior MUST be described unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- current virtual-module behavior cannot be proven
- docs require schema redesign to become accurate
- client contract is ambiguous

→ STOP

---

## DO NOT

- redesign the course schema
- modify access logic
- introduce new module persistence
- change frontend runtime behavior

---

## VERIFICATION

After change:

- course docs describe the virtual-module runtime accurately
- client expectations match current course/lesson traversal
- no persisted-module assumptions remain in active contract docs

---

## STOP CONDITIONS

- virtual-module runtime cannot be proven
- task requires schema redesign
- client contract is ambiguous

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

courses / contract_alignment

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Documentation and contract task
- Current runtime remains canonical
