# HOME AUDIO AGGREGATION CONTRACT

## STATUS

ACTIVE

This contract materializes the canonical home-audio aggregation domain.
This contract operates under `SYSTEM_LAWS.md`, `media_unified_authority_contract.md`, `media_pipeline_contract.md`, and `course_public_surface_contract.md`.
This contract owns home-audio inclusion law, home-audio access law, home-audio runtime validity/filtering law, and home-audio runtime projection read-only law.
This contract does not define general media doctrine, media representation doctrine, course/public semantics except by dependency reference, or execution response-shape law.

## 1. CONTRACT LAW

- Home-audio aggregation is a domain concern distinct from execution response shape.
- Inclusion, access, runtime validity/filtering, and runtime projection constraints must be owned together as one canonical home-audio domain.
- Inclusion does NOT grant access.
- Access is evaluated after inclusion.

## 2. DEPENDENCY REFERENCES

- Canonical media identity, source/read separation, runtime read projection where in scope, and frontend media representation are governed by `media_unified_authority_contract.md` and `SYSTEM_LAWS.md`.
- Media lifecycle and pipeline law are governed by `media_pipeline_contract.md`.
- Canonical lesson-access semantics for course-linked items are governed by `course_public_surface_contract.md`.
- This contract does not redefine those upstream rules.

## 3. INCLUSION LAW

- Inclusion in HOME_AUDIO_RUNTIME is strictly controlled by source-truth fields on source tables.

### direct_upload inclusion

- A direct upload participates ONLY if:
  - `home_player_uploads.active = true`
  - `media_asset_id` exists and is valid
  - media asset purpose = `home_player_audio`
  - media asset type = `audio`

### course_link inclusion

- A course link participates ONLY if:
  - `home_player_course_links.enabled = true`
  - referenced `lesson_media` exists
  - referenced course is published
  - linked media asset type = `audio`

- No implicit inclusion, ranking, fallback inclusion, or system-derived teacher visibility is allowed.
- `app.is_test_row_visible(...)` is NOT a teacher-controlled inclusion flag.
- `app.is_test_row_visible(...)` is a test-data visibility guard only and MUST NOT be interpreted as runtime inclusion truth.

## 3A. SOURCE AND READ AUTHORITY BOUNDARY

- `app.home_player_course_links` is canonical source truth for course-linked
  home-audio inclusion.
- Backend aggregation and read composition are read authority for course-linked
  home-audio output.
- `runtime_media` is not the mandatory direct source authority for
  `app.home_player_course_links`.
- `runtime_media` remains read-only projection authority where in scope.
- Projection drift must not become source truth.
- Canonical access for course-linked home audio still derives only from the
  approved course/lesson access truth referenced by this contract.

## 3B. STUDIO SOURCE MANAGEMENT SURFACE

The canonical Studio Home Player management surface is exactly:

- `GET /studio/home-player/library`
- `POST /studio/home-player/uploads`
- `PATCH /studio/home-player/uploads/{upload_id}`
- `DELETE /studio/home-player/uploads/{upload_id}`
- `POST /studio/home-player/course-links`
- `PATCH /studio/home-player/course-links/{link_id}`
- `DELETE /studio/home-player/course-links/{link_id}`

No alternate Studio Home Player management route family is canonical.

### direct_upload source-row create law

`POST /studio/home-player/uploads` creates one direct-upload source row linking
one teacher to one existing canonical `media_asset_id`.

Create preconditions:

- the referenced `media_asset_id` MUST exist
- the referenced asset MUST have `purpose = home_player_audio`
- the referenced asset MUST have `media_type = audio`
- the caller MUST prove teacher ownership of that exact `media_asset_id`

Ownership proof law:

- purpose/type validation alone is insufficient
- ownership MUST derive from canonical asset owner context for the referenced
  `home_player_audio` asset
- cross-user asset usage is forbidden
- a teacher MUST NOT create a `home_player_uploads` row pointing at another
  teacher's `media_asset_id`

Mutation boundary:

- create/update/delete on `/studio/home-player/uploads*` may mutate only
  `app.home_player_uploads`
- these routes must not rewrite media-asset ownership, create playback URLs, or
  create learner runtime truth

### course_link source-row law

`POST /studio/home-player/course-links` creates or updates one course-link
source row linking one teacher-owned `lesson_media` item into Home audio.

Create/update/delete preconditions:

- the referenced `lesson_media` row MUST exist
- the linked media asset MUST be `media_type = audio`
- the linked media asset MUST remain canonical lesson media
- the caller MUST be the owner of the referenced course

Mutation boundary:

- `/studio/home-player/course-links*` may mutate only
  `app.home_player_course_links`
- these routes must not create media assets, rewrite lesson-media ownership, or
  create learner runtime truth

## 4. ACCESS LAW

- Inclusion does NOT grant access.
- Access is evaluated after inclusion.

### direct_upload access

- Visible ONLY if:
  - `teacher_id == auth.uid()`

### course_link access

- Visible ONLY if canonical lesson access is satisfied under `course_public_surface_contract.md`.

- No alternative access checks are allowed.

## 5. RUNTIME VALIDITY AND FILTERING LAW

- For HOME_AUDIO_RUNTIME, a response item is valid ONLY if its playback identity is a valid `media_asset_id`.
- If `media.state != 'ready'`, the item MAY remain in HOME_AUDIO_RUNTIME and MUST return `resolved_url = null`.
- If `media.state = 'ready'` and playback cannot be resolved from `media_asset_id`, that item is contract-invalid and MUST be excluded from HOME_AUDIO_RUNTIME before response.
- Invalid ready items MUST be filtered, not propagated.
- Invalid ready items MUST NOT trigger response-level failure.
- No partial resolution is allowed.
- HOME_AUDIO_RUNTIME returns only contract-valid items.
- Contract-invalid items MUST be removed before frontend response composition.

## 6. RUNTIME PROJECTION LAW

- Runtime projection MUST remain read-only.
- Runtime projection MUST NOT modify source-table inclusion flags.
- Runtime projection MUST NOT modify `media_assets`.
- Runtime projection MUST NOT introduce new playback identity.
- Runtime projection MUST NOT be treated as the source table for
  course-linked home-audio inclusion.
- Backend composition MAY read canonical source truth and projection/read
  inputs, but MUST NOT write source authority.

## 6A. FRONTEND CONSUMPTION LAW

The canonical learner-facing Home Player runtime surface is the mounted Home
Player UI consuming:

- `GET /home/audio`

Rules:

- the learner-facing Home Player surface MUST consume `/home/audio`
- frontend MUST NOT replace the Home Player runtime with unrelated course,
  landing, or showcase data
- frontend MUST NOT omit the `/home/audio` consumer while the Home Player
  feature is mounted
- frontend MUST NOT bypass `/home/audio` by constructing playback state or
  playback URLs from source tables, `media_asset_id`, or storage fields
- frontend MUST render only backend-composed governed Home audio output

## 7. EXCLUDED SCOPE

- This contract does not define general media doctrine.
- This contract does not define frontend media representation doctrine.
- This contract does not define course/public semantics except by dependency reference.
- This contract does not define execution response shape, field order, nullability, or transport-output constraints.
- Upstream canonical owners remain authoritative for media identity, fallback prohibition, frontend media-object shape, and canonical lesson-access predicates.
