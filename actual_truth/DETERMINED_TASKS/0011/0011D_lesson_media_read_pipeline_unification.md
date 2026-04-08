# 0011D

- TASK_ID: `0011D`
- TYPE: `OWNER`
- TITLE: `Unify lesson media read surfaces under one backend media pipeline`
- PROBLEM_STATEMENT: `Lesson read surfaces currently mix canonical runtime playback with repository runtime joins, route-level preview fallbacks, direct URL absolutization, and storage-derived preview recovery.`
- TARGET_STATE:
  - `backend/app/repositories/courses.py`
  - `backend/app/routes/api_media.py`
  - `backend/app/routes/courses.py`
  - `backend/app/services/lesson_playback_service.py`
  - `frontend/lib/shared/utils/lesson_media_playback_resolver.dart`
  - lesson content and preview read surfaces use one backend-owned media object and one playback authority path
  - repositories do not join `app.runtime_media` for read-surface composition
  - route-level image/document preview fallbacks do not recover from storage or legacy URLs
  - frontend lesson rendering requests backend playback only through canonical lesson/runtime ids
- DEPENDS_ON:
  - `0011A`
- VERIFICATION_METHOD:
  - `rg -n "preview_ready|resolved_preview_url|download_url|playback_url|runtime_media|lesson-playback|runtime-playback" backend/app frontend/lib`
  - confirm repository output is storage-free and resolver-free
  - confirm preview and playback surfaces do not fall back to storage/public URLs

