# CP-403_EOF_ITALIC_REGRESSION_SUITE

- TYPE: `OWNER`
- TITLE: `Pin the EOF italic regression suite`
- DOMAIN: `regression coverage`
- CLASSIFICATION: `PIN`

## Problem Statement

EOF italic is still structurally fragile and must be pinned across raw Delta,
editor input, and mounted save flows.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/unit/lesson_content_serialization_test.dart`
- `frontend/test/widgets/lesson_editor_quill_input_test.dart`

## Implementation Surfaces Affected

- `frontend/test/unit/lesson_content_serialization_test.dart`
- `frontend/test/widgets/lesson_editor_quill_input_test.dart`
- `frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart`

## DEPENDS_ON

- `CP-G02`
- `CP-G03`

## Exact Implementation Steps

1. Bind EOF italic coverage to the locked EOF fixture ids.
2. Cover raw delta normalization, live input, and mounted studio save behavior.
3. Fail closed if canonical EOF italic output still depends on unstable repair
   layering.

## Acceptance Criteria

- EOF italic behavior is pinned across all supported execution surfaces.

## Stop Conditions

- Stop if any EOF italic case still passes only by accident of stacked repairs.

## Out Of Scope

- Preview-authority drift repair
