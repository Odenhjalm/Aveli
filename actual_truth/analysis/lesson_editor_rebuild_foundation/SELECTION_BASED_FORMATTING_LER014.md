# SELECTION-BASED FORMATTING AUDIT - LER-014

Date: `2026-04-23`

Status: `COMPLETED`

## Decision

The editor must behave like a selection-based document editor. Formatting
operations must use the current selected text range as their authority.

The previous behavior was not acceptable because active block focus caused
toolbar commands to apply to the whole block. That was deterministic, but it
was not Word/Google Docs-like selection behavior.

## Materialized Behavior

- Bold, italic, underline, and clear formatting now use active
  `TextSelection` offsets.
- Heading, paragraph, bullet-list, and ordered-list commands now require an
  active non-collapsed selection.
- Partial structural conversion splits selected text out of the source block
  and preserves surrounding text as separate deterministic document nodes.
- Collapsed cursor focus is not treated as a selection and therefore does not
  format the whole block.
- `lesson_document_v1` remains unchanged as structural and persistence
  authority.

## Examples

- Selecting `Beta` in `Alpha Beta Gamma` and pressing bold produces paragraph
  text runs `Alpha `, bold `Beta`, and ` Gamma`.
- Selecting `Beta` in `Alpha Beta Gamma` and pressing heading produces:
  paragraph `Alpha `, heading `Beta`, paragraph ` Gamma`.
- Selecting `Beta` and pressing bullet list produces:
  paragraph `Alpha `, bullet-list item `Beta`, paragraph ` Gamma`.
- Pressing bold or heading with only a cursor focus produces no document
  mutation.

## Regression Coverage

`frontend/test/widgets/lesson_document_editor_test.dart` verifies:

- selected-range inline marks do not mark surrounding text
- clear formatting removes marks only from selected text
- selected-range heading conversion splits the block
- no-selection toolbar commands are no-ops
- selected-range list conversion splits the block
- save payload remains `content_document`
- Markdown / Quill / legacy authority is not reintroduced

## Verification

- `dart format lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  completed.
- `flutter analyze lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  passed with no issues.
- `flutter analyze lib\api\api_client.dart lib\api\api_paths.dart lib\main.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  passed with no issues.
- `flutter test test\widgets\lesson_document_editor_test.dart` passed:
  `8 passed`.
- Broad frontend editor, preview, learner, media, and repository suite passed:
  `72 passed`.
- Broad backend aggregate/audit gate suite passed: `82 passed`, with the
  existing `python_multipart` warning.
- `python -m json.tool actual_truth\DETERMINED_TASKS\lesson_editor_rebuild\task_manifest.json`
  completed.

## Stop Condition Review

- Markdown was not reintroduced.
- Quill was not reintroduced.
- Legacy adapters, guardrails, and session pathways were not restored.
- Backend validation remains document-native.
- Persisted preview and learner rendering remain document-model based.
- ETag / If-Match behavior is unchanged.

## Final Assertion

Formatting authority now comes from the explicit selected text range. Block
focus is no longer enough to mutate an entire block.
