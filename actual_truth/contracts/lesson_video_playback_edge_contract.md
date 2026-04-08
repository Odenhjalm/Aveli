# LESSON VIDEO PLAYBACK EDGE CONTRACT

STATUS: ACTIVE

This contract operates under `SYSTEM_LAWS.md`, `media_unified_authority_contract.md`, and `media_pipeline_contract.md`.
This contract contains response-shape law only.

## VIDEO PLAYBACK OUTPUT SHAPE

Lesson video playback output uses this serialized field order:

- `lesson_media_id`
- `media`

Field rules:

- `lesson_media_id` MUST be present and MUST be `UUID`
- `media` MUST be present and MUST be `{ media_id, state, resolved_url } | null`
- `lesson_media_id` MUST precede `media` when both fields are serialized in the same surface
- `media` MUST be `null` when no resolved playback media object is available
- Field omission is forbidden for `lesson_media_id` and `media`

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve the listed field names exactly
- `playback_url` MUST NOT be emitted as contract output
- `playback_format` MUST NOT be emitted as contract output
- No additional video-specific resolver payload fields may be emitted
