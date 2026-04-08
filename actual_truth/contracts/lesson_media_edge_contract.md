# LESSON MEDIA EDGE CONTRACT

## STATUS

ACTIVE

This contract operates under `SYSTEM_LAWS.md`, `media_pipeline_contract.md`, and `media_unified_authority_contract.md`.
This contract contains response-shape law only.

## CANONICAL STUDIO ITEM SHAPE

`StudioLessonMediaItem` serialized field order:

- `lesson_media_id`
- `lesson_id`
- `media_asset_id`
- `position`
- `media_type`
- `state`
- `media`

Field rules:

- All listed fields MUST be present in the response
- `lesson_media_id: UUID`
- `lesson_id: UUID`
- `media_asset_id: UUID`
- `position: int`
- `media_type: "audio" | "image" | "video" | "document"`
- `state: "uploaded" | "processing" | "ready" | "failed"`
- `media: { media_id, state, resolved_url } | null`
- `media` MUST be `null` when no resolved media object is available

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve the listed field names exactly
- No additional preview or resolver payload fields may be emitted
- The following fields MUST NOT be emitted:
  - `preview_ready`
  - `original_name`
  - `resolved_preview_url`
  - `file_name`
  - `download_url`
  - `signed_url`
