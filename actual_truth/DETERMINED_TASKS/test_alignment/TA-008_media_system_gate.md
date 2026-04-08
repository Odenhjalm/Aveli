# TA-008

- TASK_ID: `TA-008`
- TYPE: `GATE`
- CLUSTER: `MEDIA_SYSTEM_FIX`
- DESCRIPTION: `Validate that media upload, attach, preview, playback, markdown, migration, and direct-upload tests align to canonical `runtime_media` authority and `lesson_media_id`-only references.`
- TARGET_FILES:
  - `backend/tests/test_api_media_audio_validation.py`
  - `backend/tests/test_home_audio_feed.py`
  - `backend/tests/test_lesson_image_compat.py`
  - `backend/tests/test_lesson_markdown_write_contract.py`
  - `backend/tests/test_lesson_media_rendering.py`
  - `backend/tests/test_lesson_media_truth_alignment.py`
  - `backend/tests/test_lesson_playback_resolution_order.py`
  - `backend/tests/test_media_api.py`
  - `backend/tests/test_media_control_plane_observability.py`
  - `backend/tests/test_media_control_plane_resolver.py`
  - `backend/tests/test_newbaseline_enrollment_drip_contract.py`
  - `backend/tests/test_runtime_media_migration.py`
  - `backend/tests/test_scan_legacy_markdown_media_refs.py`
  - `backend/tests/test_studio_direct_uploads.py`
  - `backend/tests/test_studio_pipeline_media_resolvable.py`
  - `backend/tests/test_upload_legacy_routes.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `TA-007`

