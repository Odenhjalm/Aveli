# LER-006 MEDIA CTA DOCUMENT OPERATIONS

TYPE: `OWNER`
TASK_TYPE: `MEDIA_CTA_ALIGNMENT`
DEPENDS_ON: `[LER-005]`

## Goal

Move media and magic-link/CTA authoring into first-class document operations.

## Required Outputs

- image, audio, video, and document insertion create media nodes
- media nodes reference `lesson_media_id`
- CTA insertion creates CTA nodes
- validators reject invalid media and CTA nodes
- save persists media and CTA nodes as `content_document`

## Forbidden

- using Markdown media tokens as new editor authority
- using document links as incidental Markdown link rewrites
- storing frontend-resolved media URLs
- storing `runtime_media` as document truth

## Verification

Tests prove media and CTA nodes survive save, reload, preview, and learner
rendering without Markdown token conversion.

## Stop Conditions

Stop if a media node cannot be validated against lesson-owned governed media.

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Retrieval Inputs

- `actual_truth/DETERMINED_TASKS/lesson_editor_rebuild/LER-006_media_cta_document_operations.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/editor/document/lesson_document.dart`
- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/test/unit/studio_repository_lesson_content_read_test.dart`
- `backend/tests/test_lesson_document_content_backend_contract.py`
- `backend/tests/test_write_path_dominance_regression.py`

### Materialized Changes

- Course Editor media insertion now writes media document blocks through
  `_lessonDocument.insertMedia`.
- Image, audio, video, and document insertion dispatch directly from governed
  `lesson_media_id` to document media nodes.
- The remaining video/audio insertion path no longer creates or parses
  Markdown/media-token embed values as an intermediate authority.
- Magic-link / CTA insertion writes `LessonCtaBlock` through
  `_lessonDocument.insertCta`.
- Backend document validation already rejects invalid media and CTA shapes; the
  service test now proves governed media rows are required before persistence.
- Studio repository tests now prove media and CTA nodes survive read and save as
  `content_document`, with no `content_markdown` payload.
- Course Editor source gates now fail if media insertion reintroduces
  `!image`, `!audio`, `!video`, `!document`, legacy embed parsing, or document
  link rewrite authority.
- The active fixture corpus was realigned away from removed Quill/Markdown
  tests and toward `lesson_document_v1` bindings.

### Test-Prune Audit

See:

- `actual_truth/analysis/lesson_editor_rebuild_foundation/TEST_PRUNE_AUDIT_LER006.md`

### Post-Task Audit

- The stop condition is satisfied for the write path: backend
  `validate_lesson_document` checks each media node against lesson-owned media
  rows returned by `list_studio_lesson_media`.
- Course Editor authoring/save now treats media and CTA as document nodes, not
  Markdown tokens or document-link rewrites.
- Legacy learner rendering still consumes Markdown and is intentionally left for
  `LER-008`; this task did not claim learner renderer replacement.
- Persisted preview already renders `LessonDocumentPreview`, but shared preview
  renderer hardening remains the next DAG task, `LER-007`.

### Verification Evidence

- `dart format frontend\test\unit\studio_repository_lesson_content_read_test.dart frontend\test\unit\studio_repository_lesson_media_routing_test.dart frontend\test\widgets\lesson_document_editor_test.dart frontend\lib\features\studio\presentation\course_editor_page.dart`
- `python -m json.tool actual_truth\contracts\lesson_supported_content_fixture_corpus.json > $null`
- `python -m py_compile backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_courses_studio.py backend\tests\test_studio_course_lessons.py`
- `flutter analyze lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart lib\features\studio\data\studio_models.dart lib\features\studio\data\studio_repository.dart lib\features\studio\presentation\course_editor_page.dart test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\widgets\lesson_document_editor_test.dart`
- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\widgets\lesson_document_editor_test.dart`
- `.venv\Scripts\python.exe -m pytest backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_write_path_dominance_regression.py -q`
- `.venv\Scripts\python.exe -m pytest backend\tests\test_studio_course_lessons.py::test_studio_lessons_belong_directly_to_course backend\tests\test_courses_studio.py::test_studio_course_and_lesson_endpoints_follow_canonical_shape -q`

## Successor State

`LER-007` is now eligible.
