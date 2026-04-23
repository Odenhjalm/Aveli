# MEDIA BLOCK EDITOR UX REFINEMENT 2026-04-23

`input(task="Apply UX refinements to media blocks in the lesson editor", mode="code")`

## Status

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

## Post-DAG Amendment

This task supersedes the earlier LEMB insertion UX invariant.

Previous LEMB behavior:

- Course Editor inserted media at the active editor insertion position when one
  was available.

Current UX decision:

- newly inserted media blocks are inserted at document index `0`
- the authoring workflow assumes media is moved downward after insertion
- move up/down document operations remain unchanged

This is a UX-level amendment only.

## No-Code Audit Findings

Inspected files:

- `frontend/lib/editor/document/lesson_document_editor.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`

Findings:

- `_insertMediaBlockIntoDocument` used `_resolvedLessonDocumentInsertionIndex()`
  and therefore inserted at the active editor position, with append fallback
  when no active position existed.
- editor media blocks rendered extra instructional copy:
  `Infogad media` and `Flytta blocket med pilarna.`
- the editor did not receive safe media display labels, so it could not render
  the uploaded file name.
- movement controls were already deterministic and could remain unchanged.

## Materialized Output

Updated `frontend/lib/features/studio/presentation/course_editor_page.dart`:

- Course Editor media insertion now uses `const insertionIndex = 0`
- `_resolvedLessonDocumentInsertionIndex()` was removed because media no longer
  uses active-position insertion
- editor authoring receives safe media display data from `_editorDocumentMedia()`

Updated `frontend/lib/editor/document/lesson_document_editor.dart`:

- `LessonDocumentEditor` accepts safe `LessonDocumentPreviewMedia` display data
- editor media blocks render only:
  - file name from safe label/original name
  - controlled media type label: `image`, `video`, `audio`, or `document`
- removed the instructional media-block text from editor UI

Updated regression gates:

- LER-011 and LER-012 now require top insertion for Course Editor media blocks
- gates reject append fallback and active-position media insertion for new media
- gates continue to require document-order movement and no metadata leakage

## Contract Preservation

`lesson_document_v1` was not modified.

Backend APIs were not modified.

Preview and learner rendering logic were not changed.

Media ordering semantics remain document-order based: insertion creates a block
at index `0`, and subsequent movement still uses deterministic document block
movement.

No Markdown, Quill, legacy media-token path, `media_asset_id` document
authority, or raw media URL authority was introduced.

## Verification Evidence

Commands:

```text
dart format lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart test\widgets\lesson_document_editor_test.dart
flutter analyze lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart test\widgets\lesson_document_editor_test.dart
.\.venv\Scripts\python.exe -m pytest backend\tests\test_ler011_deterministic_audit_gates.py backend\tests\test_ler012_final_aggregate_editor_gate.py
flutter test test\widgets\lesson_document_editor_test.dart
flutter test test\unit\lesson_document_model_test.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_preview_rendering_test.dart test\widgets\lesson_media_pipeline_test.dart
manifest and amendment validation
git diff --check
```

Results:

- focused Flutter analyze passed: `No issues found!`
- deterministic backend audit gates passed: `21 passed`
- focused editor widget tests passed: `13 passed`
- focused model/widget/media suite passed: `42 passed`
- manifest and post-DAG amendment validation passed:
  `validated LEMB DAG closed plus post-DAG media UX amendment`
- backend app/API diff was empty
- `git diff --check` passed with no whitespace errors

## Next Step

Preview audit remains the next UX audit surface.
