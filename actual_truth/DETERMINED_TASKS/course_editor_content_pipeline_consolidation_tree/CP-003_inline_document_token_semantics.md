# CP-003_INLINE_DOCUMENT_TOKEN_SEMANTICS

- TYPE: `OWNER`
- TITLE: `Resolve inline document-token semantics`
- DOMAIN: `document-token semantics`
- CLASSIFICATION: `RESOLVE`

## Problem Statement

`!document(id)` is part of the supported canonical subset, but hydrate and
render behavior is incomplete and still asymmetric across surfaces.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `actual_truth/contracts/lesson_document_edge_contract.md`
- `backend/tests/test_lesson_markdown_write_contract.py`

## Implementation Surfaces Affected

- `frontend/lib/shared/utils/lesson_content_pipeline.dart`
- `frontend/lib/editor/adapter/markdown_to_editor.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`
- `backend/tests/test_lesson_markdown_write_contract.py`

## DEPENDS_ON

- `CP-001`

## Exact Implementation Steps

1. Define the canonical inline-document fixture behavior for hydrate and render.
2. Preserve `!document(id)` as a supported stored form, not a compatibility
   alias.
3. Ensure trailing document rendering stays reserved for non-embedded document
   rows only.
4. Bind preview and learner verification to the same inline-document fixtures.

## Acceptance Criteria

- Inline `!document(id)` semantics are explicit and reusable across the
  pipeline.
- No surface drops embedded documents while also excluding them from trailing
  media rendering.

## Stop Conditions

- Stop if inline document support would require a second stored token contract
  or a schema change.

## Out Of Scope

- Blank-line semantics
- Validation parity
