# DOCUMENT FIXTURE CORPUS AUDIT LER-010

DATE: `2026-04-23`

## Scope

Audit target:

- `actual_truth/contracts/lesson_document_fixture_corpus.json`
- `actual_truth/contracts/lesson_document_fixture_corpus.md`
- backend corpus validation tests
- frontend corpus loader and corpus-bound tests

## Pre-Task Finding

The repository had document-model tests and a downgraded legacy Markdown
compatibility corpus, but it did not have an active positive
`lesson_document_v1` corpus that all rebuilt editor capability tests could
share.

This was a coverage gap because LER-010 requires the rebuild to prove all
required editor capabilities from document truth, not from Markdown round trips
or per-test local fixtures.

## Materialized Decision

The active positive corpus is:

`actual_truth/contracts/lesson_document_fixture_corpus.json`

It is explicitly marked `ACTIVE_REBUILT_EDITOR_AUTHORITY` and stores fixtures
as `lesson_document_v1` JSON only.

## Coverage Audit

The corpus contains positive coverage for:

- `bold`
- `italic`
- `underline`
- `clear_formatting`
- `heading`
- `bullet_list`
- `ordered_list`
- `image`
- `audio`
- `video`
- `document`
- `magic_link_cta`
- `persisted_preview`
- `etag_concurrency`

Every capability has at least one fixture id in `capability_coverage`, and
backend tests fail if any required capability lacks fixture coverage.

## Authority Audit

The corpus does not use:

- Markdown media tokens as document truth
- `content_markdown`
- Quill Delta
- frontend draft preview state as persisted truth
- frontend-authored media URLs inside document nodes
- backend Flutter subprocess validation

Resolved URLs exist only in `media_rows`, where they represent backend-authored
read projection data for renderer tests.

## Executable Binding Audit

Backend binding:

- `backend/tests/test_lesson_document_fixture_corpus.py` loads the JSON corpus
  directly and validates every document payload with
  `lesson_document_validator`.
- The same backend test verifies media-row governance, clear-formatting
  expectations, ETag canonical JSON behavior, and declared runtime/test file
  existence.

Frontend binding:

- `frontend/test/helpers/lesson_document_fixture_corpus.dart` loads the same
  JSON artifact from Flutter tests.
- `frontend/test/unit/lesson_document_model_test.dart` validates model parsing,
  canonical JSON, local media validation, and clear-formatting behavior.
- `frontend/test/widgets/lesson_document_editor_test.dart` renders the corpus
  authoring document and persisted preview fixture.
- `frontend/test/widgets/lesson_preview_rendering_test.dart` renders the full
  corpus through the learner renderer.
- `frontend/test/unit/studio_repository_lesson_content_read_test.dart` uses
  the corpus ETag document for the content write payload.

## Verification

Passed:

- `flutter test test\unit\lesson_document_model_test.dart test\unit\studio_repository_lesson_content_read_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart`
- `.\.venv\Scripts\python.exe -m pytest backend\tests\test_lesson_document_fixture_corpus.py backend\tests\test_lesson_document_content_backend_contract.py backend\tests\test_studio_lesson_document_content_api.py -q`

Backend pytest emitted only the existing Sentry/python_multipart warning.

## Result

LER-010 is complete. The next deterministic DAG step is LER-011.
