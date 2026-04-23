# DETERMINISTIC AUDIT GATES LER-011

DATE: `2026-04-23`

## Scope

LER-011 adds automated gates that keep forbidden legacy authority from
returning after LER-009 removal and LER-010 positive corpus coverage.

## Pre-Task Finding

`backend/tests/test_write_path_dominance_regression.py` already contained
several source gates, but there was not yet a dedicated LER-011 gate that also
proved detector behavior against seeded known-bad inputs.

An additional stale frontend artifact still existed:

`frontend/lib/api/api_paths.dart`

It exposed `ApiPaths.mediaPreviews = /api/lesson-media/previews` even though
the rebuilt editor preview path reads governed media placements instead.

## Materialized Gate

Executable gate:

`backend/tests/test_ler011_deterministic_audit_gates.py`

Shared audit helper:

`tools/lesson_editor_authority_audit.py`

## Seeded Failure Coverage

The gate proves detection for synthetic source containing:

- `serializeEditorDeltaToCanonicalMarkdown`
- `validateLessonMarkdownIntegrity`
- `flutter_quill`
- `contentMarkdown`
- backend `lesson_markdown_validator`
- backend `subprocess` / `flutter` validation
- Preview Mode rendering `_lessonDocument`
- `/api/lesson-media/previews`
- `resolved_preview_url`
- removed editor-only Markdown/Quill dependency declarations

## Runtime Pass Coverage

The gate verifies current runtime surfaces:

- Course Editor authoring and document editor files contain no legacy
  Markdown/Quill authority tokens.
- Studio repository content read/write uses only `content_document`,
  `If-Match`, and `ETag`.
- Backend content route and schemas use `content_document` with extra fields
  forbidden.
- Backend validation uses native `lesson_document_v1` validation, not Flutter
  or Markdown round trips.
- Course Editor Preview Mode loads persisted content through
  `readLessonContent` and renders `LessonDocumentPreview`.
- Frontend governed-media editor paths do not use legacy preview endpoint
  strings, storage paths, signed URLs, or resolved-preview URL fields.
- `flutter_quill`, `markdown_quill`, `markdown_widget`, and editor-only
  Markdown dependencies remain absent.

## Removal

Removed stale frontend legacy preview endpoint authority:

- `ApiPaths.mediaPreviews`
- `ApiClient._mediaPreviewContractViolation`

The canonical preview/media read path remains:

`GET /api/media-placements/{lesson_media_id}`

## Verification

Passed:

- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_ler011_deterministic_audit_gates.py -q`
- `flutter analyze lib\api\api_client.dart lib\api\api_paths.dart lib\features\studio\data\studio_repository.dart lib\features\studio\data\studio_repository_lesson_media.dart`
- `flutter test test\unit\media_upload_url_contract_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\unit\lesson_media_preview_cache_test.dart`
- `.\.venv\Scripts\python.exe -m py_compile tools\lesson_editor_authority_audit.py backend\tests\test_ler011_deterministic_audit_gates.py`
- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\unit\media_upload_url_contract_test.dart test\unit\lesson_media_preview_cache_test.dart test\unit\courses_repository_access_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_ler011_deterministic_audit_gates.py backend\tests\test_lesson_document_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_studio_lesson_document_content_api.py backend\tests\test_course_publish_authority.py backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_surface_based_lesson_reads.py backend\tests\test_lesson_media_rendering.py backend\tests\test_protected_lesson_content_surface_gate.py -q`

Backend pytest emitted only the existing Sentry/python_multipart warning.

## Result

LER-011 is complete. The next deterministic DAG step is LER-012.
