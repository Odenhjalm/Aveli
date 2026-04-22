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
- markdown is the canonical lesson-content format
- backend normalization is the only content authority at the write boundary

The canonical domain flow is:

~~~text
course structure write -> app.courses
lesson structure write -> app.lessons
lesson content write -> backend markdown normalization -> app.lesson_contents
~~~

No runtime code, legacy route, or active fallback may override this contract.

## 2. AUTHORITY MODEL

Canonical authorities are:

- course identity authority: `app.courses`
- course structure authority: `app.courses`
- course cover identity authority: `app.courses.cover_media_id`
- lesson identity authority: `app.lessons`
- lesson ordering authority: `app.lessons.position`
- lesson structure authority: `app.lessons`
- lesson content authority: `app.lesson_contents`
- markdown/text content authority: `app.lesson_contents.content_markdown`

Forbidden as authority:

- `StudioLesson` mixed payloads
- editor Quill Delta
- frontend-normalized markdown
- frontend preview markdown
- frontend cover preview state
- frontend-reconstructed cover URLs
- raw joined studio lesson lists that include `content_markdown`
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
- `drip_enabled`
- `drip_interval_days`

Lesson structure contains only:

- `id`
- `course_id`
- `lesson_title`
- `position`

Lesson content contains only:

- `content_markdown`

Canonical separation rules:

- `app.lessons` remains structure-only
- `app.lesson_contents` remains content-only
- `content_markdown` must never appear on a structure-only write endpoint
- `lesson_title` and `position` must never appear on a content-only write endpoint

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

~~~json
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
~~~

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
  "drip_enabled": true,
  "drip_interval_days": 7,
  "cover_media_id": "uuid | null"
}
~~~

Response:

Same canonical course structure response as course create.

Rules:

- request is partial
- mutates course metadata only
- `cover_media_id` assigns cover identity when non-null
- `cover_media_id: null` clears the cover identity
- omitted `cover_media_id` means no cover change
- `cover` is a backend-authored read field, not a write authority
- `course_group_id` is forbidden in this request
- `group_position` is forbidden in this request
- `short_description` is forbidden
- lesson fields are forbidden
- `content_markdown` is forbidden

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
  "content_markdown": "string",
  "media": []
}
~~~

Response transport metadata:

- `ETag`

Rules:

- reads existing persisted content from `app.lesson_contents.content_markdown`
- `lesson_id` identifies the lesson whose content was read
- `content_markdown` is backend-authored persisted markdown
- `media` is a read-only backend-authored list of governed media objects when applicable, otherwise an empty list
- response must not include lesson structure fields such as `lesson_title` or `position`
- response must not include course structure payload
- response must not expose storage paths, signed URLs, upload URLs, frontend-resolved URLs, or raw media resolver fields
- the `ETag` transport metadata is the canonical editor content concurrency token
- this endpoint must not mutate lesson structure or lesson content
- structure endpoints must not expose `content_markdown`, content media, or content concurrency tokens

## 6. CONTENT WRITE CONTRACT

Endpoint:

`PATCH /studio/lessons/{lesson_id}/content`

Responsibility:

- mutate lesson content only

Request:

~~~json
{
  "content_markdown": "string"
}
~~~

Required request transport metadata:

- `If-Match`

Response:

~~~json
{
  "lesson_id": "uuid",
  "content_markdown": "string"
}
~~~

Response transport metadata:

- `ETag`

Rules:

- `content_markdown` is the only request field
- request meaning is singular and non-branching
- `If-Match` must contain the current backend-issued content concurrency token
- writes without a matching `If-Match` token must fail without persistence
- successful writes must emit a replacement `ETag`
- backend must normalize markdown before persistence
- persisted content is the backend-normalized result
- response must return the backend-normalized markdown
- `lesson_title` is forbidden
- `position` is forbidden
- `course_id` is forbidden
- no structure fields may appear

Validation law:

- invalid canonical media references must be rejected
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

- editor structure reads must not expose `content_markdown`
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

Draft preview is not allowed as Preview Mode authority.

Preview Mode must be persisted-only unless a later contract explicitly defines a separate non-authoritative draft view with a distinct name and boundary.

A new backend mutation surface for Preview Mode is forbidden.

A new backend read surface is not required for authority if existing canonical read surfaces can compose persisted lesson text, lesson media, and course cover. Any future Preview helper surface must remain read-only projection only.

## 9. MARKDOWN / TEXT EDITOR LAW

Markdown law:

- markdown is the canonical lesson-content format
- `content_markdown` is canonical only on `app.lesson_contents`
- backend normalization is the only write-boundary authority
- frontend normalization is convenience only and never authority
- editor-internal rich text state is transient only
- Quill Delta or any other editor document model must never be stored as contract truth

Canonical media-reference law inside markdown:

- lesson media references must use typed lesson-media tokens only
- canonical forms are:
  - `!image(<lesson_media_id>)`
  - `!audio(<lesson_media_id>)`
  - `!video(<lesson_media_id>)`
  - `!document(<lesson_media_id>)`

Forbidden markdown persistence:

- raw HTML media tags
- raw markdown image URLs for governed lesson media
- raw document links to internal media paths
- storage-path references
- guessed playback URLs
- frontend-authored resolved media URLs

Write-boundary law:

- backend must normalize or reject incoming markdown
- backend output is the persisted truth
- content write responses must reflect backend-normalized markdown

## 10. FORBIDDEN PATTERNS

The following are forbidden:

- `POST /studio/lessons` as canonical truth
- mixed `PATCH /studio/lessons/{lesson_id}` as canonical truth
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

- editor structure models must not contain `content_markdown`
- editor structure models must not contain content media or content concurrency tokens
- editor content read models may contain only `lesson_id`, `content_markdown`, read-only `media`, and transport metadata `ETag`
- editor content write models must contain only `lesson_id` and `content_markdown`
- editor content writes must carry the required `If-Match` transport metadata

## 12. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

Current repository drift does not alter this contract.

Known drift includes:

- mounted mixed lesson write routes that still accept structure and content together
- mounted studio lesson list reads that still return `content_markdown`
- duplicate `GET /studio/courses` route definitions
- backend and frontend mixed lesson models that still combine `lesson_title`, `position`, and `content_markdown`
- frontend tests and fixtures that still reference legacy lesson fields such as `title` and `is_intro`
- frontend save logic that serializes markdown before the write boundary
- backend markdown normalization utility existing without being the sole enforced mounted write-boundary authority yet

These are drift only.
They are not contract truth.
They must be replaced, collapsed, isolated, or removed during implementation alignment.

## 13. FINAL ASSERTION

This contract is complete, deterministic, and lockable.

It is valid only if all future implementation preserves these laws:

- course structure and lesson structure remain separate from lesson content
- markdown remains the canonical lesson-content format
- backend normalization remains the only content authority at the write boundary
- legacy aliases and mixed surfaces do not survive as contract truth

This contract is ready to govern deterministic task-tree construction for implementation.
