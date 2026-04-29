# COURSE + LESSON EDITOR CONTRACT

## STATUS

ACTIVE

This contract materializes the canonical, deterministic Course + Lesson Editor domain.
It encodes already-ratified decisions only.
Cross-domain separation doctrine is defined only by `SYSTEM_LAWS.md`.
Implementation drift does not alter this contract.

## 1. CONTRACT LAW

The Course + Lesson Editor domain is governed by the following laws:

- course structure and lesson structure are not lesson content
- lesson content is not lesson structure
- `lesson_document_v1` is the canonical rebuilt-editor lesson-content format
- backend document validation and canonical JSON serialization are the only
  rebuilt-editor content authority at the write boundary

The canonical domain flow is:

~~~text
course structure write -> app.courses
lesson structure write -> app.lessons
lesson content write -> backend document validation -> app.lesson_contents
~~~

No runtime code, legacy route, or active fallback may override this contract.

Drip scheduling semantics are defined only by
`course_drip_schedule_contract.md`.
This contract owns editor structure read/write shapes only.

## 2. AUTHORITY MODEL

Canonical authorities are:

- course identity authority: `app.courses`
- course structure authority: `app.courses`
- course cover identity authority: `app.courses.cover_media_id`
- lesson identity authority: `app.lessons`
- lesson ordering authority: `app.lessons.position`
- lesson structure authority: `app.lessons`
- lesson content authority: `app.lesson_contents`
- rebuilt-editor document content authority:
  `app.lesson_contents.content_document`

Forbidden as authority:

- `StudioLesson` mixed payloads
- editor Quill Delta
- Markdown as rebuilt-editor content authority
- `content_markdown` as rebuilt-editor content authority
- frontend-normalized markdown
- frontend preview markdown
- frontend cover preview state
- frontend-reconstructed cover URLs
- raw joined studio lesson lists that include `content_markdown`
- raw joined studio lesson lists that include `content_document`
- legacy lesson alias `title`
- `is_intro`
- raw storage paths
- raw database table access used as a semantic shortcut

## 3. STRUCTURE VS CONTENT LAW

Course structure contains only:

- `id`
- `slug`
- `title`
- `course_group_id`
- `group_position`
- `cover_media_id`
- `price_amount_cents`

Lesson structure contains only:

- `id`
- `course_id`
- `lesson_title`
- `position`

Lesson content contains only:

- `content_document`

Canonical separation rules:

- `app.lessons` remains structure-only
- `app.lesson_contents` remains content-only
- `content_document` must never appear on a structure-only write endpoint
- legacy `content_markdown` must never appear on a structure-only write
  endpoint
- `lesson_title` and `position` must never appear on a content-only write endpoint

Drip shape boundary:

- studio/editor read and write shapes may include subordinate
  `drip_authoring` request/response objects
- `course_drip_schedule_contract.md` remains the only semantic owner for
  custom-drip timing semantics, mode resolution, worker behavior, and schedule
  locks
- this contract defines editor-facing shape only

## 3A. COURSE COVER AUTHORING LAW

Course cover authoring is course structure behavior.

Canonical cover identity:

- `app.courses.cover_media_id`

Canonical cover read output:

- `cover = { media_id, state, resolved_url } | null`

Rules:

- `cover_media_id` is the only course-cover identity field
- `cover` is backend-authored read data only
- `cover` must never be accepted as write input
- `media_id`, `state`, and `resolved_url` inside `cover` are read-only backend output
- frontend must render persisted course cover media only from backend-provided `cover.resolved_url`
- frontend must never reconstruct cover URLs from storage paths, media IDs, filenames, buckets, upload URLs, signed URLs, preview URLs, or local preview state
- media ingest may create media identity and upload state only
- worker processing may create media/runtime readiness only
- media ingest and worker processing must never assign, replace, or clear `app.courses.cover_media_id`
- teacher cover assignment and clear must use course structure authority only
- `/api/media/cover-*` is not canonical course-cover authoring authority
- local preview state is transient UI state only and must never become persisted truth

This law operates under the cross-domain governed media representation defined by `SYSTEM_LAWS.md`.

## 4. CANONICAL ENTRYPOINTS

### Editor Structure Reads

- `GET /studio/courses`
- `GET /studio/courses/{course_id}`
- `GET /studio/courses/{course_id}/lessons`

### Editor Structure Writes

- `POST /studio/courses`
- `PATCH /studio/courses/{course_id}`
- `PUT /studio/courses/{course_id}/drip-authoring`
- `POST /studio/courses/{course_id}/reorder`
- `POST /studio/courses/{course_id}/move-family`
- `DELETE /studio/courses/{course_id}`
- `POST /studio/courses/{course_id}/lessons`
- `PATCH /studio/lessons/{lesson_id}/structure`
- `PATCH /studio/courses/{course_id}/lessons/reorder`
- `DELETE /studio/lessons/{lesson_id}`

### Editor Content Write

- `PATCH /studio/lessons/{lesson_id}/content`

### Editor Content Read

- `GET /studio/lessons/{lesson_id}/content`

No mixed `POST /studio/lessons` or mixed `PATCH /studio/lessons/{lesson_id}` endpoint survives as canonical truth.

## 5. STRUCTURE WRITE CONTRACTS

### 5.1 Course Family List

Endpoint:

`GET /studio/course-families`

Response:

~~~json
{
  "items": [
    {
      "id": "uuid",
      "name": "string",
      "teacher_id": "uuid",
      "created_at": "iso-datetime",
      "course_count": 0
    }
  ]
}
~~~

Rules:

- returns canonical persisted course-family rows
- `course_count` is a derived read field
- family identity is still linked to courses through `course_group_id`

### 5.2 Course Family Create

Endpoint:

`POST /studio/course-families`

Request:

~~~json
{
  "name": "string"
}
~~~

Response:

Same canonical course-family structure as the list response item.

Rules:

- creates a canonical course family before any course exists
- no course fields are accepted in this request

### 5.3 Course Create

Endpoint:

`POST /studio/courses`

Request:

~~~json
{
  "title": "string",
  "slug": "string",
  "course_group_id": "uuid",
  "price_amount_cents": 123,
  "drip_enabled": true,
  "drip_interval_days": 7,
  "cover_media_id": "uuid | null"
}
~~~

Response:

Same canonical studio course detail read shape as `GET /studio/courses/{course_id}`.

Rules:

- mutates course structure only
- create appends the new course to the end of the requested family
- caller-authored `group_position` is forbidden
- `cover` is a backend-authored read field, not a write authority
- `cover_media_id` assigns cover identity when non-null
- `cover_media_id: null` means no cover identity is assigned at creation
- `short_description` is forbidden in this request
- lesson fields are forbidden in this request

### 5.4 Course Update

Endpoint:

`PATCH /studio/courses/{course_id}`

Request:

~~~json
{
  "title": "string",
  "slug": "string",
  "price_amount_cents": 123,
  "cover_media_id": "uuid | null"
}
~~~

Response:

Same canonical studio course detail read shape as `GET /studio/courses/{course_id}`.

Rules:

- request is partial
- mutates course metadata only
- `cover_media_id` assigns cover identity when non-null
- `cover_media_id: null` clears the cover identity
- omitted `cover_media_id` means no cover change
- `cover` is a backend-authored read field, not a write authority
- drip-authoring writes are forbidden on this endpoint
- `course_group_id` is forbidden in this request
- `group_position` is forbidden in this request
- `short_description` is forbidden
- lesson fields are forbidden
- `content_markdown` is forbidden

### 5.4A Studio Course Summary Read Shape

Endpoint:

`GET /studio/courses`

Response:

~~~json
{
  "items": [
    {
      "id": "uuid",
      "slug": "string",
      "title": "string",
      "teacher": {
        "user_id": "uuid",
        "display_name": "string | null"
      },
      "course_group_id": "uuid",
      "group_position": 0,
      "cover_media_id": "uuid | null",
      "cover": {
        "media_id": "string",
        "state": "string",
        "resolved_url": "string | null"
      },
      "price_amount_cents": 123,
      "required_enrollment_source": "purchase | intro | null",
      "enrollable": true,
      "purchasable": false,
      "drip_authoring": {
        "mode": "custom_lesson_offsets | legacy_uniform_drip | no_drip_immediate_access",
        "schedule_locked": false,
        "lock_reason": "first_enrollment_exists | null",
        "legacy_uniform": {
          "drip_interval_days": 7
        }
      }
    }
  ]
}
~~~

Rules:

- `drip_authoring` is a studio-only subordinate read shape
- list payload does not own lesson ordering or lesson structure
- list payload does not duplicate custom schedule rows

### 5.4B Studio Course Detail Read Shape

Endpoint:

`GET /studio/courses/{course_id}`

Response:

~~~json
{
  "id": "uuid",
  "slug": "string",
  "title": "string",
  "teacher": {
    "user_id": "uuid",
    "display_name": "string | null"
  },
  "course_group_id": "uuid",
  "group_position": 0,
  "cover_media_id": "uuid | null",
  "cover": {
    "media_id": "string",
    "state": "string",
    "resolved_url": "string | null"
  },
  "price_amount_cents": 123,
  "required_enrollment_source": "purchase | intro | null",
  "enrollable": true,
  "purchasable": false,
  "drip_authoring": {
    "mode": "custom_lesson_offsets | legacy_uniform_drip | no_drip_immediate_access",
    "schedule_locked": false,
    "lock_reason": "first_enrollment_exists | null",
    "legacy_uniform": {
      "drip_interval_days": 7
    },
    "custom_schedule": {
      "rows": [
        {
          "lesson_id": "uuid",
          "unlock_offset_days": 0
        }
      ]
    }
  }
}
~~~

Rules:

- `custom_schedule.rows` is a studio-only subordinate read shape
- lesson ordering authority remains `GET /studio/courses/{course_id}/lessons`
- detail payload must not duplicate lesson titles or positions inside
  `custom_schedule.rows`

### 5.4C Studio Course Drip Authoring Write Shape

Endpoint:

`PUT /studio/courses/{course_id}/drip-authoring`

Request:

~~~json
{
  "mode": "custom_lesson_offsets | legacy_uniform_drip | no_drip_immediate_access",
  "legacy_uniform": {
    "drip_interval_days": 7
  },
  "custom_schedule": {
    "rows": [
      {
        "lesson_id": "uuid",
        "unlock_offset_days": 0
      }
    ]
  }
}
~~~

Response:

Same canonical studio course detail read shape as `GET /studio/courses/{course_id}`.

Rules:

- request owns studio drip-authoring shape only
- request must not include course metadata fields
- request must not include lesson titles or lesson positions
- request/response shapes are subordinate to
  `course_drip_schedule_contract.md`

### 5.4D Studio Course Lock Error Shape

Response:

~~~json
{
  "code": "studio_course_schedule_locked",
  "detail": "Schedule-affecting edits are locked after first enrollment.",
  "course_id": "uuid",
  "schedule_locked": true
}
~~~

Rules:

- this shape is returned when studio drip-authoring writes are locked
- this shape does not redefine schedule-lock semantics

### 5.5 Course Reorder Within Family

Endpoint:

`POST /studio/courses/{course_id}/reorder`

Request:

~~~json
{
  "group_position": 0
}
~~~

Response:

Same canonical course structure response as course create.

Rules:

- mutates ordering only inside the existing `course_group_id`
- `group_position` must be canonical for the current family
- `course_group_id` is forbidden in this request
- no metadata fields are accepted in this request

### 5.6 Course Move To Family

Endpoint:

`POST /studio/courses/{course_id}/move-family`

Request:

~~~json
{
  "course_group_id": "uuid"
}
~~~

Response:

Same canonical course structure response as course create.

Rules:

- moves the course to a different family and appends it at the target family end
- `course_group_id` must differ from the current family
- `group_position` is forbidden in this request
- no metadata fields are accepted in this request

### 5.7 Course Delete

Endpoint:

`DELETE /studio/courses/{course_id}`

Response:

~~~json
{
  "deleted": true
}
~~~

Rules:

- deletes course identity and structure boundary
- does not define lesson-content semantics
- no content payload is accepted

### 5.8 Lesson Create

Endpoint:

`POST /studio/courses/{course_id}/lessons`

Request:

~~~json
{
  "lesson_title": "string",
  "position": 1
}
~~~

Response:

~~~json
{
  "id": "uuid",
  "course_id": "uuid",
  "lesson_title": "string",
  "position": 1
}
~~~

Rules:

- creates lesson structure only
- does not create lesson content
- `content_markdown` is forbidden
- lesson runtime alias `title` is forbidden

### 5.7 Lesson Structure Update

Endpoint:

`PATCH /studio/lessons/{lesson_id}/structure`

Request:

~~~json
{
  "lesson_title": "string",
  "position": 1
}
~~~

Response:

~~~json
{
  "id": "uuid",
  "course_id": "uuid",
  "lesson_title": "string",
  "position": 1
}
~~~

Rules:

- request is partial
- mutates lesson structure only
- `content_markdown` is forbidden
- lesson runtime alias `title` is forbidden

### 5.8 Lesson Reorder

Endpoint:

`PATCH /studio/courses/{course_id}/lessons/reorder`

Request:

~~~json
{
  "lessons": [
    { "id": "uuid", "position": 1 },
    { "id": "uuid", "position": 2 }
  ]
}
~~~

Response:

~~~json
{
  "ok": true
}
~~~

Rules:

- mutates ordering only
- payload must include every lesson in the course exactly once
- `lesson_title` is forbidden
- `content_markdown` is forbidden

### 5.9 Lesson Delete

Endpoint:

`DELETE /studio/lessons/{lesson_id}`

Response:

~~~json
{
  "deleted": true
}
~~~

Rules:

- deletes lesson identity and structure boundary
- does not accept content payload
- does not redefine content authority

### Lesson Delete Media Cleanup Decision

Lesson delete is allowed when lesson-media placements exist.

The lesson delete flow owns removal of the lesson-owned rows required to delete the lesson:

* the target `app.lesson_contents` row, if present
* all `app.lesson_media` placement rows whose `lesson_id` is the deleted lesson
* the target `app.lessons` row

Lesson delete may mutate `app.lesson_media` only to remove placement links for the lesson being deleted.

Lesson delete must not create, update, reorder, or otherwise mutate placement rows for any other lesson.

Lesson delete must not create, update, or delete `app.media_assets`.

Lesson delete must not write to `app.runtime_media`.

Removal of media assets or storage objects after lesson deletion is a separate media lifecycle / cleanup concern. It may occur only through the media lifecycle / cleanup authority after placement links are removed and orphan status is re-evaluated.

Lesson delete success means the lesson, its content row, and its lesson-owned placement links were removed. It does not mean media asset cleanup has completed.

Baseline FK or cascade behavior may support this decision only if it preserves the same authority split and does not expand lesson delete into media asset or runtime-media authority.

## 5A. CONTENT READ CONTRACT

Endpoint:

`GET /studio/lessons/{lesson_id}/content`

Responsibility:

- read lesson content only for editor hydration

Response body:

~~~json
{
  "lesson_id": "uuid",
  "content_document": {
    "schema_version": "lesson_document_v1",
    "blocks": []
  },
  "media": []
}
~~~

Response transport metadata:

- `ETag`

Rules:

- reads existing persisted rebuilt-editor content from
  `app.lesson_contents.content_document`
- `lesson_id` identifies the lesson whose content was read
- `content_document` is backend-authored persisted `lesson_document_v1`
  canonical JSON
- `media` is a read-only backend-authored list of governed media objects when applicable, otherwise an empty list
- response must not include lesson structure fields such as `lesson_title` or `position`
- response must not include course structure payload
- response must not expose storage paths, signed URLs, upload URLs, frontend-resolved URLs, or raw media resolver fields
- the `ETag` transport metadata is the canonical editor content concurrency token
- this endpoint must not mutate lesson structure or lesson content
- structure endpoints must not expose `content_document`, legacy
  `content_markdown`, content media, or content concurrency tokens

## 6. CONTENT WRITE CONTRACT

Endpoint:

`PATCH /studio/lessons/{lesson_id}/content`

Responsibility:

- mutate lesson content only

Request:

~~~json
{
  "content_document": {
    "schema_version": "lesson_document_v1",
    "blocks": []
  }
}
~~~

Required request transport metadata:

- `If-Match`

Response:

~~~json
{
  "lesson_id": "uuid",
  "content_document": {
    "schema_version": "lesson_document_v1",
    "blocks": []
  }
}
~~~

Response transport metadata:

- `ETag`

Rules:

- `content_document` is the only rebuilt-editor request field
- request meaning is singular and non-branching
- `If-Match` must contain the current backend-issued content concurrency token
- writes without a matching `If-Match` token must fail without persistence
- successful writes must emit a replacement `ETag`
- backend must validate `lesson_document_v1` before persistence
- backend must persist the backend-canonical JSON document
- response must return the persisted backend-canonical JSON document
- ETag calculation must use canonical document bytes
- `lesson_title` is forbidden
- `position` is forbidden
- `course_id` is forbidden
- legacy `content_markdown` is forbidden as rebuilt-editor write authority
- no structure fields may appear

Validation law:

- invalid canonical media references must be rejected
- invalid document schema versions must be rejected
- invalid block nodes, mark nodes, list shapes, and CTA nodes must be rejected
- raw storage-path references must be rejected
- raw HTML media tags must be rejected
- unresolved raw media URLs must be rejected

## 7. STRUCTURE READ CONTRACT

### 7.1 Editor Structure Reads

`GET /studio/courses` response:

~~~json
{
  "items": [
    {
      "id": "uuid",
      "slug": "string",
      "title": "string",
      "course_group_id": "uuid",
      "group_position": 0,
      "cover_media_id": "uuid | null",
      "cover": {
        "media_id": "string",
        "state": "string",
        "resolved_url": "string | null"
      },
      "price_amount_cents": 123,
      "drip_enabled": true,
      "drip_interval_days": 7
    }
  ]
}
~~~

`GET /studio/courses/{course_id}` response:

- same canonical course structure object as above

`GET /studio/courses/{course_id}/lessons` response:

~~~json
{
  "items": [
    {
      "id": "uuid",
      "course_id": "uuid",
      "lesson_title": "string",
      "position": 1
    }
  ]
}
~~~

Rules:

- editor structure reads must not expose `content_document`
- editor structure reads must not expose legacy `content_markdown`
- editor structure reads must not expose content media
- editor structure reads must not expose content concurrency tokens
- `GET /studio/courses` must exist exactly once
- `GET /studio/courses/{course_id}/lessons` is structure-only and must not leak content

## 8. PUBLIC SURFACE POINTER

Public course and lesson read semantics are defined only by `course_public_surface_contract.md`.

This contract defines no public response semantics, public field meaning, visibility rules, or learner-visible projection rules.

### Edit Mode / Preview Mode Decision

Edit Mode is the only authoring and mutation surface for the Course + Lesson Editor.

Preview Mode is read-only.

Preview Mode must render from the same canonical lesson text, lesson media, and course cover truth as learner mode.

Preview Mode must not become an alternate content authority.

Preview Mode must not become an alternate media authority.

Preview Mode must not become an alternate course-cover authority.

Differences between Preview Mode UI and Learner UI must be presentation-only and must not change canonical truth.

Preview Mode and Learner Lesson View MUST use the same `lesson_view_surface`
response shape for persisted lesson body and media rendering.

Editor Preview MUST consume:

`GET /courses/lessons/{lesson_id}?preview=true`

Preview mode requires teacher/studio authorization. It MAY bypass learner
enrollment gating only for the explicit preview request, and that bypass MUST
NOT create, mutate, imply, or masquerade as learner course access.

Editor preview may wrap the learner renderer in editor chrome, but it MUST NOT
bypass the learner renderer by calling a lower-level preview primitive directly.

Content block rendering, media rendering, spacing, link handling, and fallback
behavior MUST be identical between Preview Mode and Learner Lesson View.

Lesson navigation, enrollment/access gating, and course-entry CTA composition
MUST live outside the shared lesson body renderer.

Draft preview is not allowed as Preview Mode authority.

Preview Mode must be persisted-only unless a later contract explicitly defines a separate non-authoritative draft view with a distinct name and boundary.

A new backend mutation surface for Preview Mode is forbidden.

A new backend read surface is forbidden for persisted lesson preview authority
when `lesson_view_surface` can compose persisted lesson text, lesson media, and
course cover. Any future Preview helper surface must remain read-only
projection only, must not return a different lesson rendering shape, and must
not introduce studio-only frontend transforms.

## 9. DOCUMENT EDITOR LAW

Rebuilt-editor document law:

- `lesson_document_v1` is the canonical rebuilt-editor lesson-content format
- `content_document` is canonical only on `app.lesson_contents`
- backend document validation and canonical JSON serialization are the only
  rebuilt-editor write-boundary authority
- frontend normalization is convenience only and never authority
- editor-internal UI state is transient only
- Quill Delta must never be stored as contract truth
- Markdown must never be stored as rebuilt-editor contract truth

Canonical document node law:

- document root must declare `schema_version = "lesson_document_v1"`
- document root must contain explicit `blocks`
- paragraph boundaries are explicit block nodes, not newline-count semantics
- headings carry explicit heading level
- bullet and ordered lists carry explicit list-item structure
- inline formatting uses explicit marks: `bold`, `italic`, `underline`, `link`
- clear formatting removes marks without deleting text or collapsing blocks
- lesson media references must use typed media nodes that reference
  `lesson_media_id`
- magic-link / CTA content must use explicit CTA nodes, not incidental Markdown
  link text
- the authoring UI must present one continuous writing surface, not a stack of
  visible per-block editor containers
- continuous authoring is presentation-only; every edit must still map
  deterministically to `lesson_document_v1` blocks and nodes
- formatting commands must apply to the current selected text range only
- collapsed cursor focus must not format the whole block or document
- partial structural formatting, including heading and list conversion, must
  split selected text into deterministic `lesson_document_v1` blocks/nodes
- user-facing editor, preview, and learner UI must not render internal model,
  schema, Markdown/Quill authority, or debug labels
- editor authoring must use a clean white writing surface
- persisted preview and learner lesson rendering may offer local Glass/Paper
  reading modes, but reading mode is presentation-only and must not be
  serialized, persisted, or sent to backend APIs

Document fixture corpus law:

- rebuilt-editor adapter, validator, preview, and learner work must bind to a
  `lesson_document_v1` fixture corpus instead of inventing per-surface
  semantics
- the active rebuilt-editor fixture corpus artifact is
  `actual_truth/contracts/lesson_document_fixture_corpus.json`
- legacy Markdown fixtures may remain only as compatibility/import/export
  evidence

Forbidden rebuilt-editor persistence:

- raw HTML media tags
- raw Markdown image URLs for governed lesson media
- raw document links to internal media paths
- storage-path references
- guessed playback URLs
- frontend-authored resolved media URLs
- Markdown media tokens as rebuilt-editor authority
- Quill Delta as rebuilt-editor authority

Write-boundary law:

- backend must validate or reject incoming `lesson_document_v1`
- backend output is the persisted truth
- content write responses must reflect backend-canonical JSON
- backend validation must not shell out to Flutter
- backend validation must not depend on Markdown round-trip equivalence

## 10. FORBIDDEN PATTERNS

The following are forbidden:

- `POST /studio/lessons` as canonical truth
- mixed `PATCH /studio/lessons/{lesson_id}` as canonical truth
- `content_document` in any structure endpoint
- `content_markdown` in any structure endpoint
- content media in any structure endpoint
- content concurrency tokens in any structure endpoint
- `lesson_title` in the content endpoint
- `position` in the content endpoint
- `title` as lesson runtime alias
- `is_intro` as lesson authority
- duplicate `GET /studio/courses`
- `/api/media/cover-*` as course-cover authoring authority
- `cover` as course-cover write authority
- frontend-reconstructed cover URLs
- worker assignment, replacement, or clear of `app.courses.cover_media_id`
- raw `app.lessons` + `app.lesson_contents` collapse as one semantic surface
- frontend markdown normalization treated as authority
- frontend editor state treated as authority
- Markdown round-trip equivalence treated as rebuilt-editor authority
- backend Flutter subprocess validation treated as rebuilt-editor authority
- fallback aliases for lesson fields
- raw table access used to bypass canonical surfaces

## 11. FRONTEND ALIGNMENT TARGET

Editor frontend may use only these canonical structure surfaces:

- `GET /studio/courses`
- `GET /studio/courses/{course_id}`
- `GET /studio/courses/{course_id}/lessons`
- `POST /studio/courses`
- `PATCH /studio/courses/{course_id}`
- `POST /studio/courses/{course_id}/reorder`
- `POST /studio/courses/{course_id}/move-family`
- `DELETE /studio/courses/{course_id}`
- `POST /studio/courses/{course_id}/lessons`
- `PATCH /studio/lessons/{lesson_id}/structure`
- `PATCH /studio/courses/{course_id}/lessons/reorder`
- `DELETE /studio/lessons/{lesson_id}`

Editor frontend may use only this canonical content read surface:

- `GET /studio/lessons/{lesson_id}/content`

Editor frontend may use only this canonical content write surface:

- `PATCH /studio/lessons/{lesson_id}/content`

Editor frontend must render course covers only from backend-provided `cover.resolved_url`.

Frontend model separation law:

- editor structure models must not contain `content_document`
- editor structure models must not contain legacy `content_markdown`
- editor structure models must not contain content media or content concurrency tokens
- editor content read models may contain only `lesson_id`,
  `content_document`, read-only `media`, and transport metadata `ETag`
- editor content write models must contain only `lesson_id` and
  `content_document`
- editor content writes must carry the required `If-Match` transport metadata

## 12. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

Current repository drift does not alter this contract.

Known drift includes:

- mounted mixed lesson write routes that still accept structure and content together
- mounted studio lesson list reads that still return `content_markdown`
- duplicate `GET /studio/courses` route definitions
- backend and frontend mixed lesson models that still combine `lesson_title`, `position`, and `content_markdown`
- frontend tests and fixtures that still reference legacy lesson fields such as `title` and `is_intro`
- frontend save logic that serializes Markdown before the write boundary
- backend Markdown normalization and Flutter round-trip validation utilities
  existing in the current legacy content path

These are drift only.
They are not contract truth.
They must be replaced, collapsed, isolated, or removed during implementation alignment.

## 13. FINAL ASSERTION

This contract is complete, deterministic, and lockable.

It is valid only if all future implementation preserves these laws:

- course structure and lesson structure remain separate from lesson content
- `lesson_document_v1` remains the canonical rebuilt-editor lesson-content
  format
- backend document validation and canonical JSON serialization remain the only
  rebuilt-editor content authority at the write boundary
- legacy aliases and mixed surfaces do not survive as contract truth

This contract is ready to govern deterministic task-tree construction for implementation.
