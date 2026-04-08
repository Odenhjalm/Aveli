# MEDIA IMAGE EDGE CONTRACT

STATUS: ACTIVE

This contract operates under `SYSTEM_LAWS.md`, `media_unified_authority_contract.md`, and `media_pipeline_contract.md`.
This contract contains response-shape law only.

## IMAGE OUTPUT SHAPE

Image delivery output uses this serialized field order:

- `media`

Field rules:

- `media` MUST be present and MUST be `{ media_id, state, resolved_url } | null`
- `media` MUST be `null` when no resolved image media object is available
- Field omission is forbidden for `media`

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve the listed field names exactly
- `image_url` MUST NOT be emitted as contract output
- No `media_assets` storage fields may be emitted as contract output
- No additional image-specific resolver payload fields may be emitted
