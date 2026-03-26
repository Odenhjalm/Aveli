## TASK ID

editor_extract_session_orchestration

---

## PROBLEM

- Session identity exists, but orchestration still lives mainly inside `course_editor_page.dart`
- Architecture plan expects dedicated session-owned orchestration instead of page-owned async safety
- Equivalent handler expected in: `docs/architecture/aveli_editor_architecture_v2.md`, `frontend/lib/features/studio/presentation/course_editor_page.dart`, `frontend/lib/editor/session/editor_session.dart`, `frontend/lib/editor/session/editor_operation_controller.dart`

---

## SYSTEM DECISION

- Canonical markdown remains the single source of truth
- Existing editor behavior is canonical until explicitly refactored
- No new persistence model is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open source files:
  `docs/architecture/aveli_editor_architecture_v2.md`, `frontend/lib/features/studio/presentation/course_editor_page.dart`, `frontend/lib/editor/session/editor_session.dart`, `frontend/lib/editor/session/editor_operation_controller.dart`

- Identify which page-local responsibilities should move into session orchestration

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected orchestration layer MUST:

- own session identity, revision safety, and async guards
- preserve current editor behavior
- NOT split orchestration across multiple competing controllers

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- define the dedicated session-orchestration boundary
- define which responsibilities leave the page widget
- preserve current session/revision semantics

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected orchestration layer MUST:

- be deterministic
- preserve current saved-content behavior
- NOT require schema changes

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple extraction approaches exist:

- prefer the session-owned boundary implied by the architecture plan
- avoid keeping `course_editor_page.dart` as the long-term orchestration owner

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create dedicated editor-session orchestration boundary outside `course_editor_page.dart`

#### STEP 3B — Adapter rules

New orchestration layer MUST:

- own async safety and session lifecycle
- NOT duplicate mutation-pipeline logic
- NOT change persistence format

#### STEP 3C — Request/response passthrough

- Existing session identity and revision semantics MUST remain unchanged
- Page-level inputs MUST pass through unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- responsibilities cannot be isolated from the page widget
- extraction requires persistence-model change
- session ownership is unclear

→ STOP

---

## DO NOT

- persist editor-local state as truth
- change lesson storage format
- redesign editor UI wholesale
- modify backend schemas

---

## VERIFICATION

After change:

- session lifecycle is owned outside the page widget
- page-local orchestration burden is reduced
- current session/revision semantics remain intact

---

## STOP CONDITIONS

- responsibilities cannot be isolated
- extraction requires persistence change
- session ownership is ambiguous

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

editor / session_alignment

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `editor_extract_mutation_pipeline`

---

## NOTES

- Architecture extraction task
- Session semantics remain canonical
