# TA-007

- TASK_ID: `TA-007`
- TYPE: `OWNER`
- CLUSTER: `MEDIA_SYSTEM_FIX`
- DESCRIPTION: `Implement system fixes so governed media surfaces resolve through canonical `media_assets`, `lesson_media`, and `runtime_media` truth only, with no legacy upload, direct-storage, or fallback authority paths.`
- TARGET_FILES:
  - `backend/app/routes/api_media.py`
  - `backend/app/routes/home.py`
  - `backend/app/routes/studio.py`
  - `backend/app/services/lesson_playback_service.py`
  - `backend/app/media_control_plane/services/media_resolver_service.py`
  - `backend/app/repositories/runtime_media.py`
  - `backend/app/repositories/media_assets.py`
  - `backend/app/repositories/courses.py`
  - `backend/supabase/baseline_slots/0008_runtime_media_projection_core.sql`
- ACTION: `implement`
- DEPENDS_ON: `[]`

