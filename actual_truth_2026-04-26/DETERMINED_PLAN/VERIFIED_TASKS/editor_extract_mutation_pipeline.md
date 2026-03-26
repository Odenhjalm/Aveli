## TASK ID

editor_extract_mutation_pipeline

---

## PROBLEM

- Architecture plan explicitly names `editor_mutation_pipeline.dart`
- Current editor implementation has `EditorSession` and adapters, but no dedicated mutation-pipeline module
- Equivalent handler expected in: `docs/architecture/aveli_editor_architecture_v2.md`, `frontend/lib/features/studio/presentation/course_editor_page.dart`, `frontend/lib/editor/session/editor_session.dart`, `frontend/lib/editor/session/editor_operation_controller.dart`, `frontend/lib/editor/adapter/markdown_to_editor.dart`, `frontend/lib/editor/adapter/editor_to_markdown.dart`

---

## SYSTEM DECISION

- Canonical markdown remains the single source of truth
- Existing editor behavior is canonical until explicitly refactored
- No new editor persistence model is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open source files:
  `docs/architecture/aveli_editor_architecture_v2.md`, `frontend/lib/features/studio/presentation/course_editor_page.dart`, `frontend/lib/editor/session/editor_session.dart`, `frontend/lib/editor/session/editor_operation_controller.dart`, `frontend/lib/editor/adapter/markdown_to_editor.dart`, `frontend/lib/editor/adapter/editor_to_markdown.dart`

- Identify every page-local mutation path that the architecture expects the pipeline to own

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected mutation pipeline MUST:

- preserve canonical-markdown ownership
- centralize editor operations explicitly
- NOT reintroduce Quill delta as persisted truth

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- define the mutation pipeline module
- define supported operation types
- define how current page-local operations map into the pipeline

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected mutation pipeline MUST:

- be deterministic
- preserve current saved-content contract
- NOT require schema changes

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple extraction approaches exist:

- prefer the architecture document's named module boundary
- avoid introducing a second editor orchestration layer

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create module:
  `frontend/lib/editor/session/editor_mutation_pipeline.dart`

#### STEP 3B — Adapter rules

New module MUST:

- own explicit editor operations
- NOT change persistence format
- NOT duplicate adapter logic already present

#### STEP 3C — Request/response passthrough

- Existing canonical markdown inputs/outputs MUST remain unchanged
- Page-level callers MUST pass operation intent unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- page-local mutation paths cannot be isolated
- pipeline extraction requires persistence-model change
- operation ownership is unclear

→ STOP

---

## DO NOT

- persist Quill delta
- change lesson storage format
- redesign editor UI behavior wholesale
- modify backend schemas

---

## VERIFICATION

After change:

- explicit mutation pipeline module exists
- current operations are centralized through that module
- canonical markdown contract remains unchanged

---

## STOP CONDITIONS

- mutation paths cannot be isolated
- extraction requires persistence change
- operation ownership is ambiguous

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

editor / architecture_alignment

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Architecture extraction task
- Canonical markdown remains canonical
