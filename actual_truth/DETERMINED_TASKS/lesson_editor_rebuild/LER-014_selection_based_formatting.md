# LER-014 SELECTION-BASED FORMATTING

TYPE: `OWNER`
TASK_TYPE: `FRONTEND_EDITOR_SEMANTICS`
DEPENDS_ON: `[LER-013]`

## Goal

Make editor formatting behave like a selection-based document editor: toolbar
operations apply to the active selected text range, not implicitly to the
entire active block or document.

## Required Outputs

- inline formatting reads the active text selection range
- clear formatting reads the active text selection range
- heading / paragraph / list structural formatting reads the active selection
- partial structural formatting splits surrounding text into deterministic
  `lesson_document_v1` nodes
- collapsed cursor focus does not format whole blocks
- no Markdown, Quill, or legacy pathway is reintroduced

## Forbidden

- applying bold, italic, underline, clear-formatting, heading, paragraph,
  bullet-list, or ordered-list commands to an entire block unless that range is
  explicitly selected
- applying formatting to the whole document because a single block has focus
- changing `lesson_document_v1` as storage authority
- reintroducing Markdown / Quill / legacy adapter authority

## Verification

Run focused editor analyzer and widget tests, then rerun broad editor suites
and deterministic aggregate gates.

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Materialized Outputs

- Updated `frontend/lib/editor/document/lesson_document_editor.dart` so
  `_applyInlineMark`, `_clearFormatting`, and `_convertSelectedBlock` use the
  active `TextSelection` from the selected editor target.
- Collapsed/no-selection formatting is now a no-op instead of a hidden
  full-block operation.
- Partial heading/list conversion now splits the source text around the
  selected range and emits deterministic `lesson_document_v1` blocks for the
  before, selected, and after segments.
- Removed obsolete helper paths left from whole-block formatting.
- Updated `frontend/test/widgets/lesson_document_editor_test.dart` so widget
  tests prove selected-range bold/italic/underline/clear, selected-range
  heading conversion, selected-range list conversion, and no-selection no-op
  behavior.
- Updated active contracts so selection-based formatting is explicit law.

### Verification Evidence

- `dart format lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  completed.
- `flutter analyze lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  passed with no issues.
- `flutter test test\widgets\lesson_document_editor_test.dart` passed:
  `8 passed`.
- Broad frontend editor, preview, learner, media, and repository suite passed:
  `72 passed`.
- Broad backend aggregate/audit gate suite passed: `82 passed`, with the
  existing `python_multipart` warning.
- `python -m json.tool actual_truth\DETERMINED_TASKS\lesson_editor_rebuild\task_manifest.json`
  completed.

### Deterministic Result

`LER-014` keeps `lesson_document_v1` as structural authority while changing
editor behavior so formatting is driven by explicit selected text ranges, not
by focused block identity.
