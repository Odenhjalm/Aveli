# 0011F

- TASK_ID: `0011F`
- TYPE: `OWNER`
- TITLE: `Shut down duplicate legacy media read pipelines after surface cutover`
- PROBLEM_STATEMENT: `Mounted runtime still contains duplicate media resolution utilities and legacy read endpoints, including direct storage presign helpers, media_signer fallbacks, /media/sign, /media/stream, /studio/media/{id}, and /api/files-based recovery paths.`
- TARGET_STATE:
  - `backend/app/services/media_resolver.py`
  - `backend/app/utils/media_signer.py`
  - `backend/app/routes/media.py`
  - `backend/app/routes/studio.py`
  - `backend/app/routes/upload.py`
  - `backend/app/utils/lesson_content.py`
  - `frontend/lib/shared/utils/course_cover_resolver.dart`
  - any dead frontend media-signing helpers used only by legacy read paths
  - no mounted read surface depends on direct storage signing, `/media/stream`, `/studio/media/{id}`, `/api/files`, or legacy URL alias recovery
  - dead client-side read resolvers are removed
- DEPENDS_ON:
  - `0011B`
  - `0011C`
  - `0011D`
  - `0011E`
- VERIFICATION_METHOD:
  - `rg -n "resolve_media_url|resolve_storage_playback_url|resolve_lesson_media_playback_url|attach_media_links|/media/stream/|/studio/media/|/api/files/|signMedia\\(|resolveDownloadUrl\\(|resolveCourseCoverUrl" backend/app frontend/lib`
  - confirm only canonical read/playback paths remain mounted
  - confirm no frontend read surface owns media resolution

