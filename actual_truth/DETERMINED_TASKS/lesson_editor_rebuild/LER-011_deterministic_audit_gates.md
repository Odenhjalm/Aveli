# LER-011 DETERMINISTIC AUDIT GATES

TYPE: `GATE`
TASK_TYPE: `AUDIT_GATES`
DEPENDS_ON: `[LER-009, LER-010]`

## Goal

Add deterministic gates that prevent legacy editor authority from returning.

## Required Outputs

- grep or AST-based gates for forbidden rebuilt-editor imports and calls
- route/schema gates for `content_document` authority
- dependency gates for editor-only Markdown/Quill packages
- preview authority gate proving persisted-only rendering
- backend validation gate proving no Flutter harness call

## Forbidden Patterns

- `serializeEditorDeltaToCanonicalMarkdown` in new save path
- `validateLessonMarkdownIntegrity` in new save path
- backend `lesson_markdown_validator` in new validation path
- `content_markdown` as rebuilt-editor authority
- frontend media URL construction for governed media
- draft state as Preview Mode authority

## Verification

Audit gates fail on seeded forbidden patterns and pass on the final intended
state.

## Stop Conditions

Stop if a forbidden pattern cannot be made precise enough to avoid false
authority from comments, legacy quarantine, or compatibility-only code.

## Execution Record

DATE: `2026-04-23`

STATUS: `COMPLETED`

Deterministic audit gates now exist for the rebuilt editor authority boundary.
The gates include seeded forbidden-pattern checks and scoped runtime checks, so
they prove both that the detectors fail on known-bad patterns and that the
current repository state passes.

## Materialized Outputs

- Added `tools/lesson_editor_authority_audit.py` with reusable token,
  regex, Dart block, and Python route-block audit helpers.
- Added `backend/tests/test_ler011_deterministic_audit_gates.py` as the
  executable LER-011 gate.
- Seeded forbidden-pattern tests now prove detection for:
  - legacy Markdown/Quill save authority
  - backend Flutter/Markdown validation authority
  - draft document Preview Mode authority
  - frontend-governed media URL construction
  - removed editor-only Markdown/Quill dependencies
- Runtime-scoped gates now prove:
  - editor authoring paths have no legacy Markdown/Quill authority tokens
  - studio content transport uses `content_document`, `If-Match`, and `ETag`
  - backend content routes/schemas use `content_document`
  - backend validation does not call Flutter or Markdown validators
  - Course Editor Preview Mode uses persisted backend reads only
  - frontend governed-media paths do not use legacy preview URL construction
  - removed editor-only Markdown/Quill dependencies stay removed
- Removed the stale frontend `ApiPaths.mediaPreviews` constant and associated
  `ApiClient` guard for `/api/lesson-media/previews`; the studio preview path
  now remains governed by media-placement reads.

## Verification Evidence

- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_ler011_deterministic_audit_gates.py -q`
- `flutter analyze lib\api\api_client.dart lib\api\api_paths.dart lib\features\studio\data\studio_repository.dart lib\features\studio\data\studio_repository_lesson_media.dart`
- `flutter test test\unit\media_upload_url_contract_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\unit\lesson_media_preview_cache_test.dart`
- `.\.venv\Scripts\python.exe -m py_compile tools\lesson_editor_authority_audit.py backend\tests\test_ler011_deterministic_audit_gates.py`
- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\unit\media_upload_url_contract_test.dart test\unit\lesson_media_preview_cache_test.dart test\unit\courses_repository_access_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_ler011_deterministic_audit_gates.py backend\tests\test_lesson_document_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_studio_lesson_document_content_api.py backend\tests\test_course_publish_authority.py backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_surface_based_lesson_reads.py backend\tests\test_lesson_media_rendering.py backend\tests\test_protected_lesson_content_surface_gate.py -q`

## Successor

`LER-012` is now eligible: run the final aggregate editor rebuild gate across
contracts, backend, frontend, corpus, dependency, preview, learner renderer,
media, CTA, concurrency, and legacy-authority audit evidence.
