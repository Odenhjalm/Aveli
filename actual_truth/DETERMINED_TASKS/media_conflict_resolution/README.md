# MEDIA_CONFLICT_RESOLUTION TASK TREE

## SECTION: TASK TREE

### 1. DELETE_LEGACY_MEDIA_PATHS

- `MCR-001` -> delete the `/api/media/sign` legacy adapter from `backend/app/routes/api_media.py`
- `MCR-002` -> delete `/media/sign` and `/media/stream/{token}` from `backend/app/routes/media.py`
- `MCR-003` -> validate that no legacy sign or stream media routes remain

### 2. RUNTIME_MEDIA_ALIGNMENT

- `MCR-004` -> rewrite `backend/app/routes/api_media.py` to remove illegal `runtime_media` table assumptions
- `MCR-005` -> rewrite `backend/app/services/courses_service.py` to compose media from canonical runtime truth only
- `MCR-006` -> validate that runtime-media alignment uses projection truth only

### 3. MEDIA_ASSET_HELPERS_ALIGNMENT

- `MCR-007` -> implement canonical media-asset helpers for uploaded-state advancement and worker-bound readiness
- `MCR-008` -> rewrite `backend/app/routes/api_media.py` to use canonical media-asset helpers only
- `MCR-009` -> validate that helper alignment preserves the worker-only readiness boundary

### 4. HOME_AUDIO_ALIGNMENT

- `MCR-010` -> implement canonical home-audio composition in `backend/app/services/courses_service.py`
- `MCR-011` -> rewrite `backend/app/routes/home.py` to consume canonical home-audio composition only
- `MCR-012` -> validate that home-audio output uses unified media composition without invented runtime columns

### 5. MEDIA_VERIFICATION

- `MCR-013` -> aggregate verification of the resolved media-conflict cluster

## DEPENDENCY SUMMARY

- Root: `MCR-001`
- The primary phase spine is intentionally linear; recovery subtasks must follow their explicit `DEPENDS_ON` edges.
- If any executor computes a wider ready set anyway, lexical tie-break by `TASK_ID` is mandatory.
- No phase begins until the predecessor phase gate passes.
- Verification precondition for `MCR-003F6` closure is `MCR-003F6V0 -> MCR-003F6V1 -> MCR-003F6`.
- Recovery chain for the MCR-003F branch is `MCR-003F4 -> MCR-003F6 -> MCR-003F5 -> MCR-003F3 -> MCR-003F`.
- `MCR-003F6` owns route-level legacy removal in `backend/app/routes/api_media.py`.
- `MCR-003F5` owns helper-level cleanup in `backend/app/utils/media_urls.py`.

## MATERIALIZED TASK FILES

- [MCR-001_delete_api_media_sign_adapter.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-001_delete_api_media_sign_adapter.md)
- [MCR-002_delete_legacy_media_routes.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-002_delete_legacy_media_routes.md)
- [MCR-003_gate_legacy_media_path_removal.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-003_gate_legacy_media_path_removal.md)
- [MCR-004_rewrite_api_media_runtime_assumptions.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-004_rewrite_api_media_runtime_assumptions.md)
- [MCR-005_rewrite_courses_service_runtime_composition.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-005_rewrite_courses_service_runtime_composition.md)
- [MCR-006_gate_runtime_media_alignment.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-006_gate_runtime_media_alignment.md)
- [MCR-007_implement_media_asset_state_helpers.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-007_implement_media_asset_state_helpers.md)
- [MCR-008_rewrite_api_media_helper_usage.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-008_rewrite_api_media_helper_usage.md)
- [MCR-009_gate_media_asset_helper_alignment.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-009_gate_media_asset_helper_alignment.md)
- [MCR-010_implement_home_audio_composition.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-010_implement_home_audio_composition.md)
- [MCR-011_rewrite_home_audio_route.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-011_rewrite_home_audio_route.md)
- [MCR-012_gate_home_audio_alignment.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-012_gate_home_audio_alignment.md)
- [MCR-013_media_verification_aggregate.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-013_media_verification_aggregate.md)
- [MCR-003F4_remove_media_signer_legacy_field_handling_and_upload_dependency.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-003F4_remove_media_signer_legacy_field_handling_and_upload_dependency.md)
- [MCR-003F6V0_restore_local_verification_baseline.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-003F6V0_restore_local_verification_baseline.md)
- [MCR-003F6V1_restore_test_runtime_repository_import_integrity.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-003F6V1_restore_test_runtime_repository_import_integrity.md)
- [MCR-003F6_remove_api_media_preview_fallback_and_debug_signed_url_leak.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-003F6_remove_api_media_preview_fallback_and_debug_signed_url_leak.md)
- [MCR-003F5_remove_media_urls_legacy_field_carry_path.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-003F5_remove_media_urls_legacy_field_carry_path.md)
- [MCR-003F3_remove_out_of_scope_backend_runtime_and_test_legacy_field_dependencies.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-003F3_remove_out_of_scope_backend_runtime_and_test_legacy_field_dependencies.md)
- [MCR-003F_remove_profile_community_legacy_media_field_contract.md](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/MCR-003F_remove_profile_community_legacy_media_field_contract.md)
- [task_manifest.json](/home/robin/Aveli/actual_truth/DETERMINED_TASKS/media_conflict_resolution/task_manifest.json)
