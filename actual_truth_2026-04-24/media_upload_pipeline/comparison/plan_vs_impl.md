# media_upload_pipeline — planned vs implemented

## planned sources
- docs/media_pipeline.md
- docs/storage_buckets.md
- docs/MEDIA_CONTRACT_v1.md
- docs/media_forensic_report_20260123.md
- docs/media_control_plane/media_pipeline_audit_2026-03-14.md
- docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md
- homeplayer_audit_for_media_control_plane.md

## implemented sources
- backend/app/routes/upload.py
- backend/app/routes/api_media.py
- backend/app/routes/studio.py
- backend/app/services/media_transcode_worker.py
- backend/app/utils/media_signer.py
- frontend/lib/services/media_service.dart
- frontend/lib/features/media/data/media_repository.dart
- frontend/lib/features/media/data/media_pipeline_repository.dart
- frontend/lib/features/media/application/media_providers.dart
- frontend/test/widgets/wav_upload_card_test.dart

## gaps
- Contract/state rules are documented for a fuller canonical pipeline than is explicit in the current runtime file evidence.
- Legacy/public versus pipeline/private handling is present in docs and remains a partially validated boundary.
- Some runtime-facing behavior is represented in tests and helpers rather than centralized API docs.

## contradictions
- Documentation emphasizes one canonical contract, while route/service evidence shows mixed upload/playback implementation patterns across legacy and pipeline paths.
