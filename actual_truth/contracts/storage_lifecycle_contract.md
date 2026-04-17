# STORAGE LIFECYCLE CONTRACT

## STATUS

ACTIVE

## 1. Purpose

This contract defines the canonical lifecycle relationship between governed media
identity in `app.media_assets` and physical storage objects used by Aveli media.

It covers:

- original/source storage objects created by media ingest
- worker-created playback/derived storage objects
- storage cleanup after media lifecycle deletion
- storage orphan handling
- ready-state storage requirements for audio, image, video, document, profile
  media, and course covers

This contract does not redefine media identity, ingest, placement, runtime
projection, frontend representation, lesson delete, course-cover assignment,
profile projection, or media-asset deletion authority.

## 2. Authority

This contract operates under:

- `SYSTEM_LAWS.md`
- `supabase_integration_boundary_contract.md`
- `media_pipeline_contract.md`
- `media_lifecycle_contract.md`
- `course_lesson_editor_contract.md`
- `home_audio_aggregation_contract.md`
- `profile_community_media_contract.md`
- all active media edge contracts in `actual_truth/contracts/`

Authority boundaries:

- `app.media_assets` remains the only canonical media identity authority.
- `app.runtime_media` remains the only canonical runtime media truth layer.
- Backend read composition remains the only frontend media representation
  authority.
- Media ingest owns asset creation, upload target issuance, upload completion
  verification, and `pending_upload -> uploaded`.
- The canonical media worker owns `uploaded -> processing`,
  `processing -> ready`, and `processing -> failed`.
- `media_lifecycle_contract.md` remains the only authority allowed to delete
  `app.media_assets`.
- This contract owns only the storage-object side of the lifecycle.

Storage is physical persistence only. Storage objects, buckets, object paths,
storage metadata, public URLs, and signed URLs never become media identity,
runtime truth, access truth, orphan authority, or frontend contract output.

## 3. Lifecycle Model

Canonical media storage lifecycle:

```text
upload intent
-> app.media_assets row in pending_upload
-> backend-owned upload target
-> backend-mediated storage write
-> upload completion verifies original object
-> app.media_assets state uploaded
-> worker claim moves uploaded to processing
-> worker writes and verifies playback object
-> worker moves processing to ready or failed
-> runtime_media projects canonical runtime truth
-> backend read composition emits media = { media_id, state, resolved_url } | null
-> reference removal signal may request lifecycle evaluation
-> media lifecycle verifies orphan status
-> media lifecycle deletes app.media_assets when safe
-> storage cleanup deletes physical objects after asset deletion is safe
```

The database authority always precedes media meaning:

- upload intent creates a DB identity before any canonical media object exists
- upload execution may create physical bytes, but those bytes are not canonical
  media until completion verifies them and the DB state advances
- worker-created derived bytes are not canonical ready media until the worker
  verifies the object and the DB state advances to `ready`
- storage cleanup never creates, repairs, or deletes media meaning

Physical storage object phases may exist, but they are not `app.media_state`
values. The only canonical media states are those defined by
`media_pipeline_contract.md`.

## 4. State Definitions

### `pending_upload`

Entry condition:

- media ingest has created exactly one `app.media_assets` row
- the row has `state = pending_upload`
- an upload target has been issued for the row's internal source object
  coordinate

Storage relationship:

- the original storage object may be absent
- if bytes already exist, they are unconfirmed physical bytes only
- no playback object may exist as canonical truth

Exit condition:

- upload completion verifies the original storage object and moves the asset to
  `uploaded`
- there is no `pending_upload -> failed`, `pending_upload -> processing`, or
  `pending_upload -> ready` transition
- expired or abandoned pending uploads may only be removed by media lifecycle
  deletion after orphan verification; expiration is not a media state

Owner of transition:

- media ingest/upload-completion authority

### `uploaded`

Entry condition:

- upload completion has verified the original storage object
- the DB state has advanced from `pending_upload` to `uploaded`

Storage relationship:

- the original storage object must have existed at completion verification time
- the playback object may be absent
- if the original object later disappears, the asset is broken, not ready

Exit condition:

- the canonical media worker claims the asset and moves it to `processing`

Owner of transition:

- canonical media worker

### `processing`

Entry condition:

- the canonical media worker has claimed an `uploaded` asset
- the worker has moved the asset to `processing` through the canonical worker
  mutation boundary

Storage relationship:

- the worker must verify source-object availability before transformation
- the worker may create temporary and derived physical objects
- derived objects created before DB commit are not canonical ready media

Exit condition:

- `processing -> ready` after derived playback object verification
- `processing -> failed` after deterministic processing or verification failure

Owner of transition:

- canonical media worker

### `ready`

Entry condition:

- canonical worker processing has completed
- the playback object has been written and verified
- `app.media_assets.playback_object_path` is present
- runtime resolution can derive a deterministic content type and delivery
  behavior without fallback

Storage relationship:

- the playback object must exist at ready transition time
- the playback object coordinate is backend-internal storage identity, not
  frontend truth
- if the playback object later disappears, the row is broken ready state and
  must fail closed at resolution/observability; storage must not be used to
  reconstruct truth

Exit condition:

- no state transition exits `ready`
- eventual removal is deletion of the `app.media_assets` row by media lifecycle
  after orphan verification

Owner of transition:

- canonical media worker

### `failed`

Entry condition:

- canonical worker processing or verification did not complete successfully
- transition occurred from `uploaded` or `processing` through the canonical
  worker boundary

Storage relationship:

- original and temporary/derived objects may or may not exist
- no frontend resolved URL may be emitted
- storage objects for failed assets are cleanup candidates only after orphan
  verification and asset deletion safety are established

Exit condition:

- no state transition exits `failed` under this contract
- eventual removal is deletion of the `app.media_assets` row by media lifecycle
  after orphan verification

Owner of transition:

- canonical media worker

### Expired And Deleted

`expired` and `deleted` are not allowed `app.media_state` values.

Expired upload targets are lifecycle facts about an upload target, not media
states. Deleted media is represented by absence of the `app.media_assets` row
after media lifecycle deletion, not by a persisted media state.

## 5. Transition Rules

Allowed media-state transitions are exactly:

```text
pending_upload -> uploaded
uploaded -> processing
processing -> ready
processing -> failed
```

Transition requirements:

- `pending_upload -> uploaded` requires backend upload-completion verification
  of the original storage object before DB update.
- `uploaded -> processing` requires canonical worker claim through the canonical
  worker mutation boundary.
- `processing -> ready` requires worker-created or worker-verified playback
  object existence before DB update.
- `processing -> failed` requires worker-owned processing or verification
  failure.

Forbidden transitions:

- direct ready insertion
- `pending_upload -> ready`
- `pending_upload -> processing`
- `pending_upload -> failed`
- `uploaded -> ready` from a request surface
- frontend-authored state mutation
- route, trigger, migration, ad-hoc SQL, or storage event mutation to `ready`
- playback metadata writes outside the canonical worker boundary
- using storage object existence to infer or repair a DB transition

Repeated calls may be idempotent only when they preserve the same canonical
state and do not create a new transition.

## 6. Storage Rules

Storage write rules:

- frontend clients must never write directly to Supabase Storage for canonical
  media behavior
- canonical upload execution is backend-mediated through Aveli APIs
- backend code may use Supabase signed upload URLs internally as infrastructure
  mechanics
- upload intent must not return storage URLs, storage headers, buckets, object
  paths, or storage signatures as contract truth
- upload completion must not trust client claims; it must verify storage object
  existence through backend-owned storage access
- worker-created playback objects must be verified before `ready`

Storage identity rules:

- `original_object_path` is an internal source-object coordinate.
- `playback_object_path` is an internal playback-object coordinate.
- `playback_object_path` is required for `ready`.
- audio `ready` requires `playback_format = mp3`.
- image, video, document, profile-media, and course-cover `ready` require
  deterministic worker-owned format/delivery metadata sufficient for
  `runtime_media` and backend read composition to resolve or fail closed without
  fallback.
- resolver storage selection must be determined only after `media_asset_id` has
  resolved through `runtime_media`; delivery scope must be explicit in that
  runtime row or in a contract-declared storage policy referenced by that row
- if delivery scope cannot be determined from `media_asset_id -> runtime_media`,
  resolution must fail closed

Storage verification rules:

- object existence must be verified at upload completion
- source object existence must be verified by the worker before transformation
- playback object existence must be verified before `ready`
- resolver signing failure or missing playback object must not fall back to
  source objects, raw storage paths, legacy URLs, or frontend construction

Storage is never authority:

- a storage object without a DB row is not media
- a DB row without a storage object is not repaired from storage
- storage metadata cannot create placement, access, runtime truth, or ready state
- public bucket placement does not grant access or frontend authority

## READY SEMANTICS PER MEDIA TYPE

This section is the canonical definition of `ready` for governed media.

Global ready rules:

- `ready` always means playback-safe, worker-owned, and storage-verified.
- Every `ready` asset must have a verified `playback_object_path`.
- Every `ready` asset must have an explicit `playback_format`.
- `ready` requires deterministic resolver behavior through
  `media_asset_id -> runtime_media -> backend read composition`.
- `ready` is not sufficient by itself to produce frontend playback when
  `runtime_media` or backend read composition cannot resolve the canonical
  media object.
- Storage object existence alone never makes an asset ready.
- Source-object existence alone never makes an asset ready.
- Bucket/path inference never makes an asset ready.
- Fallback logic never makes an asset ready.
- Request surfaces must never mark media ready.
- Worker-verified passthrough, where allowed, is still worker processing. It
  must enter `processing`, verify the source object, establish a canonical
  playback object, verify that playback object, write `playback_format`, and
  transition to `ready` only through the canonical worker boundary.

### Audio

Audio includes lesson audio unless the more specific home-audio rule below also
applies.

| Field | Value |
| --- | --- |
| Processing required | yes |
| Worker required | yes |
| Passthrough allowed | no |
| Source object used for playback | no |
| Derived object required | yes |
| Verification rule | worker must verify source object, transcode to MP3, write derived playback object, verify playback object existence, verify content type `audio/mpeg`, and verify duration metadata before `ready` |
| Allowed playback format | `mp3` only |

Audio ready means:

- the source object has been consumed only as worker input
- a derived MP3 playback object exists
- `app.media_assets.playback_object_path` points to the derived object
- `app.media_assets.playback_format = mp3`
- runtime resolution can derive `audio/mpeg`

WAV, M4A, or any other uploaded source audio must not be served as playback and
must not be marked ready without MP3 derivation.

### Image

Image means lesson image media with `media_type = image` and purpose
`lesson_media`. Course covers and profile media have stricter rules below.

| Field | Value |
| --- | --- |
| Processing required | yes |
| Worker required | yes |
| Passthrough allowed | yes, only as worker-verified playback-object passthrough |
| Source object used for playback | no |
| Derived object required | yes; this may be a no-transform worker-created playback copy |
| Verification rule | worker must verify source object, create or copy a canonical playback object, verify playback object existence, verify image content type, write explicit playback format, and prove runtime eligibility before `ready` |
| Allowed playback format | `jpg` or `png`; `jpeg` input must normalize to `jpg` if used as playback format |

Image passthrough is allowed only when the worker determines that the uploaded
image is already playback-safe. The worker must still establish a playback
object and must not expose or rely on the source object as playback truth.

### Video

Video means lesson video media with `media_type = video`.

| Field | Value |
| --- | --- |
| Processing required | yes |
| Worker required | yes |
| Passthrough allowed | yes, only as worker-verified MP4 playback-object passthrough |
| Source object used for playback | no |
| Derived object required | yes; this may be a no-transform worker-created playback copy |
| Verification rule | worker must verify source object, produce or copy a canonical MP4 playback object, verify playback object existence, verify content type `video/mp4`, verify duration metadata, write explicit playback format, and prove runtime eligibility before `ready` |
| Allowed playback format | `mp4` only |

Video ready does not define adaptive streaming, HLS, DASH, thumbnails, or preview
tracks. Those require a future contract before they can become readiness
requirements or playback formats.

### Document

Document means lesson document media with `media_type = document`.

| Field | Value |
| --- | --- |
| Processing required | yes |
| Worker required | yes |
| Passthrough allowed | yes, only as worker-verified PDF playback-object passthrough |
| Source object used for playback | no |
| Derived object required | yes; this may be a no-transform worker-created playback copy |
| Verification rule | worker must verify source object, produce or copy a canonical PDF playback object, verify playback object existence, verify content type `application/pdf`, write explicit playback format, and prove runtime eligibility before `ready` |
| Allowed playback format | `pdf` only |

Document ready does not require a preview image. A document preview is a separate
feature and must not be inferred as a ready requirement without a future
contract. Document delivery must still emit only the canonical media object;
`download_url` is not contract output.

### Course Cover

Course cover means `purpose = course_cover` and `media_type = image`.

| Field | Value |
| --- | --- |
| Processing required | yes |
| Worker required | yes |
| Passthrough allowed | no |
| Source object used for playback | no |
| Derived object required | yes |
| Verification rule | worker must verify source object, produce a normalized JPEG cover object, verify playback object existence, verify image content type `image/jpeg`, write explicit playback format, and prove backend read composition can emit `cover = { media_id, state, resolved_url } | null` without fallback |
| Allowed playback format | `jpg` only |

Course-cover ready requires a normalized derived JPEG. The canonical derivative
must preserve aspect ratio and must not exceed 1920 pixels in width unless a
future contract replaces that bound.

Course-cover playback delivery may use public physical storage only as delivery
infrastructure. Frontend truth remains the backend-authored `cover` object.

Course-cover assignment and clear belong to course structure authority. Media
ingest and worker processing must never assign, replace, or clear
`app.courses.cover_media_id`.

### Profile Media

Profile media means `purpose = profile_media`. Under the current profile and
community media contract, avatar/profile media ready is image-only.

| Field | Value |
| --- | --- |
| Processing required | yes |
| Worker required | yes |
| Passthrough allowed | no |
| Source object used for playback | no |
| Derived object required | yes |
| Verification rule | worker must verify source object, produce a normalized JPEG profile-media object, verify playback object existence, verify image content type `image/jpeg`, write explicit playback format, and prove runtime eligibility before avatar binding or profile/community publication can rely on it |
| Allowed playback format | `jpg` only |

Profile-media ready requires a normalized derived JPEG. The canonical derivative
must preserve aspect ratio and must not exceed 1920 pixels in width unless a
future contract replaces that bound.

Ready does not by itself bind an avatar, publish a profile-media placement, or
grant access. Avatar binding and profile/community placement remain owned by the
profile/community media boundary. Auth, onboarding, and `/profiles/me` patch
surfaces must not create binary media authority, upload authority, ready-state
authority, or storage authority.

Profile-media delivery may use public physical storage only as delivery
infrastructure. Frontend truth remains backend-authored governed media output.

### Home Audio

Home audio means `purpose = home_player_audio` and `media_type = audio`.

| Field | Value |
| --- | --- |
| Processing required | yes |
| Worker required | yes |
| Passthrough allowed | no |
| Source object used for playback | no |
| Derived object required | yes |
| Verification rule | worker must satisfy the audio ready rule, and home-audio runtime must exclude any ready item whose playback cannot be resolved from `media_asset_id` |
| Allowed playback format | `mp3` only |

Home-audio ready is audio ready plus home-audio runtime validity. If
`media.state != 'ready'`, home-audio output may retain the item with
`resolved_url = null` only where `home_audio_aggregation_contract.md` allows it.
If `media.state = 'ready'` and playback cannot be resolved from
`media_asset_id`, the item is contract-invalid and must be filtered before
response.

### Ready Format Matrix

| Media category | Required purpose/type | Playback object | Playback format | Passthrough |
| --- | --- | --- | --- | --- |
| Audio | `media_type = audio` | derived MP3 object | `mp3` | no |
| Image | `purpose = lesson_media`, `media_type = image` | canonical image playback object | `jpg` or `png` | worker-verified playback-object passthrough only |
| Video | `media_type = video` | canonical MP4 playback object | `mp4` | worker-verified playback-object passthrough only |
| Document | `media_type = document` | canonical PDF playback object | `pdf` | worker-verified playback-object passthrough only |
| Course cover | `purpose = course_cover`, `media_type = image` | derived normalized JPEG object | `jpg` | no |
| Profile media | `purpose = profile_media`, image only | derived normalized JPEG object | `jpg` | no |
| Home audio | `purpose = home_player_audio`, `media_type = audio` | derived MP3 object | `mp3` | no |

Any `ready` row outside this matrix is contract-invalid until a future contract
adds a deterministic ready rule for that media category.

## 8. Deletion Rules

Reference deletion and asset deletion are separate.

Reference owners may remove only their own references:

- placement delete may delete only the target `app.lesson_media` row
- lesson delete may delete lesson-owned `app.lesson_contents`, `app.lesson_media`,
  and `app.lessons` rows
- course cover clear may clear only `app.courses.cover_media_id`
- home-player mutation may change only home-player source rows
- profile/community mutation may change only profile/community placement or
  binding rows

Reference removal may request lifecycle evaluation, but it must not synchronously
delete `app.media_assets` or storage objects in that request path.

Media lifecycle deletion order:

1. collect the candidate `media_asset_id`
2. check every canonical usage surface deterministically
3. fail closed if any reference surface is unknown, ambiguous, or inconsistent
4. capture storage cleanup targets from the asset row for audit/retry
5. delete the `app.media_assets` row only after orphan verification passes
6. delete physical storage objects only after asset deletion is confirmed safe
7. record storage cleanup success, skip, or failure for retry

Storage deletion is not transactionally atomic with DB deletion. The contract
requires ordered, idempotent, auditable execution instead:

- storage must not be deleted before safe asset deletion
- storage deletion failure must leave retryable audit evidence
- storage deletion success must not be interpreted as DB deletion success
- storage deletion must never delete or modify canonical DB rows

## 9. Orphan Rules

### Media Asset Orphans

A media asset is an orphan only under the definition in
`media_lifecycle_contract.md`.

Storage state, frontend visibility, runtime projection absence, and
control-plane classification are not sufficient orphan proof.

### Storage Object Orphans

Storage object orphan classes:

- `unconfirmed_upload_object`: an object exists for a `pending_upload` asset
  before upload completion
- `asset_object_without_usage`: source or playback objects exist for a DB asset
  that has no canonical usage references
- `db_less_storage_object`: a storage object has no corresponding
  `app.media_assets` row
- `missing_object_for_asset`: a DB asset references an object that no longer
  exists

Allowed handling:

- `unconfirmed_upload_object` may exist until the explicit upload target
  expiration recorded or returned by ingest. If no explicit expiration is
  available, automated cleanup must fail closed.
- `asset_object_without_usage` may exist until media lifecycle confirms orphan
  status and deletes the `app.media_assets` row.
- `db_less_storage_object` has zero canonical media lifetime. It may be removed
  only by audited storage garbage collection after the job proves there is no
  canonical DB row, active upload session, or active worker write for the
  object. If that proof is unavailable, cleanup must fail closed.
- `missing_object_for_asset` is valid only while the asset is still
  `pending_upload` and upload completion has not succeeded. In `uploaded`,
  `processing`, or `ready`, missing storage is a broken lifecycle condition and
  must fail closed without fallback.

Cleanup owner:

- media lifecycle owns asset orphan evaluation and asset deletion
- storage cleanup owns physical object deletion only after media lifecycle has
  established safety
- control-plane observability may classify, log, or request evaluation, but it
  must not delete outside media lifecycle authority

Cleanup trigger:

- explicit lifecycle cleanup job
- periodic garbage collection
- post-placement-delete signal
- post-lesson-delete signal
- post-course-cover-clear signal
- post-home-player-reference-removal signal
- post-profile/community-reference-removal signal
- future canonical post-reference-removal signals declared by contract

No orphan cleanup may proceed from storage-only evidence.

## 10. Resolver Requirements

The resolver contract input is:

- `media_asset_id`
- `runtime_media`

Domain surfaces may use their own identifiers only to locate the canonical
`media_asset_id` before resolver execution. For example, a lesson surface may
start from `lesson_media_id`, but resolver behavior must still resolve through
the `media_asset_id -> runtime_media -> backend read composition` chain.

Resolver rules:

- use `runtime_media` as runtime truth for state and resolution eligibility
- use only `media_asset_id`, the matching `runtime_media` row, and delivery
  policy explicitly exposed by that runtime row
- construct only `media = { media_id, state, resolved_url } | null` for
  frontend-facing governed media
- return `resolved_url = null` for non-ready media where the owning surface
  allows non-ready items
- fail closed or exclude the item, according to the owning surface contract,
  when `state = ready` but storage signing or object verification fails
- public/private delivery handling must be explicit in `runtime_media` or in
  delivery policy explicitly referenced by the matching runtime row
- missing delivery policy is a resolution failure, not a fallback trigger
- storage signing is an implementation detail after runtime eligibility is
  established

Resolver forbidden inputs and behavior:

- hardcoded bucket
- hardcoded state
- storage-path-based branching
- direct `media_assets` inspection as a replacement for `runtime_media`
- direct Supabase Storage playback as business truth
- fallback to source objects, legacy media objects, public URLs, signed URLs,
  preview URLs, download URLs, or frontend reconstruction

## 11. Forbidden Patterns

The following patterns are invalid:

- storage as media identity, runtime truth, access truth, or frontend truth
- client-direct Supabase Storage upload for canonical media behavior
- upload endpoint returning a Supabase signed upload URL as contract truth
- upload completion based only on client assertion
- direct ready insertion
- direct `UPDATE app.media_assets SET state = 'ready'`
- direct `pending_upload -> ready`
- direct `uploaded -> ready` from any request surface
- request-surface passthrough readiness
- worker readiness without storage verification
- `ready` without `playback_object_path`
- audio `ready` without `playback_format = mp3`
- resolver hardcoding a bucket or state
- resolver constructing media from raw storage paths
- storage cleanup before asset deletion safety is confirmed
- asset deletion from placement delete, lesson delete, course-cover clear,
  home-player mutation, profile/community mutation, runtime projection, backend
  read composition, or frontend rendering
- DB row reconstruction from storage objects
- storage object deletion used as proof that DB cleanup happened
- adding `expired` or `deleted` to `app.media_state` without amending the
  canonical media pipeline and baseline contracts
