## TASK ID

home_player_emit_canonical_runtime_projection

---

## PROBLEM

- Historical snapshot assumed Home feed still returned mixed ids and partially-resolved playback URLs
- Current `/home/audio` runtime already emits `runtime_media_id`, `is_playable`, `playback_state`, and `failure_reason`
- Equivalent handler expected in: `backend/app/routes/home.py`, `backend/app/repositories/home_player_library.py`, `backend/app/repositories/runtime_media.py`, `frontend/lib/features/home/data/home_audio_repository.dart`, `media_control_plane_phase2_design.md`, `homeplayer_audit_for_media_control_plane.md`

---

## SYSTEM DECISION

- Media authority = control_plane
- Existing runtime projection logic is canonical
- No new business logic is allowed

---

## TASK VALIDITY

- is_real_problem: true
- already_satisfied: true
- requires_code_change: false

---

## PROBLEM TYPE

problem_type: contract_mismatch

classification_reason: The original issue was a Home runtime contract mismatch where the feed exposed mixed identities and partially resolved playback state. Current code already emits the canonical projection, so this task remains only as already-satisfied historical evidence.

---

## REQUIRED ACTION

STOP TASK GENERATION

- retain this file only as completed historical evidence
- do not generate new implementation work from this task

---

## DO NOT

- introduce new media identities
- duplicate resolver logic
- leak raw storage ids as public contract
- redesign Home curation rules

---

## VERIFICATION

- Home feed exposes one canonical runtime projection
- frontend no longer needs mixed id interpretation
- playability metadata is explicit

---

## STOP CONDITIONS

- this task is treated as unresolved implementation work
- current runtime evidence is ignored

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
