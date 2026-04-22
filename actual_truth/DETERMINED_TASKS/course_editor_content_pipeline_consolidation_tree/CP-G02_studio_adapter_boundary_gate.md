# CP-G02_STUDIO_ADAPTER_BOUNDARY_GATE

- TYPE: `GATE`
- TITLE: `Studio adapter-boundary gate`
- DOMAIN: `studio boundary verification`
- CLASSIFICATION: `GATE`

## Problem Statement

Validation and rendering branches must not continue until studio hydration and
save are explainable through one owned adapter boundary.

## Primary Authority Reference

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`

## Implementation Surfaces Affected

- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart`
- `frontend/test/unit/editor_markdown_adapter_test.dart`
- `frontend/test/unit/lesson_content_serialization_test.dart`

## DEPENDS_ON

- `CP-101`
- `CP-102`
- `CP-103`

## Exact Implementation Steps

1. Verify studio hydrate and studio save both terminate at the owned adapter
   boundary.
2. Verify no surface-specific semantic owner survives outside that boundary.
3. Fail closed if mounted studio tests still need stacked repair assumptions.

## Acceptance Criteria

- Studio edit and save are boundary-owned, not layer-owned.
- Downstream validation and render work can assume one studio adapter contract.

## Stop Conditions

- Stop if any mounted studio flow still forks importer or serializer semantics.

## Out Of Scope

- Frontend and backend validator parity
