# 0009I_remove_fallbacks

TASK_ID: T009
STATUS: COMPLETE
TYPE: OWNER
PURPOSE: Ta bort kvarvarande legacy media-fallbacks och fallback-konfiguration så att kanonisk runtime failar explicit i stället för att reparera via legacy paths.
FILES AFFECTED:
- backend/app/config.py
- backend/app/models.py
- backend/app/routes/media.py
- backend/app/routes/upload.py
- backend/app/routes/studio.py
- backend/app/utils/media_signer.py
- backend/app/services/lesson_playback_service.py
- backend/tests/test_media_signer.py
- backend/tests/test_course_cover_pipeline.py
- backend/tests/test_media_preview_batch_unit.py
DEPENDS_ON:
- T005
- T006
DONE_WHEN:
- `media_allow_legacy_media` finns inte längre som runtime-konfiguration.
- Ingen aktiv kodväg använder `resolve_legacy_playback`, `resolve_object_media_playback` eller legacy media coalesce-fallback som systembeteende.
- Legacy media-routes och upload-paths failar explicit eller är borttagna.
VALIDATION:
- `rg "media_allow_legacy_media|resolve_legacy_playback|resolve_object_media_playback" backend/app frontend/lib` visar inga aktiva runtime-paths kvar.
- `rg "coalesce\\(ma\\.streaming_object_path, ma\\.original_object_path|ma\\.original_object_path\\)" backend/app/models.py backend/app/routes/media.py` visar ingen aktiv playback-fallback.
- Riktad media-verifiering visar explicit fail-closed i stället för fallback.
