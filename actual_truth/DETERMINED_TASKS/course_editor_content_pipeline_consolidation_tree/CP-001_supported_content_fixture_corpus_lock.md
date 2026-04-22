# CP-001_SUPPORTED_CONTENT_FIXTURE_CORPUS_LOCK

- TYPE: `OWNER`
- TITLE: `Lock the supported-content fixture corpus`
- DOMAIN: `supported-content authority`
- CLASSIFICATION: `LOCK`

## Problem Statement

The content pipeline cannot be consolidated deterministically until every
surface binds to the same supported Markdown-canonical fixture corpus.

## Primary Authority Reference

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`

## Implementation Surfaces Affected

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/helpers/lesson_supported_content_fixture_corpus.dart`
- `frontend/test/unit/lesson_supported_content_fixture_corpus_test.dart`
- `backend/tests/test_lesson_supported_content_fixture_corpus.py`

## DEPENDS_ON

- None

## Exact Implementation Steps

1. Lock canonical supported fixtures, compatibility-only inputs, and explicitly
   unsupported shapes in repo-owned contract artifacts.
2. Bind the corpus to frontend adapter, newline, guard, preview, learner, and
   backend validator and write-contract test groups.
3. Mark `paragraph_blank_line_two_paragraphs` as owned by `CP-002`.
4. Mark `document_token_inline` as owned by `CP-003`.

## Acceptance Criteria

- The fixture corpus is authoritative and reusable.
- Every downstream branch can reference fixture ids instead of inventing new
  surface-specific cases.

## Stop Conditions

- Stop if a required supported fixture cannot be expressed without changing
  canonical storage or route contracts.

## Out Of Scope

- Adapter consolidation
- Blank-line semantics repair
- Inline document-token completion
