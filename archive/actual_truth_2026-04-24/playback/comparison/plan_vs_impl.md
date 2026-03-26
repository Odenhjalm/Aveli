# playback — planned vs implemented

## planned sources
- `actual_truth_2026-04-24/Aveli_System_Decisions.md`
- `docs/media_pipeline.md`
- `docs/media_control_plane/media_pipeline_audit_2026-03-14.md`
- `media_control_plane_phase2_design.md`
- `runtime_media_reference_design.md`

## implemented sources
- `backend/app/routes/api_media.py`
- `backend/app/routes/media.py`
- `backend/app/routes/playback.py`
- `backend/app/media_control_plane/services/media_resolver_service.py`
- `backend/app/services/lesson_playback_service.py`
- `backend/app/services/playback_delivery_service.py`
- `frontend/lib/api/api_paths.dart`
- `frontend/lib/features/media/data/media_pipeline_repository.dart`
- `frontend/lib/shared/utils/lesson_media_playback_resolver.dart`
- `frontend/lib/features/home/presentation/home_dashboard_page.dart`

## system should be
- Playback should expose one canonical runtime identity and one canonical public playback API.
- Legacy token signing and asset-centric playback should be transitional only.
- Home and lesson playback should resolve through the same control-plane-backed runtime surface.

## system is
- Home playback now calls `/api/media/playback` with `runtime_media_id`.
- Frontend lesson playback still calls `/api/media/lesson-playback` with `lesson_media_id`, even though the backend resolves that path by looking up `runtime_media_id` and delegating to runtime playback.
- Asset-centric `/api/media/playback-url`, router-level `/api/playback/lesson`, runtime stream delivery, and legacy `/media/sign` remain mounted or documented beside the canonical runtime playback path.

## mismatches
- `[important] playback_converge_runtime_identity` — lesson-facing playback and supporting docs still expose non-runtime ids even though `runtime_media_id` is now the shared control-plane identity.
- `[important] playback_converge_public_playback_surfaces` — several public playback entry points remain mounted where one canonical surface is planned.
