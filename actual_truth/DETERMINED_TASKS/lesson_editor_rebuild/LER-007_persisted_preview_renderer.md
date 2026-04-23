# LER-007 PERSISTED PREVIEW RENDERER

TYPE: `OWNER`
TASK_TYPE: `PREVIEW_ALIGNMENT`
DEPENDS_ON: `[LER-006]`

## Goal

Render Course Editor Preview Mode from persisted `content_document` only.

## Required Outputs

- preview loads saved `content_document`
- preview uses the document renderer
- preview renders governed media through backend-authored media objects
- preview does not render unsaved editor draft state
- preview remains read-only

## Forbidden

- rendering local draft document state in Preview Mode
- rendering local Markdown in Preview Mode
- using preview cache as content authority
- adding a Preview mutation API

## Verification

Widget tests prove unsaved edits do not appear in Preview Mode and saved
document content does appear.

## Stop Conditions

Stop if persisted preview cannot be distinguished from draft authoring state.

## Execution Record

DATE: `2026-04-23`

STATUS: `COMPLETED`

Implemented Course Editor Preview Mode as a persisted-only document read path.
Preview now reads `content_document` from the dedicated lesson content endpoint,
hydrates only media IDs embedded in that persisted document through backend
placement reads, and renders via `LessonDocumentPreview`.

## Materialized Outputs

- `frontend/lib/features/studio/presentation/course_editor_page.dart` loads
  preview state from `readLessonContent`.
- Preview media is derived from persisted document media references, then read
  through `fetchLessonMediaPlacements`.
- Preview rendering uses `LessonDocumentPreview(document: ..., media: ...)`.
- Preview state is cleared when preview mode is entered, exited, reset, or
  fails, preventing stale preview authority.
- `frontend/lib/editor/document/lesson_document_editor.dart` renders media
  blocks from backend-authored preview media objects.
- `frontend/test/widgets/lesson_document_editor_test.dart` proves saved
  document content appears and unsaved draft content does not.
- `backend/tests/test_write_path_dominance_regression.py` gates the Course
  Editor preview implementation against draft document, draft media, Markdown,
  cache, and mutation authority.

## Verification Evidence

- `dart format lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart test\widgets\lesson_document_editor_test.dart`
- `python -m py_compile backend\tests\test_write_path_dominance_regression.py`
- `flutter analyze lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart lib\features\studio\data\studio_models.dart lib\features\studio\data\studio_repository.dart lib\features\studio\presentation\course_editor_page.dart test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\widgets\lesson_document_editor_test.dart`
- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\widgets\lesson_document_editor_test.dart`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_studio_course_lessons.py::test_studio_lessons_belong_directly_to_course backend\tests\test_courses_studio.py::test_studio_course_and_lesson_endpoints_follow_canonical_shape -q`

## Successor

`LER-008` is now eligible: learner rendering must align to the same
document-renderer authority.
