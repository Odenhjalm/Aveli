## TASK ID

playback_converge_runtime_identity

---

## PROBLEM

- Public playback still leaks multiple identity types: `lesson_media_id`, `media_asset_id`, legacy token ids, and `runtime_media_id`
- Phase-2 design requires one reference-layer runtime identity
- Equivalent handler expected in: `media_control_plane_phase2_design.md`, `backend/app/repositories/runtime_media.py`, `backend/app/routes/api_media.py`, `backend/app/routes/playback.py`, `backend/app/routes/home.py`, `frontend/lib/api/api_paths.dart`, `frontend/lib/shared/utils/lesson_media_playback_resolver.dart`, `frontend/lib/features/home/data/home_audio_repository.dart`

---

## SYSTEM DECISION

- Media authority = control_plane
- Existing runtime projection is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open source files:
  `media_control_plane_phase2_design.md`, `backend/app/repositories/runtime_media.py`, `backend/app/routes/api_media.py`, `backend/app/routes/playback.py`, `backend/app/routes/home.py`, `frontend/lib/api/api_paths.dart`, `frontend/lib/shared/utils/lesson_media_playback_resolver.dart`, `frontend/lib/features/home/data/home_audio_repository.dart`

- Identify every current public caller and the identity it uses

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected canonical identity MUST:

- sit above asset/object/storage identity
- work for both lesson and Home playback
- NOT require separate public ids per surface

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON and/or contract artifact output
- define one public runtime identity
- define how legacy callers map to that identity during migration

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected identity MUST:

- be deterministic
- NOT expose storage or asset ids as the primary public contract
- NOT create a second reference layer

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple identity candidates exist:

- prefer `runtime_media_id`
- fallback only to an explicitly documented equivalent reference-layer id

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create canonical runtime-identity contract around:
  `runtime_media_id`

#### STEP 3B — Adapter rules

Identity convergence MUST:

- reuse existing runtime projection directly
- NOT duplicate mapping logic per caller
- NOT keep asset-centric ids as the primary public contract

#### STEP 3C — Request/response passthrough

- Canonical runtime id MUST be propagated unchanged
- Legacy mapping rules MUST be explicit
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- one shared identity cannot be proven
- Home and lesson playback require different public ids
- new business logic is required

→ STOP

---

## DO NOT

- invent new parallel identities
- leak storage ids as public contract
- duplicate projection logic
- redesign media authority rules

---

## VERIFICATION

After change:

- one canonical runtime identity is defined and used across playback surfaces
- legacy ids are transitional only
- Home and lesson callers can share the same public identity contract

---

## STOP CONDITIONS

- shared identity cannot be proven
- surfaces require different public ids
- task requires new business logic

---

## RISK LEVEL

HIGH

---

## CATEGORY

playback / identity_convergence

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `home_player_emit_canonical_runtime_projection`

---

## NOTES

- Architecture task
- Runtime projection remains canonical source
