# LER-009 LEGACY MARKDOWN QUILL REMOVAL

TYPE: `OWNER`
TASK_TYPE: `LEGACY_REMOVAL`
DEPENDS_ON: `[LER-003, LER-008]`

## Goal

Remove or quarantine legacy Markdown and Quill authority paths.

## Required Outputs

- new editor save path has no Markdown adapter dependency
- new preview and learner paths have no Markdown renderer dependency
- backend validation no longer uses Flutter harness
- Quill-specific patches are removed or quarantined outside new editor authority
- dependencies used only for old editor authority are removed when safe

## Forbidden

- keeping legacy paths reachable as fallback authority
- leaving tests that force the rebuilt editor to preserve Markdown round trips
- preserving code only because it was patched recently

## Verification

Repo-wide gates show no forbidden legacy authority imports remain in rebuilt
editor, preview, learner, or backend validation paths.

## Stop Conditions

Stop if a legacy module is still required by a non-editor canonical domain and
cannot be safely split.

## Execution Record

DATE: `2026-04-23`

STATUS: `COMPLETED`

Legacy Markdown/Quill authority has been removed from the rebuilt editor
surface. Course Editor no longer constructs a Quill controller/session, the
frontend no longer ships the Quill/Markdown adapter, guard, normalization,
roundtrip harness, or legacy render pipeline, and backend validation no longer
contains the Flutter Markdown validator.

## Materialized Outputs

- Removed frontend Quill/Markdown adapter files under
  `frontend/lib/editor/adapter`.
- Removed frontend Markdown integrity guard, Quill Delta normalizer, and Quill
  session/controller scaffolding.
- Removed Course Editor controller/test-bridge code and renamed the remaining
  async safety token to document request authority.
- Removed `lesson_content_pipeline.dart`, `quill_embed_insertion.dart`, and
  legacy roundtrip tools.
- Removed legacy Markdown normalization/roundtrip tests that forced the rebuild
  to preserve Markdown semantics.
- Removed `flutter_quill`, `flutter_quill_extensions`, `markdown_quill`, and
  `markdown_widget` from Flutter dependencies and plugin registration.
- Removed `backend/app/utils/lesson_markdown_validator.py`.
- Changed publish readiness to validate and inspect `content_document` via
  `lesson_document_validator` instead of `content_markdown`.
- Added deterministic source gates proving the removed files and forbidden
  dependencies stay out of rebuilt editor, preview, learner, and backend
  validation paths.
- Updated the legacy fixture corpus binding so preview/learner tests bind to
  document rendering instead of the deleted Markdown pipeline.

## Quarantine Decision

`content_markdown` still exists as legacy database compatibility in old
repository helpers, scripts, and explicit rejection tests. It is not reachable
from new editor save, persisted preview, learner rendering, backend document
validation, or publish readiness.

## Verification Evidence

- `flutter pub get`
- `dart format lib\features\studio\presentation\course_editor_page.dart lib\main.dart`
- `ruff format backend\app\services\courses_service.py backend\app\repositories\courses.py backend\app\schemas\__init__.py backend\tests\test_course_publish_authority.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_lesson_supported_content_fixture_corpus.py`
- `flutter analyze lib\main.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart`
- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\unit\courses_repository_access_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
- `.\.venv\Scripts\python.exe -m py_compile backend\app\schemas\__init__.py backend\app\repositories\courses.py backend\app\services\courses_service.py backend\tests\test_course_publish_authority.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_studio_lesson_document_content_api.py backend\tests\test_course_publish_authority.py backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_surface_based_lesson_reads.py backend\tests\test_lesson_media_rendering.py backend\tests\test_protected_lesson_content_surface_gate.py -q`

## Successor

`LER-010` is now eligible: create the document fixture corpus and tests for
all required editor capabilities, persisted preview, media/CTA, and ETag
concurrency.
