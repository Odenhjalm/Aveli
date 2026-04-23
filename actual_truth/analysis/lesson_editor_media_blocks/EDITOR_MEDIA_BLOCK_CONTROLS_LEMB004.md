# EDITOR MEDIA BLOCK CONTROLS LEMB-004

`input(task="Execute LEMB-004 editor media block movement controls", mode="code")`

## Status

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

## Pre-Change Audit

`LessonDocumentEditor` rendered `LessonMediaBlock` nodes as non-text blocks in
the continuous writing surface.

The media block UI did not expose deterministic move up/down controls.

The document model already had `moveBlock`, `moveBlockUp`, and
`moveBlockDown` from `LEMB-002`.

No widget test proved editor-level media movement, boundary-disabled behavior,
or preview order parity after movement.

## Materialized Output

Updated `frontend/lib/editor/document/lesson_document_editor.dart`:

- added `_moveBlock(blockIndex, targetIndex)`
- added `_moveBlockUp(blockIndex)`
- added `_moveBlockDown(blockIndex)`
- rendered generic media move up/down `IconButton` controls inside each media
  block
- disabled move-up at the first block
- disabled move-down at the last block
- used document-model `moveBlock` operation rather than ad hoc list mutation
- preserved editor insertion index after movement by reporting the moved
  block's new insertion position

Updated `frontend/test/widgets/lesson_document_editor_test.dart`:

- added widget coverage for moving a media block up
- added widget coverage for moving a media block down
- added widget coverage for disabled boundary controls
- added widget coverage proving media identity and type survive movement
- added widget coverage proving preview receives the moved document order
- asserted move-control tooltips are generic and do not expose internal media
  id or raw media type

## Contract Preservation

`lesson_document_v1` remains unchanged.

Backend APIs remain unchanged.

No placement reorder endpoint is used for document AST movement.

No Markdown, Quill, HTML media tag, raw URL, or legacy media-token authority
was introduced.

Known user-facing metadata leakage in the media block body remains assigned to
`LEMB-005`; `LEMB-004` only guarantees that the new movement controls do not
introduce id/type leakage.

## Verification Evidence

Commands:

```text
dart format lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart
flutter analyze lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart test\widgets\lesson_media_pipeline_test.dart
flutter test test\widgets\lesson_document_editor_test.dart test\widgets\lesson_media_pipeline_test.dart
```

Results:

- `dart format` completed for 2 files.
- `flutter analyze` returned `No issues found!`.
- focused widget/media pipeline tests returned `21 passed`.

## Deterministic Result

`LEMB-004` adds deterministic media block movement controls inside the rebuilt
editor authoring surface. Movement is document-model based, boundary-safe, and
keeps editor and preview document order aligned.

## Next Deterministic Step

`LEMB-005 RENDERER UI LEAK CLEANUP`
