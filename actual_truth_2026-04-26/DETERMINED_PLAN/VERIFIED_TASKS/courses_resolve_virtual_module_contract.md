## TASK ID

courses_resolve_virtual_module_contract

---

## PROBLEM

- Current runtime still exposes `_virtual_module()` in `backend/app/routes/courses.py`
- Course and lesson traversal still preserve a module-based compatibility contract even though the target canonical structure is now direct course -> lessons
- The task is no longer a documentation-only alignment pass; it requires architectural removal of module abstraction from active traversal
- Equivalent evidence expected in: `backend/app/routes/courses.py`, `backend/app/repositories/courses.py`, `backend/app/services/courses_service.py`, `docs/README.md`, `frontend/lib/features/courses/presentation/course_page.dart`, `frontend/lib/features/courses/presentation/lesson_page.dart`

---

## SYSTEM DECISION

- This task is explicitly reclassified as `architecture_change`
- Canonical traversal target is: `course -> lessons (direct)`
- `_virtual_module()` and module-based traversal are no longer preserved contracts for this task
- Architecture work MUST remove module abstraction from active course and lesson traversal without redesigning unrelated course access rules

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open source files:
  `backend/app/routes/courses.py`, `backend/app/repositories/courses.py`, `backend/app/services/courses_service.py`, `docs/README.md`, `frontend/lib/features/courses/presentation/course_page.dart`, `frontend/lib/features/courses/presentation/lesson_page.dart`

- Identify every active runtime dependency on module-based traversal and every place where course -> lessons direct traversal must replace it

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected contract MUST:

- define direct course -> lessons traversal as the canonical structure
- remove virtual-module dependencies from active traversal
- preserve current course access and lesson access behavior
- NOT retain module-based payload requirements in the canonical contract

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- define the canonical direct traversal payloads for course and lesson reads
- identify lessons as belonging directly to a course
- remove module abstraction from active contract language

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected contract MUST:

- match the new direct traversal architecture introduced by this task
- NOT preserve `_virtual_module()` or module-based traversal as active truth
- NOT rely on persisted-module assumptions as the canonical model

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF docs and runtime disagree:

- prefer the new direct course -> lessons architecture defined in this task
- keep historical module model only as deprecated background context

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Remove module abstraction from active course and lesson traversal surfaces
- Define and implement the canonical direct structure:
  - `course`
  - `lessons`
- Update active client and documentation surfaces to follow the direct structure

#### STEP 3B — Adapter rules

Architecture update MUST:

- remove `_virtual_module()` from active traversal
- remove module-based contract requirements from course and lesson payload interpretation
- NOT change course access logic
- NOT introduce new module storage semantics
- NOT preserve module abstraction as compatibility truth

#### STEP 3C — Request/response passthrough

- Course and lesson traversal MUST become direct
- Active clients MUST no longer depend on module abstraction for navigation or gating
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- module abstraction cannot be removed without forbidden schema work
- direct course -> lessons traversal cannot be proven end-to-end
- client contract remains ambiguous after source inspection

→ STOP

---

## DO NOT

- preserve `_virtual_module()`
- maintain module-based contract
- modify access logic
- introduce new module persistence
- modify database schema

---

## VERIFICATION

After change:

- course and lesson traversal use direct `course -> lessons` structure
- no active traversal depends on `_virtual_module()` or module-based contract
- client expectations match the direct course -> lessons model

---

## STOP CONDITIONS

- task requires database schema modification
- direct traversal cannot replace module abstraction safely
- client contract is ambiguous

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

architecture_change

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Architectural reclassification
- Canonical target is direct `course -> lessons` traversal
