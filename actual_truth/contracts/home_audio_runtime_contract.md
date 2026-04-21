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

## COURSE-LINK COMPOSITION AUTHORITY

Runtime response shape remains governed by this contract.

Course-linked home audio may be composed from canonical
`app.home_player_course_links` source truth plus backend read composition under
`home_audio_aggregation_contract.md`.

`runtime_media` remains read-only projection authority where in scope, but it
is not the source table for `app.home_player_course_links`.

Frontend fallback, direct storage authority, and client-side access inference
are forbidden.

## DETERMINISTIC DELIVERY RESOLVER BOUNDARY

Home-audio runtime output may include only the governed `media` object shape
defined by this contract.

The backend resolver owns deterministic delivery policy outside
`app.runtime_media`. The resolver may read accepted projection facts from
`runtime_media`, but it must resolve playback delivery from canonical media
identity, accepted source authority, media lifecycle state, playback object
readiness, and backend access rules.

`runtime_media` must remain read-only projection. It must not become delivery
policy authority, storage URL authority, signed URL authority, or fallback
authority.

If delivery cannot be resolved deterministically, the emitted `media` value must
fail closed according to the governed shape, and any diagnostic write must be
observability/support only.

## TRANSPORT CONSTRAINTS

- Response payloads MUST preserve the listed field names exactly
- `media_asset_id` MUST NOT be emitted as contract output
- signed URL fields MUST NOT be emitted as contract output
- download URL fields MUST NOT be emitted as contract output
- storage-derived playback fields MUST NOT be emitted as contract output
- No additional playback resolver payload fields may be emitted

## MOUNTED FRONTEND CONSUMER LAW

The mounted learner-facing Home Player UI MUST consume `GET /home/audio` as its
canonical runtime feed.

Frontend consumer rules:

- frontend MUST render the governed item shape from this contract
- frontend MUST NOT leave `/home/audio` without a mounted learner-facing
  consumer when the Home Player feature is present
- frontend MUST NOT substitute another endpoint, local cache model, course
  showcase payload, or direct lesson-media query for the Home Player runtime
- frontend MUST NOT construct playback from `media_asset_id`, storage path,
  source-object path, signed URL, or any other non-contract field
