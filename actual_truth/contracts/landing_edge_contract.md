# LANDING EDGE CONTRACT

STATUS: ACTIVE

This contract operates under `SYSTEM_LAWS.md`, `course_public_surface_contract.md`, and `media_unified_authority_contract.md`.
This contract contains response-shape law only.

## LANDING COVER OUTPUT SHAPE

Where a landing execution surface emits course-card cover output, the serialized field order is:

- `cover_media_id`
- `cover`

Field rules:

- `cover_media_id` MUST be present and MUST be `UUID | null`
- `cover` MUST be present and MUST be `{ media_id, state, resolved_url } | null`
- `cover` MUST be `null` when no resolved cover media object is available
- Placeholder cover objects are forbidden
- `cover.resolved_url` MUST NOT be `null` when `cover` is an object
- Field omission is forbidden for `cover_media_id` and `cover`

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve the listed field names exactly
- `cover_url` MUST NOT be emitted as contract output
- `resolved_cover_url` MUST NOT be emitted as contract output
- Storage-path media fields MUST NOT be emitted as contract output
- No additional landing-specific resolver payload fields may be emitted
