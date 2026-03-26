## TASK ID

home_player_route_playback_through_control_plane

---

## PROBLEM

- Historical snapshot assumed Home playback still branched between feed-provided URLs and non-canonical playback calls
- Current Home UI already resolves playback through `POST /api/media/playback` using `runtime_media_id`
- Equivalent handler expected in: `frontend/lib/features/home/presentation/home_dashboard_page.dart`, `frontend/lib/features/home/data/home_audio_repository.dart`, `backend/app/routes/home.py`, `backend/app/routes/api_media.py`, `backend/app/routes/playback.py`, `backend/app/services/playback_delivery_service.py`, `media_control_plane_phase2_design.md`

---

## SYSTEM DECISION

- Media authority = control_plane
- Existing playback-resolution logic is canonical
- No new business logic is allowed

---

## TASK VALIDITY

- is_real_problem: true
- already_satisfied: true
- requires_code_change: false

---

## PROBLEM TYPE

problem_type: architecture_change

classification_reason: The original issue required structural convergence of Home playback onto the shared control plane rather than a Home-specific surface. Current Home playback already uses the shared runtime-media playback path, so this task remains only as already-satisfied historical evidence.

---

## REQUIRED ACTION

STOP TASK GENERATION

- retain this file only as completed historical evidence
- do not generate new implementation work from this task

---

## DO NOT

- invent a Home-only playback API
- duplicate control-plane logic
- expose raw storage URLs as primary contract
- redesign Home curation rules

---

## VERIFICATION

- Home playback uses the same canonical playback surface as the rest of the system
- Home-specific playback branches are removed or reduced to transitional adapters
- feed-attached URLs are no longer the primary public playback contract

---

## STOP CONDITIONS

- this task is treated as unresolved implementation work
- current runtime evidence is ignored

---

## RISK LEVEL

HIGH

---

## CATEGORY

home_player / control_plane_alignment

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `home_player_emit_canonical_runtime_projection`

---

## NOTES

- Completed historical task
- Shared playback surface already remains canonical for Home playback
