# CP-302_STUDIO_PREVIEW_LEARNER_COMPOSITION

- TYPE: `OWNER`
- TITLE: `Align studio preview to learner-equivalent composition`
- DOMAIN: `studio preview`
- CLASSIFICATION: `ALIGN`

## Problem Statement

Studio preview must share learner-equivalent composition for the same persisted
Markdown while remaining a separate persisted-content-only authority surface.

## Primary Authority Reference

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `backend/tests/test_write_path_dominance_regression.py`

## Implementation Surfaces Affected

- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart`

## DEPENDS_ON

- `CP-G01`
- `CP-G02`
- `CP-301`

## Exact Implementation Steps

1. Keep preview content sourced from persisted backend content only.
2. Reuse learner-equivalent composition for the same Markdown and media
   fixtures.
3. Prevent preview-only importer or renderer semantics from reappearing.

## Acceptance Criteria

- Preview remains persisted-content-only.
- Preview composition matches learner semantics for supported fixtures.

## Stop Conditions

- Stop if preview needs controller-derived Markdown or preview-only render
  rules.

## Out Of Scope

- Backend validator behavior
