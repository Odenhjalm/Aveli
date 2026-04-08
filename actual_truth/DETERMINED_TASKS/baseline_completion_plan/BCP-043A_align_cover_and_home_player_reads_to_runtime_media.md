# BCP-043A

- TASK_ID: `BCP-043A`
- TYPE: `OWNER`
- TITLE: `Align course-cover and home-player mounted reads to unified runtime_media`
- PROBLEM_STATEMENT: `BCP-043 is currently over-broad. Canonical baseline authority already exists for lesson media, course cover, and home-player direct-upload runtime truth, but mounted course-cover and home-player read composition still bypass unified runtime_media. Those dependency-valid consumers must align first without pulling profile/community work forward.`
- IMPLEMENTATION_SURFACES:
  - `backend/app/services/courses_service.py`
  - `backend/app/services/home_audio_service.py`
  - `backend/app/services/lesson_playback_service.py`
  - `backend/app/repositories/runtime_media.py`
  - `backend/app/media_control_plane/services/media_resolver_service.py`
  - mounted course-cover and home-player read helpers only
- TARGET_STATE:
  - mounted course cover reads derive media truth from unified `runtime_media` instead of direct media-asset or storage checks
  - mounted home-player reads derive media truth from unified `runtime_media` instead of direct media-asset playback shaping
  - backend read composition remains the sole author of `{ media_id, state, resolved_url } | null`
  - no separate cover resolver or home-player-specific media truth path remains mounted for the dependency-valid surfaces in scope
- DEPENDS_ON:
  - `BCP-042`
  - `BCP-042A`
- EXPECTED_OUTCOME_BEFORE_ACTION:
  - the dependency-valid mounted media consumers already covered by canonical baseline truth are aligned to the unified media chain without touching profile/community authority gaps
- VERIFICATION_METHOD:
  - grep mounted course-cover and home-player paths for direct `media_assets` truth reads, direct storage existence checks, and direct `resolve_media_asset_playback` composition
  - confirm course cover and home-player responses now derive media state and resolved playback from `runtime_media`
  - confirm backend read composition still emits frontend media objects only as `{ media_id, state, resolved_url } | null`
- CONSTRAINTS:
  - do not materialize profile/community baseline authority in this task
  - do not widen `runtime_media` row shape beyond the locked append-only baseline
  - do not introduce synthetic runtime identifiers, fallback resolvers, or direct storage-truth contracts
  - do not modify unrelated DB-surface, memberships, auth-subject, or aggregate-audit work
- STOP_CONDITIONS:
  - stop if mounted course-cover or home-player responses require fields that are not present in the unified `runtime_media` baseline and no primary source authorizes extending that baseline inside current scope
  - stop if profile/community alignment becomes required to verify the dependency-valid course-cover and home-player surfaces in this task
  - stop if mounted lesson-media playback semantics would have to be weakened to make course cover or home-player pass

## OWNER IMPLEMENTATION

- Added narrow `runtime_media` repository helpers in `backend/app/repositories/runtime_media.py` for the only dependency-valid mounted consumers in scope:
  - `get_course_cover_runtime_media(...)`
  - `get_home_player_runtime_media(...)`
  - `get_lesson_runtime_media(...)`
- Kept the unified row shape append-only from baseline authority and only exposed the fields needed for backend read composition:
  - `lesson_media_id`
  - `lesson_id`
  - `course_id`
  - `media_asset_id`
  - `media_type`
  - `playback_object_path`
  - `playback_format`
  - `state`
- Rewired `backend/app/services/courses_service.py` so mounted home-player composition no longer calls direct `resolve_media_asset_playback(...)`.
- Rewired `backend/app/services/courses_service.py` so mounted course-cover composition no longer reads direct `media_assets` truth or storage-catalog existence.
- Preserved backend-authored media representation in mounted responses as the read-composition layer output.
- Did not touch profile/community media consumers, `home_audio_service.py`, or broader media-resolver scope because they are outside the dependency-valid mounted boundary owned by this task.

## OWNER EVIDENCE

- `actual_truth/contracts/media_unified_authority_contract.md`
  - one authority chain only: `media_id -> runtime_media -> backend read composition -> API -> frontend`
  - routes must not bypass `runtime_media`
  - no cover-specific authority and no home-player-specific authority may remain mounted
- `actual_truth/contracts/home_audio_runtime_contract.md`
  - `media_asset_id` remains the only playback identity
  - invalid ready items must be filtered rather than propagated
  - no fallback playback path is allowed
- `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md`
  - course cover remains pointer-only at `cover_media_id`
  - backend read composition must derive `cover` from `app.runtime_media`
- `Aveli_System_Decisions.md`
  - no layer may bypass `runtime_media`
  - home-player runtime truth remains owned by `runtime_media`
- repo drift evidence before mutation:
  - mounted course cover resolved from direct `media_assets` and storage-existence logic
  - mounted home-player ready playback resolved from direct `resolve_media_asset_playback(...)`

## OWNER VERIFICATION

- Verified syntax with:
  - `.\.venv\Scripts\python.exe -m py_compile backend/app/repositories/runtime_media.py backend/app/services/courses_service.py backend/tests/test_course_cover_read_contract.py backend/tests/test_courses_service_home_audio.py backend/tests/test_home_audio_feed.py`
- Verified the owned invariant with focused tests:
  - `.\.venv\Scripts\python.exe -m pytest backend/tests/test_courses_service_home_audio.py backend/tests/test_course_cover_read_contract.py::test_resolve_course_cover_ready_asset_returns_control_plane backend/tests/test_course_cover_read_contract.py::test_resolve_course_cover_uploaded_asset_returns_placeholder backend/tests/test_course_cover_read_contract.py::test_resolve_course_cover_missing_asset_returns_placeholder backend/tests/test_course_cover_read_contract.py::test_resolve_course_cover_missing_asset_without_legacy_returns_placeholder backend/tests/test_course_cover_read_contract.py::test_resolve_course_cover_missing_derived_bytes_never_returns_ready backend/tests/test_course_cover_read_contract.py::test_resolve_course_cover_logs_contract_violation backend/tests/test_course_cover_read_contract.py::test_attach_course_cover_read_contract_respects_feature_flag backend/tests/test_course_cover_read_contract.py::test_fetch_course_includes_cover_when_cover_media_id_resolves backend/tests/test_course_cover_read_contract.py::test_list_public_courses_includes_cover_when_cover_media_id_resolves -q`
  - result: `12 passed`
- Verified mounted course-cover and home-player paths no longer reference direct bypasses with grep:
  - no `resolve_media_asset_playback`
  - no `media_assets_repo`
  - no `storage_objects`
  - across:
    - `backend/app/services/courses_service.py`
    - `backend/app/routes/home.py`
    - `backend/app/routes/courses.py`
    - `backend/app/services/courses_read_service.py`
- Noted but intentionally excluded broader route/integration tests that require a replayed local baseline because `BCP-043A` owns mounted read composition, not full local baseline bootstrapping.

## EXECUTION LOCK

- EXPECTED_STATE:
  - mounted course-cover and home-player reads derive runtime truth from unified `runtime_media`
  - no direct `media_assets` truth reads, storage-existence checks, or `resolve_media_asset_playback(...)` bypass remain in the mounted read paths owned by this task
  - backend read composition remains the sole author of response media objects in scope
- ACTUAL_STATE:
  - `courses_service` now composes course-cover payloads from `runtime_media` rows keyed by course pointer identity
  - `courses_service` now composes direct-upload and course-link home-player payloads from `runtime_media` rows instead of direct media-asset playback
  - focused cover and home-player unit verification passed without reopening profile/community scope
- REMAINING_RISKS:
  - `home_audio_service.py` still contains legacy direct playback shaping, but it is not mounted in the current runtime path owned by this task
  - local route/integration tests that create auth subjects require a replayed local baseline and remain outside this task's narrow verification boundary
  - remaining mounted profile/community media consumers are still owned downstream by `BCP-043`
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-043`
