# DOCUMENT OPERATION PRIMITIVES LEMB-002

`input(task="Execute LEMB-002 document operation primitives", mode="code")`

## Status

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

## Pre-Change Audit

`frontend/lib/editor/document/lesson_document.dart` already contained a
canonical `insertMedia(index, mediaType, lessonMediaId)` operation.

The existing insert operation already emitted:

- `media_type`
- `lesson_media_id`

The document model did not contain deterministic block movement operations.

`frontend/test/unit/lesson_document_model_test.dart` covered parsing,
serialization, fixture corpus validation, inline mark operations, CTA
validation, and invalid media shapes, but did not explicitly prove:

- media insertion before, between, and after text blocks
- media movement up/down
- boundary-safe block movement
- media movement preserving exact media block identity and type

## Materialized Output

Updated `frontend/lib/editor/document/lesson_document.dart`:

- added `moveBlock(fromIndex, toIndex)`
- added `moveBlockUp(index)`
- added `moveBlockDown(index)`

The move operations:

- validate indexes with `RangeError.checkValidIndex`
- return the same document for no-op same-index moves
- return the same document for top/bottom boundary up/down moves
- preserve the moved `LessonBlock` instance and payload
- mutate only block order

Updated `frontend/test/unit/lesson_document_model_test.dart`:

- added coverage for media insertion before text
- added coverage for media insertion between text blocks
- added coverage for media insertion after text
- added coverage for media move up/down
- added coverage for explicit block movement to a target index
- added coverage for boundary no-op and out-of-range behavior
- asserted canonical JSON still uses `lesson_media_id` and does not contain
  `media_asset_id`

## Contract Preservation

`lesson_document_v1` remains unchanged.

Backend APIs remain unchanged.

No Markdown, Quill, HTML media tag, raw URL, or legacy media-token pathway was
introduced.

`media_asset_id` was not added to the document model.

## Verification Evidence

Commands:

```text
dart format lib\editor\document\lesson_document.dart test\unit\lesson_document_model_test.dart
flutter analyze lib\editor\document\lesson_document.dart test\unit\lesson_document_model_test.dart
flutter test test\unit\lesson_document_model_test.dart
```

Results:

- `dart format` completed for 2 files.
- `flutter analyze` returned `No issues found!`.
- `flutter test test\unit\lesson_document_model_test.dart` returned
  `14 passed`.

## Deterministic Result

`LEMB-002` establishes the document-operation substrate needed by later UI
tasks. `LEMB-003` may now consume the operation layer to replace append-only
media insertion with positioned insertion.
