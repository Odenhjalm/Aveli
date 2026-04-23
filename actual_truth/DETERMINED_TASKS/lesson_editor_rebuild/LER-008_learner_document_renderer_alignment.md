# LER-008 LEARNER DOCUMENT RENDERER ALIGNMENT

TYPE: `OWNER`
TASK_TYPE: `LEARNER_RENDERER_ALIGNMENT`
DEPENDS_ON: `[LER-007]`

## Goal

Align learner lesson rendering to `lesson_document_v1`.

## Required Outputs

- learner lesson read path returns or composes document content
- learner renderer uses the same document rendering rules as Preview Mode
- learner media rendering uses backend-authored governed media
- learner access rules remain unchanged

## Forbidden

- using Markdown as learner content truth for rebuilt lessons
- constructing media URLs on the frontend
- changing enrollment or drip access semantics

## Verification

Learner rendering tests prove parity with Preview Mode for document content,
media nodes, CTA nodes, headings, lists, and inline marks.

## Stop Conditions

Stop if learner response shape ownership conflicts with public-surface contract
law after LER-001.

## Execution Record

DATE: `2026-04-23`

STATUS: `COMPLETED`

Learner lesson rendering now uses `lesson_document_v1` as the content truth.
The protected learner content surface composes `content_document`, frontend
lesson detail parsing requires `content_document`, and learner rendering uses
the same `LessonDocumentPreview` block/inline/list/CTA rules as Course Editor
Preview Mode.

## Materialized Outputs

- `backend/app/schemas/__init__.py` exposes learner lesson content as
  `content_document`.
- `backend/app/repositories/courses.py` reads `content_document` from
  `app.lesson_content_surface`.
- `backend/app/services/courses_service.py` canonicalizes the protected learner
  `content_document` before response composition.
- `frontend/lib/features/courses/data/courses_repository.dart` parses learner
  lesson content into `LessonDocument` and rejects legacy `content_markdown` in
  learner content payloads.
- `frontend/lib/features/courses/presentation/lesson_page.dart` renders learner
  content from `LessonDocument`, not Markdown, and uses backend-authored media
  objects for image, audio, video, and document blocks.
- `frontend/lib/editor/document/lesson_document_editor.dart` exposes the shared
  document preview renderer with injectable media rendering and CTA/link launch
  handling.
- Learner tests now prove document content, media nodes, CTA nodes, headings,
  lists, and inline marks render without Markdown tokens.
- Source gates now fail if learner rendering reintroduces Quill, Markdown
  conversion, or `contentMarkdown` as the learner content authority.

## Verification Evidence

- `python -m py_compile backend\app\schemas\__init__.py backend\app\repositories\courses.py backend\app\services\courses_service.py backend\tests\test_surface_based_lesson_reads.py backend\tests\test_protected_lesson_content_surface_gate.py backend\tests\test_lesson_media_rendering.py backend\tests\test_write_path_dominance_regression.py`
- `flutter analyze lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart lib\features\courses\data\courses_repository.dart lib\features\courses\presentation\lesson_page.dart test\unit\courses_repository_access_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\unit\studio_repository_lesson_media_routing_test.dart test\unit\courses_repository_access_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_lesson_supported_content_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_write_path_dominance_regression.py backend\tests\test_surface_based_lesson_reads.py backend\tests\test_protected_lesson_content_surface_gate.py backend\tests\test_lesson_media_rendering.py backend\tests\test_studio_course_lessons.py::test_studio_lessons_belong_directly_to_course backend\tests\test_courses_studio.py::test_studio_course_and_lesson_endpoints_follow_canonical_shape -q`

## Successor

`LER-009` is now eligible: remove or quarantine remaining legacy
Markdown/Quill authority paths after document save, preview, learner rendering,
media, and CTA replacements exist.
