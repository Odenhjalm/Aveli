# BCP-044

- TASK_ID: `BCP-044`
- TYPE: `GATE`
- TITLE: `Verify unified runtime_media authority across governed surfaces`
- PROBLEM_STATEMENT: `The canonical media plan fails if course cover or any other governed media surface can still bypass unified runtime_media or reintroduce a surface-specific resolver after alignment lands.`
- IMPLEMENTATION_SURFACES:
  - `backend/tests/`
  - `backend/app/services/courses_service.py`
  - `backend/app/services/courses_read_service.py`
  - `backend/app/media_control_plane/services/media_resolver_service.py`
  - governed media read paths
- TARGET_STATE:
  - focused verification fails when course cover bypasses unified `runtime_media`
  - focused verification fails when any governed surface emits media outside backend-authored `{ media_id, state, resolved_url } | null`
  - focused verification fails when alternate media truth paths return
- DEPENDS_ON:
  - `BCP-043`
- VERIFICATION_METHOD:
  - add focused backend tests for course cover and other governed media surfaces
  - run grep checks for alternate resolvers, storage-truth leaks, and runtime-media bypasses
  - confirm no separate cover resolver or alternate media truth path remains mounted

## GATE IMPLEMENTATION

- Added one focused runtime-media authority gate file:
  - `backend/tests/test_runtime_media_authority_gate.py`
- Performed the minimum contract repair required by the gate:
  - removed the extra `source` field from course-cover frontend payload composition in `backend/app/services/courses_service.py`
- Reused already aligned governed-surface verification for:
  - home-player media
  - profile/community media
- Kept the gate within verification scope:
  - no baseline mutation
  - no new resolver system
  - no route expansion outside governed media read composition

## GATE EVIDENCE

- `backend/app/services/courses_service.py`
  - course-cover payload now emits only `{ media_id, state, resolved_url }`
  - home-player media continues to emit only `{ media_id, state, resolved_url }`
- `backend/app/utils/profile_media.py`
  - profile/community media continues to emit only backend-authored `ResolvedMedia`
- `backend/tests/test_runtime_media_authority_gate.py`
  - proves course-cover read composition uses unified `runtime_media`
  - proves course-cover placeholders also stay inside the canonical frontend shape
- `backend/tests/test_courses_service_home_audio.py`
  - proves home-player media uses runtime-media-backed backend-authored media objects
- `backend/tests/test_teacher_profile_media_truth_alignment.py`
  - proves profile/community media uses runtime-media-backed backend-authored media objects

## GATE VERIFICATION

- `python -m py_compile` passed for:
  - `backend/app/services/courses_service.py`
  - `backend/tests/test_runtime_media_authority_gate.py`
- Focused governed-surface verification passed:
  - `pytest backend/tests/test_runtime_media_authority_gate.py backend/tests/test_courses_service_home_audio.py backend/tests/test_teacher_profile_media_truth_alignment.py -q`
  - result: `8 passed`
- Grep verification confirmed no alternate media truth helpers remain in the mounted governed-surface implementation scope:
  - no `resolve_media_asset_playback` in governed mounted read-composition surfaces
  - no `cover_image_url`
  - no `asset_url`
  - no `lesson_media_sources`
  - no `seminar_recording_sources`
- Course-cover payload composition no longer carries the extra `source` field that would violate the unified frontend media shape.

## EXECUTION LOCK

- EXPECTED_STATE:
  - governed media surfaces share one unified runtime-media authority
  - course cover, home-player media, and profile/community media emit only `{ media_id, state, resolved_url } | null`
  - no surface-specific resolver or storage-truth bypass remains mounted
- ACTUAL_STATE:
  - course-cover payload composition now matches the canonical frontend media shape
  - home-player and profile/community media continue to match the same canonical shape
  - focused verification across governed surfaces passed without introducing a second media doctrine
- REMAINING_RISKS:
  - later DB-surface alignment in `BCP-036` still must ensure course detail and lesson content reads remain surface-based end to end
  - stale broader integration tests exist outside the focused gate scope and still assume older course-cover payloads or unreplayed local DB state
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `PASSED_FOR_BCP-036_AND_BCP-050`
