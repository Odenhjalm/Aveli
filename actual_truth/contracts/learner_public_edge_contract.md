# LEARNER PUBLIC EDGE CONTRACT

## STATUS

ACTIVE

This contract operates under `SYSTEM_LAWS.md`, `course_public_surface_contract.md`, and `media_unified_authority_contract.md`.
This contract defines no domain ownership, public-surface semantic ownership, media doctrine, fallback authority, or cross-domain doctrine.

## CANONICAL RESPONSE SURFACES

`CourseDiscoveryCourse` serialized field order:

- `id`
- `slug`
- `title`
- `teacher`
- `course_group_id`
- `group_position`
- `cover_media_id`
- `cover`
- `price_amount_cents`
- `drip_enabled`
- `drip_interval_days`

Field rules:

- All listed fields MUST be present in the response
- `teacher` MUST be serialized as `{ user_id, display_name } | null`
- `teacher.user_id` MUST be backend-authored from canonical course ownership
- `teacher.display_name` MUST be backend-authored from profile projection data
- `group_position` MUST be present and MUST be the only course progression field
- The legacy course progression field `step` MUST NOT be emitted
- `cover_media_id: UUID | null`
- `cover` MUST be present and MUST be `{ media_id, state, resolved_url } | null`
- `cover` MUST be `null` when no contract-valid resolved cover object exists
- Placeholder cover objects are forbidden
- `cover.resolved_url` MUST NOT be `null` when `cover` is an object
- No additional cover fields may be emitted

`CourseDetailResponse` serialized field order:

- `course`
- `lessons`
- `short_description`

Field rules:

- All listed fields MUST be present in the response
- `course` MUST be serialized as an object
- `lessons` MUST be serialized as an array
- `short_description` MUST be serialized as `str | null`

`LessonContentResponse` media output rules:

- `media` MUST be serialized as an array
- Each media item MUST contain a `media` field
- `media` MUST be `{ media_id, state, resolved_url } | null`
- Learner/public surfaces MUST NOT expose storage fields, signed URLs, or resolver-specific payloads

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve listed field names exactly
- Field omission is forbidden where a field is part of the declared surface
- Optional learner/public media fields MUST use `null` rather than omission
- No additional storage-adjacent media payloads may be emitted
