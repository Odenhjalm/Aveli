# LER-010 DOCUMENT FIXTURE AND TEST CORPUS

TYPE: `GATE`
TASK_TYPE: `TEST_ALIGNMENT`
DEPENDS_ON: `[LER-003, LER-006, LER-008]`

## Goal

Create a document-model fixture corpus and tests for all required editor
capabilities.

## Required Outputs

- document fixture corpus for required node and mark combinations
- backend validation tests
- frontend model tests
- editor widget tests
- preview persisted-only tests
- learner renderer parity tests
- ETag conflict tests

## Required Feature Coverage

- bold
- italic
- underline
- clear formatting
- headings
- bullet lists
- ordered lists
- image
- audio
- video
- document
- magic-link / CTA
- persisted preview
- ETag concurrency

## Forbidden

- relying on Markdown round-trip tests as rebuilt-editor proof
- leaving newline-count fixtures as paragraph authority

## Verification

All required fixture cases pass in backend and frontend test suites.

## Stop Conditions

Stop if any required feature lacks a document fixture and an executable test.

## Execution Record

DATE: `2026-04-23`

STATUS: `COMPLETED`

The active positive fixture corpus for the rebuilt editor now exists as
`lesson_document_v1` JSON and is consumed by backend and frontend tests. The
corpus covers all required editor capabilities without using Markdown
round-trip fixtures, newline-count paragraph authority, Quill Delta, or
legacy `content_markdown` as proof.

## Materialized Outputs

- Added `actual_truth/contracts/lesson_document_fixture_corpus.json` as the
  active rebuilt-editor corpus.
- Added `actual_truth/contracts/lesson_document_fixture_corpus.md` to define
  corpus status, required coverage, execution binding, and forbidden legacy
  evidence.
- Added `backend/tests/test_lesson_document_fixture_corpus.py` to validate
  corpus status, coverage, document shapes, governed media rows, clear
  formatting semantics, ETag canonical JSON behavior, and real runtime/test
  path bindings.
- Added `frontend/test/helpers/lesson_document_fixture_corpus.dart` so Flutter
  tests load the same corpus artifact instead of duplicating ad hoc fixtures.
- Extended frontend model tests to parse, validate, and canonicalize every
  corpus document field.
- Extended editor widget tests to render the full positive corpus authoring
  document and to run persisted preview from saved corpus content only.
- Extended learner renderer tests to render the full positive corpus through
  the same document renderer path as preview.
- Bound the frontend ETag content-write test to the corpus
  `etag_concurrency.updated_document` fixture.

## Capability Coverage

- Formatting: `bold`, `italic`, `underline`, `clear_formatting`
- Blocks: `heading`, `bullet_list`, `ordered_list`
- Media: `image`, `audio`, `video`, `document`
- CTA: `magic_link_cta`
- Runtime authority gates: `persisted_preview`, `etag_concurrency`

## Verification Evidence

- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_lesson_document_fixture_corpus.py -q`
- `flutter test test\widgets\lesson_document_editor_test.dart`
- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_lesson_document_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_studio_lesson_document_content_api.py -q`

## Successor

`LER-011` is now eligible: add deterministic audit gates that fail if
Markdown, Quill Delta, backend Flutter validation, draft preview, or client
media URL construction returns as rebuilt editor authority.
