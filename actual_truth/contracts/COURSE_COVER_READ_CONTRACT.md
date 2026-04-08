# COURSE_COVER_READ_CONTRACT

STATUS: ACTIVE

This contract operates under `SYSTEM_LAWS.md`, `course_public_surface_contract.md`, and `media_unified_authority_contract.md`.
This contract contains response-shape law only.

## COVER OUTPUT SHAPE

Within `CourseDiscoveryCourse`, cover output uses this serialized field order:

- `cover_media_id`
- `cover`

Field rules:

- `cover_media_id` MUST be present and MUST be `UUID | null`
- `cover` MUST be present and MUST be `{ media_id, state, resolved_url } | null`
- `cover_media_id` MUST precede `cover` when both fields are serialized in the same surface
- If no resolved cover object is available, `cover` MUST be `null`
- Field omission is forbidden for `cover_media_id` and `cover`

## TRANSPORT CONSTRAINTS

- Cover output MUST NOT be emitted as flat `cover_url`
- No additional cover resolver payload fields may be emitted
- Response payloads MUST preserve the listed field names exactly
