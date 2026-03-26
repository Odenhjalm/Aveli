# home_player — planned vs implemented

## planned sources
- `actual_truth_2026-04-26/Aveli_System_Decisions.md`
- `homeplayer_audit_for_media_control_plane.md`
- `media_control_plane_phase2_design.md`
- `runtime_media_reference_design.md`
- `docs/media_control_plane/media_pipeline_audit_2026-03-14.md`

## implemented sources
- `backend/app/routes/home.py`
- `backend/app/routes/api_media.py`
- `backend/app/routes/studio.py`
- `backend/app/repositories/courses.py`
- `backend/app/repositories/home_player_library.py`
- `backend/app/repositories/runtime_media.py`
- `backend/app/schemas/__init__.py`
- `backend/app/services/courses_service.py`
- `frontend/lib/features/home/data/home_audio_repository.dart`
- `frontend/lib/features/home/presentation/home_dashboard_page.dart`
- `frontend/lib/features/media/data/media_pipeline_repository.dart`
- `frontend/lib/features/studio/widgets/home_player_upload_dialog.dart`

## system should be
- Home should expose one canonical runtime-media projection to the frontend.
- Home playback should resolve through the shared runtime playback contract.
- Direct Home uploads should remain teacher-library items, not synthetic lesson/course items.

## system is
- `/home/audio` now emits `runtime_media_id`, `is_playable`, `playback_state`, and `failure_reason`, and `courses_service._attach_home_playback_metadata()` strips raw storage and signed-URL fields before returning the feed.
- `frontend/lib/features/home/presentation/home_dashboard_page.dart` now resolves playback through `MediaPipelineRepository.fetchRuntimePlaybackUrl()` and `POST /api/media/playback`.
- Home WAV uploads now call `MediaPipelineRepository.completeUpload()` before creating the `home_player_uploads` projection row, so the generic media completion surface is already in use.
- Direct-upload rows in `backend/app/repositories/courses.py` still populate `lesson_id` and `course_id` with `runtime_media.id` so they fit the lesson-shaped feed schema, and the frontend `HomeAudioItem` model still requires lesson/course context for every Home item.

## mismatches
- `[important] home_player_isolate_direct_upload_contract` — direct Home uploads still masquerade as lesson/course-shaped items instead of exposing an isolated teacher-library contract around the canonical `runtime_media_id`.
