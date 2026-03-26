## TASK ID

home_player_isolate_direct_upload_contract

---

## PROBLEM

- Historical snapshot assumed direct Home uploads still relied on synthetic lesson/course placeholders
- Current Home-feed query already emits `NULL` lesson/course context for direct uploads while preserving `runtime_media_id`
- `frontend/lib/features/home/data/home_audio_repository.dart` already models `lessonId` and `courseId` as optional fields
- Equivalent handler expected in: `backend/app/repositories/courses.py`, `backend/app/services/courses_service.py`, `backend/app/schemas/__init__.py`, `frontend/lib/features/home/data/home_audio_repository.dart`, `frontend/lib/features/home/presentation/home_dashboard_page.dart`, `media_control_plane_phase2_design.md`, `runtime_media_reference_design.md`

---

## SYSTEM DECISION

- Media authority = control_plane
- `runtime_media_id` is the public identity layer
- No new business logic is allowed

---

## TASK VALIDITY

- is_real_problem: true
- already_satisfied: true
- requires_code_change: false

---

## PROBLEM TYPE

problem_type: runtime_mismatch

classification_reason: The original issue was a runtime-data mismatch where direct Home uploads were projected with synthetic lesson/course context instead of their actual DB-backed semantics. Current query and frontend model already align, so this task remains only as already-satisfied historical evidence.

---

## REQUIRED ACTION

STOP TASK GENERATION

- retain this file only as completed historical evidence
- do not generate new implementation work from this task

---

## DO NOT

- change playback authorization
- redesign Home curation rules
- introduce new public media identities
- modify storage or runtime_media semantics

---

## VERIFICATION

- direct Home uploads no longer masquerade as lesson/course items
- frontend contract distinguishes course-linked items from teacher-library items deterministically
- `runtime_media_id` remains the canonical public id

---

## STOP CONDITIONS

- this task is treated as unresolved implementation work
- current runtime evidence is ignored

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

home_player / contract_isolation

---

## EXECUTION ORDER

- Can be executed independently: false
- Depends on: `home_player_emit_canonical_runtime_projection`

---

## NOTES

- Completed historical task
- Teacher-library items already do not need synthetic lesson/course placeholders
