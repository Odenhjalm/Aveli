## TASK ID

editor_finish_preview_contract_alignment

---

## PROBLEM

- Preview directionally follows the student-render contract, but preview hydration is still page-coupled and intertwined with editor-local concerns
- Architecture plan expects preview to derive from canonical markdown through the same student-render contract
- Equivalent handler expected in: `docs/architecture/aveli_editor_architecture_v2.md`, `frontend/lib/features/studio/presentation/course_editor_page.dart`, `frontend/lib/features/studio/presentation/lesson_media_preview.dart`, `frontend/lib/features/studio/presentation/lesson_media_preview_cache.dart`, `frontend/lib/features/studio/presentation/lesson_media_preview_hydration.dart`, `frontend/lib/shared/utils/lesson_content_pipeline.dart`

---

## SYSTEM DECISION

- Canonical markdown remains the single source of truth
- Preview must follow student-render semantics
- No new persistence model is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open source files:
  `docs/architecture/aveli_editor_architecture_v2.md`, `frontend/lib/features/studio/presentation/course_editor_page.dart`, `frontend/lib/features/studio/presentation/lesson_media_preview.dart`, `frontend/lib/features/studio/presentation/lesson_media_preview_cache.dart`, `frontend/lib/features/studio/presentation/lesson_media_preview_hydration.dart`, `frontend/lib/shared/utils/lesson_content_pipeline.dart`

- Identify where preview logic is still page-owned instead of contract-owned

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected preview contract MUST:

- derive from canonical markdown
- match student-render semantics
- NOT depend on page-local editor state as long-term truth

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- define the preview contract boundary explicitly
- define canonical markdown as preview input
- preserve current preview outputs needed by Studio

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected preview contract MUST:

- be deterministic
- preserve current saved-content behavior
- NOT require schema changes

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple preview boundaries exist:

- prefer the student-render contract
- avoid retaining page-owned preview rules as long-term truth

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create explicit preview contract boundary derived from canonical markdown

#### STEP 3B — Adapter rules

Preview alignment MUST:

- reuse existing student-render semantics
- NOT duplicate render logic
- NOT treat editor-local state as persisted truth

#### STEP 3C — Request/response passthrough

- Canonical markdown MUST pass into preview unchanged
- Preview outputs MUST remain usable by Studio
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- preview contract cannot be isolated
- student-render semantics are unclear
- extraction requires persistence-model change

→ STOP

---

## DO NOT

- persist preview state as truth
- change lesson storage format
- duplicate student-render logic
- modify backend schemas

---

## VERIFICATION

After change:

- preview is explicitly derived from canonical markdown
- preview semantics match student rendering
- page-local preview ownership is reduced

---

## STOP CONDITIONS

- preview contract cannot be isolated
- student-render semantics are unclear
- extraction requires persistence change

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

editor / preview_alignment

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `editor_extract_session_orchestration`

---

## NOTES

- Architecture extraction task
- Student-render semantics remain canonical
