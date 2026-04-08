# HOME AUDIO RUNTIME CONTRACT

## STATUS

ACTIVE

This contract operates under `SYSTEM_LAWS.md`, `home_audio_aggregation_contract.md`, `media_unified_authority_contract.md`, and `media_pipeline_contract.md`.
This contract contains response-shape law only.
Home-audio inclusion, access, runtime validity/filtering, and runtime projection semantics are defined only by `home_audio_aggregation_contract.md`.

## HOME AUDIO PLAYBACK OUTPUT SHAPE

HOME_AUDIO_RUNTIME playback output uses this serialized field order for playback fields inside each emitted item:

- `media`

Field rules:

- `media` MUST be present and MUST be `{ media_id, state, resolved_url } | null`
- Field omission is forbidden for `media`

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve the listed field names exactly
- `media_asset_id` MUST NOT be emitted as contract output
- signed URL fields MUST NOT be emitted as contract output
- download URL fields MUST NOT be emitted as contract output
- storage-derived playback fields MUST NOT be emitted as contract output
- No additional playback resolver payload fields may be emitted
