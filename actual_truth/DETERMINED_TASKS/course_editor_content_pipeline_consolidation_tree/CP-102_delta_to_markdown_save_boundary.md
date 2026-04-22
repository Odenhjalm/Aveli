# CP-102_DELTA_TO_MARKDOWN_SAVE_BOUNDARY

- TYPE: `OWNER`
- TITLE: `Consolidate the Delta-to-Markdown save boundary`
- DOMAIN: `editor save`
- CLASSIFICATION: `CONSOLIDATE`

## Problem Statement

Studio save still relies on layered repairs around the serializer instead of one
owned Delta-to-Markdown boundary.

## Primary Authority Reference

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`

## Implementation Surfaces Affected

- `frontend/lib/editor/adapter/editor_to_markdown.dart`
- `frontend/lib/editor/normalization/quill_delta_normalizer.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`

## DEPENDS_ON

- `CP-G01`

## Exact Implementation Steps

1. Make `editor_to_markdown.dart` the owned serializer boundary for supported
   content.
2. Restrict save-path normalization to the rules required by the supported
   subset.
3. Remove surface-specific Markdown post-processing that acts as a second save
   authority.

## Acceptance Criteria

- One serializer path emits canonical Markdown for supported fixtures.
- Studio save no longer depends on scattered repair layers.

## Stop Conditions

- Stop if serializer correctness still depends on save-surface-specific
  rewrites.

## Out Of Scope

- Frontend guard alignment
