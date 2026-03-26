## TASK ID

media_align_home_upload_completion_surface

---

## PROBLEM

- Historical snapshot assumed Home-player WAV upload bypassed the generic media completion surface
- Current Home upload flow already calls `MediaPipelineRepository.completeUpload()` before creating the Home projection row
- Equivalent handler expected in: `backend/app/routes/api_media.py`, `backend/app/routes/studio.py`, `backend/app/repositories/home_player_library.py`, `frontend/lib/features/studio/widgets/home_player_upload_dialog.dart`, `frontend/lib/features/studio/data/studio_repository.dart`

---

## SYSTEM DECISION

- Existing media completion logic is canonical
- No new business logic is allowed
- Home upload flow must converge with the pipeline, not bypass it

---

## TASK VALIDITY

- is_real_problem: true
- already_satisfied: true
- requires_code_change: false

---

## PROBLEM TYPE

problem_type: contract_mismatch

classification_reason: The original issue was a Home upload contract mismatch against the canonical `/api/media/complete` lifecycle. Current runtime already uses the canonical completion surface, so this task is retained only as already-satisfied historical evidence.

---

## REQUIRED ACTION

STOP TASK GENERATION

- retain this file only as completed historical evidence
- do not generate new implementation work from this task

---

## DO NOT

- change transcode-worker behavior
- change Home-player visibility rules
- redesign library-row semantics
- change storage buckets or paths

---

## VERIFICATION

- Home-player WAV uploads complete through the same canonical media lifecycle as other pipeline uploads
- Home-specific projection remains downstream of canonical media completion
- no active task depends on a missing Home upload completion fix

---

## STOP CONDITIONS

- this task is treated as active implementation work
- current runtime evidence is ignored

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

media_upload_pipeline / home_alignment

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Completed historical task
- Generic media completion already remains canonical
