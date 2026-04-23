# CONTRACT BOUNDARY LOCK LEMB-001

`input(task="Execute LEMB-001 contract boundary lock for lesson editor media blocks", mode="no-code")`

## Status

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

No application implementation was performed in this step.

## Decision

The media identity boundary is locked:

```text
lesson_document_v1 media block identity = lesson_media_id
media pipeline asset identity = media_asset_id
```

`media_asset_id` is not editor document truth.

`LessonMediaBlock(media_type, lesson_media_id)` remains the canonical editor
document node for media inside `lesson_document_v1`.

## Authority Evidence

`actual_truth/contracts/course_lesson_editor_contract.md` states that lesson
media document references must use typed media nodes that reference
`lesson_media_id`.

`actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md` states:

- media blocks carry `lesson_media_id` and `media_type`
- media nodes must reference governed lesson media by `lesson_media_id`
- `media_asset_id` is forbidden as editor document truth

`actual_truth/contracts/media_pipeline_contract.md` states:

- `media_asset_id` is canonical asset identity for ingest and asset lifecycle
- `lesson_media_id` is canonical authored placement identity for lesson-media
  attachment
- placement read/write responses may carry both identities as metadata, but
  this does not amend editor document authority

## Repository Evidence

`frontend/lib/editor/document/lesson_document.dart` currently aligns with the
locked boundary:

- `LessonMediaBlock` stores `mediaType`
- `LessonMediaBlock` stores `lessonMediaId`
- serialization emits `media_type`
- serialization emits `lesson_media_id`
- document validation resolves media references by `lessonMediaId`

`frontend/lib/features/studio/presentation/course_editor_page.dart` uses
`mediaAssetId` in placement/preview metadata paths and inserts media blocks
with `lessonMediaId`.

`frontend/lib/features/courses/presentation/lesson_page.dart` uses
`mediaAssetId` as read metadata and currently exposes it as a learner label
fallback. That is not editor document truth, but it is a user-facing leakage
gap assigned to `LEMB-005`.

## Locked Implementation Rules

Later tasks MUST:

- keep `LessonMediaBlock(media_type, lesson_media_id)` unchanged as canonical
  document shape
- use `media_asset_id` only before or outside document-node creation, where it
  belongs to ingest/asset/placement metadata
- create editor media blocks only after a governed placement identity
  `lesson_media_id` exists
- validate media references against placement identity, not asset identity
- remove user-facing `media_asset_id` label fallback under `LEMB-005`

Later tasks MUST NOT:

- store `media_asset_id` in `lesson_document_v1`
- infer `lesson_media_id` from `media_asset_id` without placement authority
- treat media placement ordering as document AST ordering
- use Markdown, Quill, HTML media tags, raw URLs, or legacy media tokens as
  editor media authority

## Contradiction Handling

If a future task requires `media_asset_id` inside `lesson_document_v1`, the
controller must stop and create a contract-amendment task before any
implementation proceeds.

No such amendment is authorized by `LEMB-001`.

## Next Deterministic Step

`LEMB-002 DOCUMENT OPERATION PRIMITIVES`

This may proceed only under the locked identity rule above.
