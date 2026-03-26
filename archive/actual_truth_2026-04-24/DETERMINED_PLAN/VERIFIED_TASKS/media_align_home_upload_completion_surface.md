## TASK ID

media_align_home_upload_completion_surface

---

## PROBLEM

- Home-player WAV upload currently creates library/runtime state after upload without using the generic media completion surface
- Canonical completion logic already exists in: POST `/api/media/complete`
- Equivalent handler expected in: `backend/app/routes/api_media.py`, `backend/app/routes/studio.py`, `backend/app/repositories/home_player_library.py`, `frontend/lib/features/studio/widgets/home_player_upload_dialog.dart`, `frontend/lib/features/studio/data/studio_repository.dart`

---

## SYSTEM DECISION

- Existing media completion logic is canonical
- No new business logic is allowed
- Home upload flow must converge with the pipeline, not bypass it

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/api_media.py`, `backend/app/routes/studio.py`, `backend/app/repositories/home_player_library.py`, `frontend/lib/features/studio/widgets/home_player_upload_dialog.dart`, `frontend/lib/features/studio/data/studio_repository.dart`

- Identify where Home-player WAV uploads skip generic media completion

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected canonical flow MUST:

- reuse generic media completion rules
- preserve Home-player ownership and purpose validation
- NOT create a second completion state machine

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- preserve Home-player upload confirmation fields
- preserve canonical media state after completion

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected canonical flow MUST:

- return deterministic structure
- NOT bypass existing state transitions
- NOT require new Home-only transformation rules

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple completion paths exist:

- prefer the generic `/api/media/complete` path
- keep Home-specific library-row creation as a projection step only

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create aligned Home-player completion surface around:
  POST `/api/media/complete`

#### STEP 3B — Adapter rules

Alignment MUST:

- call existing completion logic directly
- NOT duplicate media-state transitions
- NOT bypass ownership/purpose validation
- NOT introduce a second upload-complete contract

#### STEP 3C — Request/response passthrough

- Request MUST preserve current Home-upload identity inputs
- Response MUST preserve canonical media state outputs
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- generic completion cannot serve Home-player uploads
- library-row projection depends on hidden side effects
- new business logic is required

→ STOP

---

## DO NOT

- change transcode-worker behavior
- change Home-player visibility rules
- redesign library-row semantics
- change storage buckets or paths

---

## VERIFICATION

After change:

- Home-player WAV uploads complete through the same canonical media lifecycle as other pipeline uploads
- Home-specific projection remains downstream of canonical media completion
- no duplicate completion state machine remains

---

## STOP CONDITIONS

- canonical completion cannot be reused
- hidden Home-only side effects exist
- new business logic is required

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

media_upload_pipeline / home_alignment

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `media_align_lesson_upload_surfaces`

---

## NOTES

- Convergence task
- Generic media completion remains canonical
