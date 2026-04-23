# TEST PRUNE AUDIT LER-006

DATE: `2026-04-23`

SCOPE: deterministic audit and removal of tests that only protected the
superseded Quill/Markdown editor authority after `LER-005`.

## Decision

The current editor path is `lesson_document_v1` plus `content_document`.
Tests that assert Quill Delta mutation semantics, Markdown serialization,
Markdown integrity guards, Markdown fixture locks, or legacy content-write
contracts are no longer valid rebuilt-editor gates.

Those tests were removed instead of rewritten when their only assertion was
that the old editor pipeline remained dominant.

## Removed Test Artifacts

- `frontend/test/unit/editor_markdown_adapter_test.dart`
- `frontend/test/unit/lesson_content_serialization_test.dart`
- `frontend/test/unit/lesson_markdown_integrity_guard_test.dart`
- `frontend/test/unit/lesson_markdown_roundtrip_tool_test.dart`
- `frontend/test/unit/lesson_newline_persistence_test.dart`
- `frontend/test/unit/lesson_supported_content_fixture_corpus_test.dart`
- `frontend/test/unit/quill_embed_insertion_test.dart`
- `frontend/test/unit/editor_operation_controller_test.dart`
- `frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart`
- `frontend/test/widgets/lesson_editor_quill_input_test.dart`
- `frontend/test/helpers/lesson_supported_content_fixture_corpus.dart`
- `backend/tests/test_lesson_markdown_validator.py`
- `backend/tests/test_lesson_markdown_write_contract.py`
- `backend/tests/test_lesson_newline_persistence.py`
- `backend/tests/test_studio_lesson_content_authority.py`

## Replaced By

- `frontend/test/unit/lesson_document_model_test.dart`
- `frontend/test/widgets/lesson_document_editor_test.dart`
- `frontend/test/unit/studio_repository_lesson_content_read_test.dart`
- `frontend/test/unit/studio_repository_lesson_media_routing_test.dart`
- `backend/tests/test_lesson_document_content_backend_contract.py`
- `backend/tests/test_studio_lesson_document_content_api.py`
- `backend/tests/test_write_path_dominance_regression.py`
- `backend/tests/test_lesson_supported_content_fixture_corpus.py`

## Contract Realignment

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json` no
  longer binds active rebuilt-editor coverage to removed Quill/Markdown tests.
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md` now
  records those removed files as retired editor-authority bindings.
- Current retained Markdown tests are compatibility/tooling/legacy-render tests,
  not rebuilt-editor authority tests.

## Retained Legacy Tests

These were intentionally not removed in this step:

- learner/public surface tests that still assert existing `content_markdown`
  reads before `LER-008`
- legacy Markdown scan/normalization tests used as compatibility tooling before
  `LER-009`
- media preview/learner rendering tests that still cover current legacy render
  surfaces until the renderer DAG nodes replace them

## Verification

- JSON corpus parse passed with `python -m json.tool`.
- Focused backend document/fixture/source-gate tests passed.
- Focused frontend document model, repository, media routing, and editor widget
  tests passed.
- Focused studio lesson API tests passed after updating them from
  `content_markdown` writes to `content_document` writes.
