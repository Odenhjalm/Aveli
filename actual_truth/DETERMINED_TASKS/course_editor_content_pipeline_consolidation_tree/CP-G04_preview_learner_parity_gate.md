# CP-G04_PREVIEW_LEARNER_PARITY_GATE

- TYPE: `GATE`
- TITLE: `Preview and learner parity gate`
- DOMAIN: `render parity`
- CLASSIFICATION: `GATE`

## Problem Statement

Regression gates must not proceed until preview and learner prove equivalent
visible semantics for the same canonical fixtures.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

## Implementation Surfaces Affected

- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`

## DEPENDS_ON

- `CP-301`
- `CP-302`

## Exact Implementation Steps

1. Render the same canonical fixtures through preview and learner surfaces.
2. Compare headings, emphasis, underline, lists, blank lines, media tokens, and
   inline documents.
3. Fail closed on any surface-specific semantic divergence.

## Acceptance Criteria

- Preview and learner render equivalently for the supported subset.

## Stop Conditions

- Stop on any unexplained parity mismatch.

## Out Of Scope

- Drift-test repair
