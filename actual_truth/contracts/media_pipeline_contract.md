# MEDIA PIPELINE CONTRACT

## STATUS

ACTIVE

This contract defines the canonical lesson-media ingest, placement, asset-lifecycle, and lesson-media pipeline law.
This contract operates under `SYSTEM_LAWS.md`.
Cross-domain media doctrine is defined only by `SYSTEM_LAWS.md`.

## 1. CONTRACT LAW

The canonical lesson-media write chain is:

```text
upload-url
-> upload-completion
-> placement attach
```

The canonical lesson-media read chain is:

```text
placement read
-> canonical governed media output under SYSTEM_LAWS.md
```

The following identities are distinct and must not be conflated:

- `media_asset_id`
  - canonical asset identity for lesson-media ingest and asset lifecycle
- `lesson_media_id`
  - canonical authored placement identity for lesson-media attachment

No existing route family is canonical as-is.
This contract defines the canonical lesson-media endpoint set directly.

## 2. LAYER OWNERSHIP

### Ingest Authority

The ingest layer owns:

- media asset identity creation
- upload target issuance
- upload completion confirmation
- initial asset lifecycle transition to `uploaded`

The ingest layer does not own:

- lesson placement
- lesson-media ordering
- runtime projection semantics
- execution response shape

Successful ingest creates:

- exactly one `media_assets` record
- zero `lesson_media` records

### Placement Authority

The placement layer owns:

- creation of one `lesson_media` row linking one lesson to one existing asset
- placement ordering
- authored placement identity

The placement layer does not own:

- asset creation
- upload completion
- runtime projection semantics
- execution response shape

Successful placement attach creates:

- exactly one `lesson_media` record
- zero new `media_assets` records

### Runtime Dependency Boundary

This contract depends on canonical runtime projection under `SYSTEM_LAWS.md` for governed playback.

Domain rules:

- `asset_state == ready` is not sufficient by itself to establish playable output
- `lesson_media` existence is not sufficient by itself to establish playable output
- lesson-media ingest and placement endpoints must not write directly to `runtime_media`

## 3. INGEST CONTRACT

### Canonical Upload-URL Endpoint

`POST /api/lessons/{lesson_id}/media-assets/upload-url`

Single responsibility:

- create one asset and issue one upload target

Single request meaning:

- authorize upload for a new asset scoped to one lesson context

This endpoint must not:

- create placement
- imply placement
- create runtime rows
- emit resolved playback data
- expose storage paths as contract truth

The path parameter `lesson_id` has exactly one meaning:

- authorization and source-scope context for asset ingest

`lesson_id` in this endpoint does not:

- create `lesson_media`
- imply that placement already exists
- authorize frontend inference about later placement

### Canonical Upload-Completion Endpoint

`POST /api/media-assets/{media_asset_id}/upload-completion`

Single responsibility:

- confirm that upload bytes for one existing asset were successfully uploaded

Single request meaning:

- transition one existing asset from `pending_upload` to `uploaded`

This endpoint must not:

- attach the asset to a lesson
- create placement
- create runtime rows
- emit resolved playback data

## 4. ASSET LIFECYCLE

The canonical lesson-media asset lifecycle field is:

- `asset_state`

Allowed asset states:

- `pending_upload`
- `uploaded`
- `processing`
- `ready`
- `failed`

Allowed transitions:

- `pending_upload -> uploaded`
- `uploaded -> processing`
- `processing -> ready`
- `processing -> failed`

Canonical meaning of each state:

- `pending_upload`
  - asset identity exists
  - upload target exists
  - upload completion has not been confirmed
- `uploaded`
  - upload completion is confirmed
  - worker-owned processing has not completed
- `processing`
  - canonical worker-owned processing is active
- `ready`
  - worker-owned processing is complete
  - asset is eligible for canonical runtime projection under `SYSTEM_LAWS.md`
- `failed`
  - canonical processing did not complete successfully

Forbidden lifecycle behavior:

- direct ready insertion
- direct `pending_upload -> ready`
- direct `pending_upload -> processing`
- direct frontend-authored state mutation
- direct playback metadata writes outside worker-owned transitions
- skipping worker-owned processing

## 5. PLACEMENT CONTRACT

### Canonical Placement-Attach Endpoint

`POST /api/lessons/{lesson_id}/media-placements`

Single responsibility:

- create one authored placement linking one lesson to one existing asset

Single request meaning:

- attach this existing asset to this lesson as one placement

This endpoint must only accept an already-created asset identity.

This endpoint must not:

- create upload targets
- accept upload bytes
- create new assets
- create runtime rows
- emit resolved playback data
- double as reorder, replace, or preview behavior

Placement preconditions:

- `lesson_id` must identify an existing lesson
- `media_asset_id` must identify an existing asset
- the asset must not be in `pending_upload`
- the asset must not be in `failed`

Placement law:

- placement is authored attachment only
- placement does not create runtime truth
- placement does not create execution response-shape authority

### Lesson-Media Placement Reorder/Delete Decision

Lesson-media placement reorder is canonical placement-layer behavior.

Lesson-media placement delete is canonical placement-layer behavior only when it means removing the authored `app.lesson_media` placement link.

The placement-layer source entity is `app.lesson_media`.

Canonical reorder surface:
`PATCH /api/lessons/{lesson_id}/media-placements/reorder`

Canonical delete surface:
`DELETE /api/media-placements/{lesson_media_id}`

Reorder may mutate only `app.lesson_media.position`.

Delete may delete only the target `app.lesson_media` row.

Neither reorder nor delete may create, update, or delete `app.media_assets`.

Neither reorder nor delete may write to `app.runtime_media`.

Asset cleanup after a placement is removed is a separate media lifecycle / cleanup concern and is not placement-delete authority.

The existing `/api/lesson-media/{lesson_id}/reorder` and `/api/lesson-media/{lesson_id}/{lesson_media_id}` write routes are temporary implementation drift and are not canonical surfaces.

## 6. REQUEST / RESPONSE CONTRACTS

### 6.1 Upload-URL Request

Endpoint:

`POST /api/lessons/{lesson_id}/media-assets/upload-url`

Request body:

```json
{
  "media_type": "audio | image | video | document",
  "filename": "string",
  "mime_type": "string",
  "size_bytes": 123
}
```

Rules:

- all fields are required
- there are no optional request fields
- `media_type` classifies the asset only
- `media_type` must not branch the endpoint into a second contract path

Response fields:

- `media_asset_id: uuid`
- `asset_state: pending_upload`
- `upload_url: string`
- `headers: map<string, string>`
- `expires_at: datetime`

Response rules:

- no placement identity may be returned
- no runtime identity may be returned
- no storage path may be returned as contract truth
- no resolved playback data may be returned

### 6.2 Upload-Completion Request

Endpoint:

`POST /api/media-assets/{media_asset_id}/upload-completion`

Request body:

```json
{}
```

Rules:

- the request body is empty
- there are no optional fields

Response fields:

- `media_asset_id: uuid`
- `asset_state: uploaded`

Response rules:

- no placement identity may be returned
- no runtime identity may be returned
- no resolved playback data may be returned

### 6.3 Placement-Attach Request

Endpoint:

`POST /api/lessons/{lesson_id}/media-placements`

Request body:

```json
{
  "media_asset_id": "uuid"
}
```

Rules:

- the request body has exactly one field
- the request body contains no lesson field because lesson scope is provided by the path
- there are no optional request fields
- the request cannot be interpreted as upload, replace, preview, or playback

Response fields:

- `lesson_media_id: uuid`
- `lesson_id: uuid`
- `media_asset_id: uuid`
- `position: int`
- `media_type: audio | image | video | document`
- `asset_state: uploaded | processing | ready`

Response rules:

- the response describes placement plus current asset lifecycle state only
- the response must not emit resolved playback data
- the response must not act as a preview or playback surface

### 6.4 Placement Read

Endpoint:

`GET /api/media-placements/{lesson_media_id}`

Response fields:

- `lesson_media_id: uuid`
- `lesson_id: uuid`
- `media_asset_id: uuid`
- `position: int`
- `media_type: audio | image | video | document`
- `asset_state: uploaded | processing | ready | failed`
- `media: canonical governed media object under SYSTEM_LAWS.md | null`

Read rules:

- `media` is required on canonical placement reads
- `media` must follow the canonical governed media representation defined only by `SYSTEM_LAWS.md`
- placement reads must not expose raw storage, preview-specific, signed-url, or download-url truth

## 7. FORBIDDEN PATTERNS

The following are forbidden by this contract:

- any polymorphic lesson-media endpoint
- any upload endpoint that also creates placement
- any completion endpoint that also attaches placement
- any placement endpoint that also uploads or completes ingest
- any read endpoint that also acts as preview, batch-preview, reorder, or delete
- `purpose` as a public contract field
- `link_scope` as a public contract field
- `lesson_id` in request bodies where lesson scope is already defined by the path
- `course_id` as a public contract branch for lesson-media pipeline endpoints
- `storage_path`
- `object_path`
- `preview_ready`
- `resolved_preview_url`
- `download_url`
- `signed_url`
- `playback_url`
- `playback_format` as lesson-media contract truth
- direct runtime-media writes from ingest or placement endpoints

## 8. FRONTEND ALIGNMENT TARGET

Authoring frontend may call only the canonical lesson-media pipeline endpoints:

- `POST /api/lessons/{lesson_id}/media-assets/upload-url`
- `POST /api/media-assets/{media_asset_id}/upload-completion`
- `POST /api/lessons/{lesson_id}/media-placements`
- `PATCH /api/lessons/{lesson_id}/media-placements/reorder`
- `GET /api/media-placements/{lesson_media_id}`
- `DELETE /api/media-placements/{lesson_media_id}`

If implementation drift exposes extra media fields:

- frontend must ignore them as non-authoritative

## 9. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

The current repository contains implementation drift that does not amend this contract.

Known drift includes:

- route families that still mix upload, completion, attach, status, preview, reorder, or delete behavior
- public request shapes that still include `purpose` or `link_scope`
- preview-specific metadata
- repository and route paths that still expose storage-oriented fields

These are implementation drift only.
They are not contract truth.

## 10. FINAL ASSERTION

This contract is deterministic, single-meaning, and enforceable.

It is valid only if all future implementation work preserves these laws:

- ingest does not imply placement
- placement does not imply playback
- lesson-media pipeline endpoints do not create runtime truth directly
- no polymorphic lesson-media endpoint survives
- no public request field changes endpoint meaning
