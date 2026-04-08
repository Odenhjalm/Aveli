# BCP-043

- TASK_ID: `BCP-043`
- TYPE: `OWNER`
- TITLE: `Align backend read composition and resolvers to unified runtime_media`
- PROBLEM_STATEMENT: `After BCP-043A aligns the dependency-valid course-cover and home-player consumers and BCP-042B materializes the active profile-media authority path, the remaining mounted profile/community media paths still must not reintroduce a second media doctrine. This downstream task survives only for the remaining mounted scope that must now align to the approved one-model profile-media domain through unified runtime_media.`
- IMPLEMENTATION_SURFACES:
  - `backend/app/repositories/teacher_profile_media.py`
  - `backend/app/routes/community.py`
  - `backend/app/utils/profile_media.py`
  - any remaining mounted profile/community media consumers only
- TARGET_STATE:
  - backend read composition remains the sole author of `{ media_id, state, resolved_url } | null`
  - remaining mounted profile/community media consumers use the unified media chain from `app.profile_media_placements` through `runtime_media` instead of storage-truth or surface-specific payloads
  - alternate profile/community media truth lookups are removed from mounted runtime paths
  - frontend-facing payloads continue to receive backend-authored media objects only
- DEPENDS_ON:
  - `BCP-042`
  - `BCP-042A`
  - `BCP-042B`
  - `BCP-043A`
- VERIFICATION_METHOD:
  - grep mounted profile/community runtime for storage-truth fields, direct signed/download URLs, and alternate media truth helpers
  - confirm remaining governed profile/community surfaces read media truth from unified `runtime_media`
  - confirm backend read composition still owns frontend media representation

## OWNER IMPLEMENTATION

- Replaced the mounted profile-media repository source with the active contract-owned feature entity:
  - `app.profile_media_placements`
  - fields consumed only from `id`, `subject_user_id`, `media_asset_id`, `visibility`
- Added one canonical runtime-media lookup helper for profile-media rows:
  - `backend/app/repositories/runtime_media.py::get_profile_runtime_media`
- Rewrote the mounted profile/community read-composition helper in `backend/app/utils/profile_media.py` so frontend-facing media payloads are authored only as:
  - `{ media_id, state, resolved_url } | null`
- Removed mounted profile/community dependence on legacy source variants:
  - `lesson_media_sources`
  - `seminar_recording_sources`
  - `media_kind`
  - `external_url`
  - `cover_image_url`
  - `is_published`
  - `enabled_for_home_player`
- Rewired the mounted community read path in `backend/app/routes/community.py` so published teacher profile media flows:
  - `app.profile_media_placements`
  - `app.runtime_media`
  - backend read composition
  - API response
- Rewired the mounted studio read and write paths in `backend/app/routes/studio.py` so profile media CRUD now uses:
  - `media_asset_id`
  - `visibility`
  - backend-authored `TeacherProfileMediaItem`
- Updated the mounted schema contract in `backend/app/schemas.py` and `backend/app/schemas/__init__.py` to the canonical one-model profile-media shape only.
- Updated focused profile/community truth tests so the mounted contract asserts:
  - canonical source identity
  - canonical response shape
  - runtime-media-backed frontend media representation
  - absence of legacy profile-media fields

## OWNER EVIDENCE

- `actual_truth/contracts/profile_community_media_contract.md`
  - canonical feature entity = `app.profile_media_placements`
  - canonical subject binding = `subject_user_id`
  - canonical purpose = `profile_media`
  - community consumes the same domain through backend read composition
- `actual_truth/contracts/media_unified_authority_contract.md`
  - unified chain remains `media_id -> runtime_media -> backend read composition -> API -> frontend`
- `Aveli_System_Decisions.md`
  - governed media must not create a second resolver system
  - backend read composition remains the only frontend media representation authority
- `backend/supabase/baseline_slots/0019_runtime_media_profile_media.sql`
  - baseline authority now exposes published profile-media rows through unified `runtime_media`
- `backend/app/routes/community.py`
  - mounted public profile/community media no longer emits source lists or storage-truth aliases
- `backend/app/routes/studio.py`
  - mounted teacher profile media CRUD no longer carries legacy profile-media source variants

## OWNER VERIFICATION

- `python -m py_compile` passed for:
  - `backend/app/repositories/teacher_profile_media.py`
  - `backend/app/repositories/runtime_media.py`
  - `backend/app/utils/profile_media.py`
  - `backend/app/routes/community.py`
  - `backend/app/routes/studio.py`
  - `backend/app/schemas.py`
  - `backend/app/schemas/__init__.py`
  - `backend/tests/test_teacher_profile_media.py`
  - `backend/tests/test_teacher_profile_media_truth_alignment.py`
- Focused profile/community verification passed:
  - `pytest backend/tests/test_teacher_profile_media.py backend/tests/test_teacher_profile_media_truth_alignment.py -q`
  - result: `8 passed`
- Mounted profile/community route blocks now verify as runtime-media-backed:
  - `backend/app/routes/community.py` uses `list_public_teacher_profile_media(...)` and `profile_media_item_from_row(...)`
  - `backend/app/routes/studio.py` uses `list_teacher_profile_media(...)`, `create_teacher_profile_media(...)`, `update_teacher_profile_media(...)`, and `profile_media_item_from_row(...)`
- Grep verification confirmed no remaining legacy profile/community payload fields in the mounted profile/community implementation surfaces:
  - `cover_image_url`
  - `asset_url`
  - `storage_path`
  - `storage_bucket`
  - `lesson_media_sources`
  - `seminar_recording_sources`
  - `media_kind`
  - `external_url`
  - `seminar_recording_id`
  - `lesson_media_id`
  - `enabled_for_home_player`
  - `is_published`

## EXECUTION LOCK

- EXPECTED_STATE:
  - remaining mounted profile/community media consumers use the approved one-model profile-media contract through unified `runtime_media`
  - backend read composition remains the only frontend media representation authority
  - mounted profile/community runtime paths do not reintroduce a second media doctrine
- ACTUAL_STATE:
  - mounted profile/community routes now consume `app.profile_media_placements` through the unified runtime-media chain
  - frontend-facing profile/community payloads now carry only canonical item fields and backend-authored `media`
  - mounted legacy source-list and storage-truth payload paths were removed from the aligned profile/community surfaces
- REMAINING_RISKS:
  - non-mounted cleanup helpers and old database references may still mention legacy `teacher_profile_media`, but they are not mounted profile/community read-composition authority in this task scope
  - the downstream runtime-media gate in `BCP-044` must still prove that no governed media surface bypasses unified `runtime_media`
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-044`
