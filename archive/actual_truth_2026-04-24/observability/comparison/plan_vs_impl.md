# observability — planned vs implemented

## planned sources
- `codex/AVELI_OPERATING_SYSTEM.md`
- `docs/media_control_plane_mcp.md`
- `actual_truth_2026-04-24/observability/mcp_observability_contract.md`

## implemented sources
- `backend/app/routes/media_control_plane_mcp.py`
- `backend/app/repositories/home_player_library.py`
- `backend/app/repositories/media_assets.py`
- `backend/app/repositories/runtime_media.py`
- `backend/app/services/media_control_plane_observability.py`
- `backend/tests/test_media_control_plane_observability.py`

## system should be
- Runtime isolation rollout should surface lesson/runtime projection drift, home-upload runtime gaps, and orphaned asset conditions without UI-first debugging.
- Media-control-plane observability should stay deterministic, read-only, and grounded in the canonical resolver.

## system is
- `get_asset()` reports `home_runtime_projection_missing` when an active Home upload has no `runtime_media` row.
- `list_orphaned_assets()` classifies `runtime_projection_gap` for Home assets and distinguishes grace-window uploads from stalled assets.
- `validate_runtime_projection(lesson_id)` performs field-level lesson/runtime contract comparison and reuses the canonical resolver without mutating state.
- `backend/tests/test_media_control_plane_observability.py` covers lesson projection diffs, Home runtime-gap detection, and false-negative avoidance for failed unlinked Home audio.

## mismatches
- None proven from current repo state for the runtime-isolation scope.
