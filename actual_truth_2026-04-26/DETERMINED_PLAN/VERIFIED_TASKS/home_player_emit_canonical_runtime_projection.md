## TASK ID

home_player_emit_canonical_runtime_projection

---

## PROBLEM

- Home feed still returns mixed ids and partially-resolved playback URLs
- Phase-2 design expects a canonical runtime projection with one public runtime id and playability metadata
- Equivalent handler expected in: `backend/app/routes/home.py`, `backend/app/repositories/home_player_library.py`, `backend/app/repositories/runtime_media.py`, `frontend/lib/features/home/data/home_audio_repository.dart`, `media_control_plane_phase2_design.md`, `homeplayer_audit_for_media_control_plane.md`

---

## SYSTEM DECISION

- Media authority = control_plane
- Existing runtime projection logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/home.py`, `backend/app/repositories/home_player_library.py`, `backend/app/repositories/runtime_media.py`, `frontend/lib/features/home/data/home_audio_repository.dart`, `media_control_plane_phase2_design.md`, `homeplayer_audit_for_media_control_plane.md`

- Identify every field in the current Home feed that leaks mixed identity or raw playback URL assumptions

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected projection MUST:

- expose one canonical runtime id
- expose playability state and display metadata
- NOT expose mixed asset/object identities as primary public ids

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- include canonical runtime id
- include playability metadata
- include display metadata without raw playback URLs as primary contract

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected projection MUST:

- be deterministic
- NOT require Home-specific id branching in the frontend
- NOT expose raw storage identity as the public runtime contract

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple identity candidates exist:

- prefer `runtime_media_id`
- fallback to documented reference-layer equivalent only if explicitly proven

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create canonical Home feed projection for:
  GET `/home/audio`

#### STEP 3B — Adapter rules

New projection MUST:

- reuse existing runtime projection logic directly
- NOT duplicate playback resolution
- NOT encode Home-only identity semantics

#### STEP 3C — Request/response passthrough

- Existing display metadata MUST remain usable
- Canonical runtime id MUST be passed unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- canonical runtime id cannot be proven
- Home requires mixed ids to remain functional
- projection requires new business logic

→ STOP

---

## DO NOT

- introduce new media identities
- duplicate resolver logic
- leak raw storage ids as public contract
- redesign Home curation rules

---

## VERIFICATION

After change:

- Home feed exposes one canonical runtime projection
- frontend no longer needs mixed id interpretation
- playability metadata is explicit

---

## STOP CONDITIONS

- canonical runtime id cannot be proven
- Home depends on mixed ids
- task requires new business logic

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

home_player / projection_alignment

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `media_align_home_upload_completion_surface`

---

## NOTES

- Projection task
- Control-plane runtime identity remains canonical
