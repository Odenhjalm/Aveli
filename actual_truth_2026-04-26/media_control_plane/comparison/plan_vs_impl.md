# media_control_plane — planned vs implemented

## planned sources
- `actual_truth_2026-04-26/Aveli_System_Decisions.md`
- `aveli_system_manifest.json`
- `docs/media_control_plane_mcp.md`
- `docs/media_architecture.md`
- `docs/media_control_plane/media_control_plane_plan.md`
- `docs/media_control_plane/media_pipeline_audit_2026-03-14.md`
- `media_control_plane_phase2_design.md`
- `runtime_media_reference_design.md`
- `homeplayer_audit_for_media_control_plane.md`

## implemented sources
- `backend/app/media_control_plane/services/media_resolver_service.py`
- `backend/app/repositories/runtime_media.py`
- `backend/app/routes/api_media.py`
- `backend/app/routes/media_control_plane_mcp.py`
- `backend/app/routes/playback.py`
- `backend/app/services/lesson_playback_service.py`
- `backend/app/services/media_control_plane_observability.py`
- `frontend/lib/features/home/data/home_audio_repository.dart`
- `frontend/lib/features/home/presentation/home_dashboard_page.dart`
- `frontend/lib/features/media/data/media_pipeline_repository.dart`
- `frontend/lib/shared/utils/lesson_media_playback_resolver.dart`

## system should be
- One canonical runtime media identity should sit above assets, objects, and storage rows.
- One canonical playback API should serve both lesson playback and Home playback.
- The control plane should remain the protected authority for readiness, auth, storage-selection rules, and rollout observability.

## system is
- The resolver service, `runtime_media` table, MCP routes, and home/runtime playback flow already exist.
- Home playback now consumes `runtime_media_id` and resolves through `POST /api/media/playback`.
- `POST /api/media/lesson-playback`, `POST /api/media/playback-url`, `POST /api/playback/lesson`, `GET /api/media/stream/{runtime_media_id}`, and legacy `/media/sign` still remain mounted or documented beside the runtime playback surface.
- `backend/app/services/media_control_plane_observability.py` and `docs/media_control_plane_mcp.md` already cover lesson-runtime drift and home-upload runtime gaps through `get_asset`, `list_orphaned_assets`, and `validate_runtime_projection`.

## mismatches
- `[important] playback_converge_runtime_identity` — lesson-facing playback and supporting docs still accept or describe non-runtime ids even though `runtime_media_id` is now the canonical control-plane identity.
- `[important] playback_converge_public_playback_surfaces` — multiple public playback entry points remain mounted beside `POST /api/media/playback`.
