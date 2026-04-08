# MCR-013

- TASK_ID: `MCR-013`
- TYPE: `AGGREGATE`
- CLUSTER: `MEDIA_VERIFICATION`
- DESCRIPTION: `Run aggregate verification across the media-conflict-resolution scope to confirm no legacy sign or stream routes remain, no direct ready writes remain, no invented runtime_media columns remain, and no raw playback_url or download_url contract payloads remain.`
- TARGET_FILES:
  - `actual_truth/DETERMINED_TASKS/media_conflict_resolution/task_manifest.json`
  - `backend/app/routes/api_media.py`
  - `backend/app/routes/media.py`
  - `backend/app/routes/home.py`
  - `backend/app/services/courses_service.py`
  - `backend/app/repositories/media_assets.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `MCR-012`
