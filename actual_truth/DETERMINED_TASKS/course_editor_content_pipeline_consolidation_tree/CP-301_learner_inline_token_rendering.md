# CP-301_LEARNER_INLINE_TOKEN_RENDERING

- TYPE: `OWNER`
- TITLE: `Complete learner inline-token rendering`
- DOMAIN: `learner rendering`
- CLASSIFICATION: `COMPLETE`

## Problem Statement

Learner rendering must fully implement the locked token contract, including
inline documents, without surface-specific fallback behavior.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

## Implementation Surfaces Affected

- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/lib/shared/utils/lesson_content_pipeline.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

## DEPENDS_ON

- `CP-G01`
- `CP-G02`

## Exact Implementation Steps

1. Render inline image, audio, video, and document tokens at canonical token
   positions.
2. Keep trailing document rendering limited to non-embedded document rows.
3. Bind learner rendering to the same supported fixture ids used by preview.

## Acceptance Criteria

- Learner rendering no longer drops embedded document tokens.
- Token rendering matches the locked supported-content contract.

## Stop Conditions

- Stop if learner rendering still depends on token-type-specific fallback logic
  outside the shared contract.

## Out Of Scope

- Studio preview authority
