# PROFILE MEDIA EDGE CONTRACT

STATUS: ACTIVE

This contract operates under `SYSTEM_LAWS.md`, `profile_community_media_contract.md`, and `media_unified_authority_contract.md`.
This contract contains response-shape law only.

## PROFILE COMMUNITY MEDIA OUTPUT SHAPE

Where a profile/community execution surface emits a media payload, the serialized field order is:

- `media`

Field rules:

- `media` MUST be present and MUST be `{ media_id, state, resolved_url } | null`
- `media` MUST be `null` when no resolved profile/community media object is available
- Field omission is forbidden for `media`

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve the listed field names exactly
- Storage fields MUST NOT be emitted as contract output
- Download URL fields MUST NOT be emitted as contract output
- Signed URL fields MUST NOT be emitted as contract output
- No additional profile/community-specific resolver payload fields may be emitted
