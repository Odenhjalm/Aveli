# CP-103_EDITOR_INPUT_NEWLINE_SANITIZATION_ALIGNMENT

- TYPE: `OWNER`
- TITLE: `Align editor input and newline sanitization`
- DOMAIN: `editor input`
- CLASSIFICATION: `ALIGN`

## Problem Statement

Live editor input can still generate unstable inline-newline structures that the
save boundary must later repair.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/widgets/lesson_editor_quill_input_test.dart`

## Implementation Surfaces Affected

- `frontend/lib/editor/session/editor_operation_controller.dart`
- `frontend/lib/editor/normalization/quill_delta_normalizer.dart`
- `frontend/test/widgets/lesson_editor_quill_input_test.dart`

## DEPENDS_ON

- `CP-G01`

## Exact Implementation Steps

1. Align live editor newline insertion with the supported-content contract.
2. Keep inline formatting off newline sentinels when the supported subset does
   not require it.
3. Preserve stable editor input for EOF italic and block formatting cases.

## Acceptance Criteria

- Live edits no longer generate avoidable unstable Delta shapes for supported
  fixtures.
- Input behavior aligns with the owned save boundary.

## Stop Conditions

- Stop if newline sanitization still depends on undefined downstream repair.

## Out Of Scope

- Backend validation
