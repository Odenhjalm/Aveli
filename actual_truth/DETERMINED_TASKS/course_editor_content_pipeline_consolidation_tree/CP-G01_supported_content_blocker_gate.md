# CP-G01_SUPPORTED_CONTENT_BLOCKER_GATE

- TYPE: `GATE`
- TITLE: `Supported-content blocker gate`
- DOMAIN: `blocker verification`
- CLASSIFICATION: `GATE`

## Problem Statement

Adapter consolidation must not start while newline semantics and inline
document-token semantics remain ambiguous.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`

## Implementation Surfaces Affected

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/unit/lesson_supported_content_fixture_corpus_test.dart`
- `backend/tests/test_lesson_supported_content_fixture_corpus.py`

## DEPENDS_ON

- `CP-001`
- `CP-002`
- `CP-003`

## Exact Implementation Steps

1. Confirm blocker fixtures no longer have unresolved semantic ownership.
2. Confirm `CP-002` and `CP-003` results are recorded back into the supported
   corpus.
3. Fail closed if any downstream node would still need to decide newline or
   inline-document semantics for itself.

## Acceptance Criteria

- Blank-line semantics and inline document-token semantics are explicit and
  contract-backed.
- Adapter consolidation can proceed without reopening supported-content scope.

## Stop Conditions

- Stop on any unresolved blocker fixture.

## Out Of Scope

- Studio adapter implementation details
