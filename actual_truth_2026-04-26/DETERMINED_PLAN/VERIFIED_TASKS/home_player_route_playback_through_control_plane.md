## TASK ID

home_player_route_playback_through_control_plane

---

## PROBLEM

- Home playback still branches between feed-provided URLs and non-canonical playback calls
- Phase-2 design requires Home to use the same canonical control-plane-backed playback path as lesson playback
- Equivalent handler expected in: `frontend/lib/features/home/presentation/home_dashboard_page.dart`, `frontend/lib/features/home/data/home_audio_repository.dart`, `backend/app/routes/home.py`, `backend/app/routes/api_media.py`, `backend/app/routes/playback.py`, `backend/app/services/playback_delivery_service.py`, `media_control_plane_phase2_design.md`

---

## SYSTEM DECISION

- Media authority = control_plane
- Existing playback-resolution logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `frontend/lib/features/home/presentation/home_dashboard_page.dart`, `frontend/lib/features/home/data/home_audio_repository.dart`, `backend/app/routes/home.py`, `backend/app/routes/api_media.py`, `backend/app/routes/playback.py`, `backend/app/services/playback_delivery_service.py`, `media_control_plane_phase2_design.md`

- Identify the current Home-only playback branches and the canonical control-plane target surface

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected playback path MUST:

- use the canonical runtime identity
- use one backend playback surface shared with lesson playback
- NOT depend on feed-attached playback URLs

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- accept canonical runtime identity
- return canonical playback URL or stream handle
- remain compatible with Home playback needs

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected playback path MUST:

- be deterministic
- NOT require Home-only fallback logic
- NOT leak raw storage URLs as public contract

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple playback APIs exist:

- prefer the canonical runtime-media playback surface
- treat Home-specific branches as transitional only

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create canonical Home playback usage around:
  the shared runtime-media playback surface

#### STEP 3B — Adapter rules

New Home playback path MUST:

- call existing playback logic directly
- NOT duplicate resolver logic
- NOT keep feed-attached URLs as primary playback contract

#### STEP 3C — Request/response passthrough

- Canonical runtime id MUST be passed unchanged
- Shared playback response MUST be returned unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- canonical shared playback surface cannot be chosen
- Home requires raw feed URLs to remain primary
- task requires new business logic

→ STOP

---

## DO NOT

- invent a Home-only playback API
- duplicate control-plane logic
- expose raw storage URLs as primary contract
- redesign Home curation rules

---

## VERIFICATION

After change:

- Home playback uses the same canonical playback surface as the rest of the system
- Home-specific playback branches are removed or reduced to transitional adapters
- feed-attached URLs are no longer the primary public playback contract

---

## STOP CONDITIONS

- canonical shared playback surface cannot be proven
- Home depends on raw feed URLs
- task requires new business logic

---

## RISK LEVEL

HIGH

---

## CATEGORY

home_player / control_plane_alignment

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `home_player_emit_canonical_runtime_projection`, `playback_converge_runtime_identity`, `playback_converge_public_playback_surfaces`

---

## NOTES

- Convergence task
- Shared playback surface remains canonical
