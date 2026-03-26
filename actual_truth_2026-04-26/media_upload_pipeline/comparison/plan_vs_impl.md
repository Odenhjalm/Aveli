# media_upload_pipeline — planned vs implemented

## planned sources
- `actual_truth_2026-04-26/Aveli_System_Decisions.md`
- `docs/media_pipeline.md`
- `docs/MEDIA_CONTRACT_v1.md`
- `docs/storage_buckets.md`
- `docs/direct_uploads.md`
- `docs/media_forensic_report_20260123.md`
- `docs/media_control_plane/media_pipeline_audit_2026-03-14.md`
- `media_contract_implementation.md`
- `homeplayer_audit_for_media_control_plane.md`

## implemented sources
- `backend/app/routes/api_media.py`
- `backend/app/routes/studio.py`
- `backend/app/repositories/media_assets.py`
- `backend/app/services/media_transcode_worker.py`
- `backend/app/utils/media_paths.py`
- `backend/app/utils/media_signer.py`
- `frontend/lib/api/api_paths.dart`
- `frontend/lib/features/media/data/media_pipeline_repository.dart`
- `frontend/lib/features/studio/data/studio_repository.dart`
- `frontend/lib/features/studio/widgets/home_player_upload_dialog.dart`
- `frontend/landing/lib/studioUploads.ts`

## system should be
- Upload creation, completion, attachment, and playback signing should flow through one canonical media-asset contract.
- Lesson uploads and Home uploads should converge on the same upload-url and completion semantics before projection-specific attach steps.
- Active frontend signing paths and lifecycle docs should resolve against mounted backend surfaces only.

## system is
- `/api/media/upload-url`, `/api/media/complete`, `/api/media/attach`, and `/api/media/playback` are implemented.
- Home WAV uploads now call `MediaPipelineRepository.completeUpload()` before creating the Home library projection row, so the generic completion surface is already in use.
- Flutter studio lesson-audio upload uses the pipeline path, but Next landing uploads and the legacy studio direct-upload flow still use `/studio/lessons/{lesson_id}/media/presign` plus `/studio/lessons/{lesson_id}/media/complete`.
- `docs/media_pipeline.md` still treats `/api/media/playback-url` and `media_asset_id` playback as canonical, and `docs/storage_buckets.md` plus `docs/direct_uploads.md` still describe `/studio/lessons/{lesson_id}/media/presign` as the canonical lesson-upload contract.
- `frontend/lib/api/api_paths.dart` still points `mediaSign` at `/api/media/sign`, while mounted backend logic remains `/media/sign`.

## mismatches
- `[blocking] api_align_media_sign_route` — current frontend sign path and mounted backend sign path do not match.
- `[important] media_align_lesson_upload_surfaces` — lesson uploads and lesson-upload docs still treat `studio.py` presign/complete endpoints as canonical instead of converging on the `/api/media/*` lifecycle.
