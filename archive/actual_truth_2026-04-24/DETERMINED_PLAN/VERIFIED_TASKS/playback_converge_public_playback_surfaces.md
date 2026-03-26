## TASK ID

playback_converge_public_playback_surfaces

---

## PROBLEM

- Public playback is split across `/media/sign`, `/api/media/playback-url`, `/api/media/lesson-playback`, `/api/media/playback`, `/api/playback/lesson`, and runtime-media streaming
- Phase-2 design requires one canonical public playback surface
- Equivalent handler expected in: `backend/app/routes/media.py`, `backend/app/routes/api_media.py`, `backend/app/routes/playback.py`, `backend/app/services/playback_delivery_service.py`, `frontend/lib/api/api_paths.dart`, `frontend/lib/shared/utils/lesson_media_playback_resolver.dart`, `frontend/lib/features/media/data/media_pipeline_repository.dart`

---

## SYSTEM DECISION

- Media authority = control_plane
- Existing playback logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/media.py`, `backend/app/routes/api_media.py`, `backend/app/routes/playback.py`, `backend/app/services/playback_delivery_service.py`, `frontend/lib/api/api_paths.dart`, `frontend/lib/shared/utils/lesson_media_playback_resolver.dart`, `frontend/lib/features/media/data/media_pipeline_repository.dart`

- Identify every current public playback entry point and its callers

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected canonical playback surface MUST:

- operate on the canonical runtime identity
- support both lesson and Home playback
- NOT require caller-specific fallback paths

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- accept canonical runtime identity
- return the canonical playback response
- define how transitional routes map to the canonical surface

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected playback surface MUST:

- be deterministic
- NOT expose multiple competing public contracts
- NOT require new frontend branching logic

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple playback APIs exist:

- prefer the runtime-media control-plane surface
- treat other surfaces as transitional only

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create canonical public playback surface for all callers

#### STEP 3B — Adapter rules

Convergence MUST:

- call existing playback logic directly
- NOT duplicate signing or streaming logic
- NOT keep legacy or asset-specific surfaces as equal public contracts

#### STEP 3C — Request/response passthrough

- Canonical request MUST be passed unchanged
- Canonical response MUST be returned unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- one shared playback surface cannot be chosen
- caller compatibility requires multiple permanent public APIs
- new business logic is required

→ STOP

---

## DO NOT

- invent new playback APIs
- duplicate playback logic
- keep legacy and canonical surfaces as equal long-term contracts
- redesign media authority rules

---

## VERIFICATION

After change:

- one canonical public playback surface is defined
- legacy/asset-specific/public-token routes are transitional only
- frontend callers can converge on one playback contract

---

## STOP CONDITIONS

- shared public surface cannot be proven
- multiple permanent public APIs remain required
- task requires new business logic

---

## RISK LEVEL

HIGH

---

## CATEGORY

playback / surface_convergence

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `playback_converge_runtime_identity`

---

## NOTES

- Architecture task
- Shared playback logic remains canonical
