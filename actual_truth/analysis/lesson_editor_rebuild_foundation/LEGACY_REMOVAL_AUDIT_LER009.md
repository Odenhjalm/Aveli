# LEGACY REMOVAL AUDIT LER-009

DATE: `2026-04-23`

SCOPE: deterministic removal or quarantine of legacy Markdown and Quill
authority after document save, persisted preview, learner rendering, media, and
CTA document paths were materialized.

## Contract Decision

The current Quill-to-Markdown pipeline is legacy evidence, not rebuild
authority. LER-009 therefore removes code that existed only to support Quill
Delta, Markdown round trips, Flutter-backed backend Markdown validation, or
Markdown media-token rendering in rebuilt editor paths.

## Removed Frontend Authority

- Removed Quill/Markdown editor adapters under `frontend/lib/editor/adapter`.
- Removed Markdown integrity guard and Quill Delta normalizer.
- Removed Quill editor session/controller scaffolding.
- Removed the Course Editor JS test bridge tied to controller identity.
- Removed legacy Markdown rendering/storage pipeline and Quill embed insertion
  helpers from `frontend/lib/shared/utils`.
- Removed legacy Markdown roundtrip CLI/harness files under `frontend/tool`.
- Removed legacy Markdown normalization/unit tests that forced Markdown
  preservation.
- Removed `flutter_quill`, `flutter_quill_extensions`, `markdown_quill`, and
  `markdown_widget` from Flutter dependencies and plugin registration.

## Removed Backend Authority

- Removed `backend/app/utils/lesson_markdown_validator.py`; backend validation
  no longer shells out to Flutter.
- Changed course publish readiness to validate `content_document` via
  `lesson_document_validator`, not `content_markdown` normalization.
- Changed publish lesson reads to project `content_document` as publish
  content authority.
- Removed unused legacy `StudioLessonCreate` / `StudioLessonUpdate` schemas
  that accepted `content_markdown`.

## Quarantined Compatibility

The repository still contains `content_markdown` database compatibility code in
old repository helpers and legacy scripts. That code is not reachable from the
rebuilt editor save path, persisted preview path, learner render path, backend
document validation, or publish readiness. It remains legacy compatibility only
and must not be used as new editor authority.

## Source Gate Result

Active rebuilt paths were checked for these forbidden authority tokens:

- `flutter_quill`
- `QuillController`
- `quill_delta`
- `markdown_quill`
- `markdown_widget`
- `markdown_to_editor`
- `editor_to_markdown`
- `lesson_markdown_integrity_guard`
- `lesson_content_pipeline`
- `lesson_markdown_validator`
- `validate_lesson_markdown`

No forbidden token remains in active frontend app code, active frontend tests,
frontend tools, or backend app code, except explicit regression-test strings
that assert the removed paths stay removed.

## Verification Evidence

- `flutter analyze lib\main.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart`
- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\unit\courses_repository_access_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
- `.\.venv\Scripts\python.exe -m py_compile backend\app\schemas\__init__.py backend\app\repositories\courses.py backend\app\services\courses_service.py backend\tests\test_course_publish_authority.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_studio_lesson_document_content_api.py backend\tests\test_course_publish_authority.py backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_surface_based_lesson_reads.py backend\tests\test_lesson_media_rendering.py backend\tests\test_protected_lesson_content_surface_gate.py -q`

## Next Edge

`LER-010` is now eligible: build the positive document fixture corpus and tests
for every required editor capability after legacy authority has been removed.
