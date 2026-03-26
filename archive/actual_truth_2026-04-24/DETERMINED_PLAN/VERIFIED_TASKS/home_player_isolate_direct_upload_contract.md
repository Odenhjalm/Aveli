## TASK ID

home_player_isolate_direct_upload_contract

---

## PROBLEM

- `/home/audio` now exposes `runtime_media_id`, but direct Home uploads still populate `lesson_id` and `course_id` with `runtime_media.id` so they fit a lesson-shaped feed schema
- `backend/app/schemas/__init__.py` and `frontend/lib/features/home/data/home_audio_repository.dart` still require lesson/course context for every Home item, even when the source is a teacher-library upload
- Equivalent handler expected in: `backend/app/repositories/courses.py`, `backend/app/services/courses_service.py`, `backend/app/schemas/__init__.py`, `frontend/lib/features/home/data/home_audio_repository.dart`, `frontend/lib/features/home/presentation/home_dashboard_page.dart`, `media_control_plane_phase2_design.md`, `runtime_media_reference_design.md`

---

## SYSTEM DECISION

- Media authority = control_plane
- `runtime_media_id` is the public identity layer
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route and contract source files:
  `backend/app/repositories/courses.py`, `backend/app/services/courses_service.py`, `backend/app/schemas/__init__.py`, `frontend/lib/features/home/data/home_audio_repository.dart`, `frontend/lib/features/home/presentation/home_dashboard_page.dart`, `media_control_plane_phase2_design.md`, `runtime_media_reference_design.md`

- Identify every field where direct Home uploads still reuse synthetic lesson/course context

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected Home contract MUST:

- preserve `runtime_media_id` as the canonical public identity
- keep genuine course/lesson context only for course-linked items
- NOT require fake course_id / lesson_id placeholders for teacher-library uploads

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON and/or markdown contract output
- preserve current display and playability metadata
- distinguish direct Home uploads from course-linked items without synthetic lesson/course ids

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected Home contract MUST:

- be deterministic
- NOT require placeholder course or lesson ids for direct uploads
- NOT reintroduce asset or object ids as public runtime identifiers

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple Home feed shapes are possible:

- prefer the smallest contract that keeps `runtime_media_id`, playability metadata, and genuine course context unchanged
- fallback only to an explicitly documented optional-context shape already supported by the current UI

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create isolated Home feed contract for:
  GET `/home/audio`

#### STEP 3B — Adapter rules

New Home contract MUST:

- reuse existing runtime projection logic directly
- NOT duplicate playback or curation logic
- NOT invent fake lesson/course placeholders for direct teacher-library uploads

#### STEP 3C — Request/response passthrough

- `runtime_media_id` MUST remain unchanged
- genuine course-linked context MUST remain unchanged
- playability metadata MUST remain unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- frontend Home UI depends on placeholder lesson/course ids
- direct uploads cannot be represented without inventing new business logic
- contract isolation requires new runtime authority rules

→ STOP

---

## DO NOT

- change playback authorization
- redesign Home curation rules
- introduce new public media identities
- modify storage or runtime_media semantics

---

## VERIFICATION

After change:

- direct Home uploads no longer masquerade as lesson/course items
- frontend contract distinguishes course-linked items from teacher-library items deterministically
- `runtime_media_id` remains the canonical public id

---

## STOP CONDITIONS

- current Home UI depends on placeholder lesson/course ids
- contract isolation requires new business logic
- canonical `runtime_media_id` cannot remain unchanged

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

home_player / contract_isolation

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `playback_converge_runtime_identity`

---

## NOTES

- Contract isolation task
- Teacher-library items must not impersonate course content
