# EDITOR POSITIONED MEDIA INSERTION LEMB-003

`input(task="Execute LEMB-003 editor positioned media insertion", mode="code")`

## Status

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

## Pre-Change Audit

`LessonDocumentEditor` tracked a private `_selectedTarget`, but did not expose
the current document insertion position to Course Editor.

`CourseEditorPage._insertMediaBlockIntoDocument` inserted media with:

```text
_lessonDocument.insertMedia(_lessonDocument.blocks.length, ...)
```

That made image, audio, video, and document insertion append-only because all
media insert helpers route through `_insertMediaBlockIntoDocument`.

Existing renderer behavior already iterated `document.blocks` inline; the gap
was authored insertion position, not preview/learner AST rendering.

## Materialized Output

Updated `frontend/lib/editor/document/lesson_document_editor.dart`:

- added optional `onInsertionIndexChanged`
- reported insertion index when a text target receives focus or tap
- resolved insertion index as the position after the active block
- kept empty-document insertion index as `0`
- kept invalid/stale target fallback as document tail

Updated `frontend/lib/features/studio/presentation/course_editor_page.dart`:

- added `_lessonDocumentInsertionIndex`
- reset insertion position on lesson/document boot resets and persisted
  document hydration
- clamped insertion position whenever document content changes
- passed `onInsertionIndexChanged` from `LessonDocumentEditor`
- changed `_insertMediaBlockIntoDocument` to insert at the resolved current
  editor position instead of unconditional tail append
- advanced the insertion position after inserted media so repeated inserts are
  deterministic

Updated `frontend/test/widgets/lesson_document_editor_test.dart`:

- added a widget harness proving selected text target position can drive media
  insertion between text blocks
- proved insertion after a later paragraph appends after that paragraph, not
  outside document flow
- proved surrounding text blocks remain unchanged
- proved preview receives the same document order as editor state

## Contract Preservation

`lesson_document_v1` remains unchanged.

Backend APIs remain unchanged.

Media blocks still use `media_type` and `lesson_media_id`.

No Markdown, Quill, HTML media tag, raw URL, or legacy media-token authority
was introduced.

## Verification Evidence

Commands:

```text
dart format lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart test\widgets\lesson_document_editor_test.dart
flutter analyze lib\editor\document\lesson_document_editor.dart lib\features\studio\presentation\course_editor_page.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_media_pipeline_test.dart
flutter test test\widgets\lesson_document_editor_test.dart test\widgets\lesson_media_pipeline_test.dart
```

Results:

- `dart format` completed for 3 files.
- `flutter analyze` returned `No issues found!`.
- focused widget/media pipeline tests returned `20 passed`.

## Deterministic Result

`LEMB-003` replaces append-only media insertion with active-position media
insertion for the Course Editor authoring path while preserving inline
`lesson_document_v1` document order as rendering authority.

## Next Deterministic Step

`LEMB-004 EDITOR MEDIA BLOCK CONTROLS`
