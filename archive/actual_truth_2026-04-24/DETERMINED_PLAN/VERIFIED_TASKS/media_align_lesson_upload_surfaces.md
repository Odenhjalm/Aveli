## TASK ID

media_align_lesson_upload_surfaces

---

## PROBLEM

- Lesson uploads still use: POST `/studio/lessons/{lesson_id}/media/presign`, POST `/studio/lessons/{lesson_id}/media/complete`
- Canonical pipeline already exists at: POST `/api/media/upload-url`, POST `/api/media/complete`, POST `/api/media/attach`
- Equivalent handler expected in: `backend/app/routes/studio.py`, `backend/app/routes/api_media.py`, `frontend/lib/features/studio/data/studio_repository.dart`, `frontend/landing/lib/studioUploads.ts`, `frontend/lib/features/media/data/media_pipeline_repository.dart`

---

## SYSTEM DECISION

- Existing backend media logic is canonical
- No new business logic is allowed
- Media pipeline must converge, not fork

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/studio.py`, `backend/app/routes/api_media.py`, `frontend/lib/features/studio/data/studio_repository.dart`, `frontend/landing/lib/studioUploads.ts`, `frontend/lib/features/media/data/media_pipeline_repository.dart`

- Identify the exact overlap between lesson-presign flow and canonical pipeline flow

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected canonical flow MUST:

- preserve existing upload lifecycle behavior
- reuse `/api/media/upload-url`, `/api/media/complete`, and `/api/media/attach`
- NOT duplicate upload business logic

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- preserve existing upload target, completion, and attachment fields
- remain usable by Studio and landing callers

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected canonical flow MUST:

- return deterministic structure
- NOT add a second lesson-upload lifecycle
- NOT require new frontend-only transformations

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple upload flows exist:

- prefer the canonical `/api/media/*` lifecycle
- treat `studio.py` lesson upload endpoints as transitional adapters only

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create aligned lesson upload surface around:
  POST `/api/media/upload-url`
  POST `/api/media/complete`
  POST `/api/media/attach`

#### STEP 3B — Adapter rules

Alignment MUST:

- call existing pipeline logic directly
- NOT call through HTTP internally
- NOT duplicate completion or attachment logic
- NOT introduce a second lesson-media lifecycle

#### STEP 3C — Request/response passthrough

- Request MUST preserve existing lesson-upload inputs
- Response MUST preserve existing upload/attach outputs
- No speculative transformation allowed

### STEP 4 — Failure handling

IF:

- lesson-upload behavior cannot be mapped to canonical pipeline
- existing Studio callers require new business logic
- attachment semantics are unclear

→ STOP

---

## DO NOT

- modify media-processing rules
- modify transcode-worker behavior
- redesign lesson-media semantics
- change storage rules

---

## VERIFICATION

After change:

- lesson uploads use one canonical lifecycle
- Studio and landing callers resolve through the same canonical media pipeline
- no duplicate upload/completion logic remains

---

## STOP CONDITIONS

- canonical lifecycle cannot be proven
- caller compatibility requires new business logic
- attachment contract is ambiguous

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

media_upload_pipeline / alignment

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `api_align_media_sign_route`

---

## NOTES

- Convergence task
- Existing `/api/media/*` pipeline remains canonical
