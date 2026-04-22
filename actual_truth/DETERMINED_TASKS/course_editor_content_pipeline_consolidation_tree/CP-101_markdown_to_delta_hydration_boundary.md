# CP-101_MARKDOWN_TO_DELTA_HYDRATION_BOUNDARY

- TYPE: `OWNER`
- TITLE: `Consolidate the Markdown-to-Delta hydration boundary`
- DOMAIN: `editor hydration`
- CLASSIFICATION: `CONSOLIDATE`

## Problem Statement

Studio hydration and learner read-only rendering must not keep separate import
semantics for the same canonical Markdown.

## Primary Authority Reference

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`

## Implementation Surfaces Affected

- `frontend/lib/editor/adapter/markdown_to_editor.dart`
- `frontend/lib/shared/utils/lesson_content_pipeline.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`

## DEPENDS_ON

- `CP-G01`

## Exact Implementation Steps

1. Make `markdown_to_editor.dart` the owned importer boundary for supported
   stored Markdown.
2. Remove any surface-specific importer semantics that redefine supported
   content.
3. Keep studio editor hydration and learner read-only document creation bound
   to the same import rules.

## Acceptance Criteria

- Canonical stored Markdown becomes Quill Delta through one importer boundary.
- Preview and learner do not require separate Markdown-to-Delta rules.

## Stop Conditions

- Stop if any caller still needs a custom importer branch for supported
  fixtures.

## Out Of Scope

- Save-boundary serialization
