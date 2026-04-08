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
- `step`
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

## 4. CANONICAL ENTRYPOINTS

### Editor Structure Reads

- `GET /studio/courses`
- `GET /studio/courses/{course_id}`
- `GET /studio/courses/{course_id}/lessons`

### Editor Structure Writes

- `POST /studio/courses`
- `PATCH /studio/courses/{course_id}`
- `DELETE /studio/courses/{course_id}`
- `POST /studio/courses/{course_id}/lessons`
- `PATCH /studio/lessons/{lesson_id}/structure`
- `PATCH /studio/courses/{course_id}/lessons/reorder`
- `DELETE /studio/lessons/{lesson_id}`

### Editor Content Write

- `PATCH /studio/lessons/{lesson_id}/content`

No mixed `POST /studio/lessons` or mixed `PATCH /studio/lessons/{lesson_id}` endpoint survives as canonical truth.

## 5. STRUCTURE WRITE CONTRACTS

### 5.1 Course Create

Endpoint:

`POST /studio/courses`

Request:

~~~json
{
  "title": "string",
  "slug": "string",
  "course_group_id": "uuid",
  "step": "intro | step1 | step2 | step3",
  "price_amount_cents": 123,
  "drip_enabled": true,
  "drip_interval_days": 7,
  "cover_media_id": "uuid"
}
~~~

Response:

~~~json
{
  "id": "uuid",
  "slug": "string",
  "title": "string",
  "course_group_id": "uuid",
  "step": "intro | step1 | step2 | step3",
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
- `cover` is a backend-authored read field, not a write authority
- `short_description` is forbidden in this request
- lesson fields are forbidden in this request

### 5.2 Course Update

Endpoint:

`PATCH /studio/courses/{course_id}`

Request:

~~~json
{
  "title": "string",
  "slug": "string",
  "course_group_id": "uuid",
  "step": "intro | step1 | step2 | step3",
  "price_amount_cents": 123,
  "drip_enabled": true,
  "drip_interval_days": 7,
  "cover_media_id": "uuid"
}
~~~

Response:

Same canonical course structure response as course create.

Rules:

- request is partial
- mutates course structure only
- `short_description` is forbidden
- lesson fields are forbidden
- `content_markdown` is forbidden

### 5.3 Course Delete

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

### 5.4 Lesson Create

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

### 5.5 Lesson Structure Update

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

### 5.6 Lesson Reorder

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

### 5.7 Lesson Delete

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

Response:

~~~json
{
  "lesson_id": "uuid",
  "content_markdown": "string"
}
~~~

Rules:

- `content_markdown` is the only request field
- request meaning is singular and non-branching
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
      "step": "intro | step1 | step2 | step3",
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
- `GET /studio/courses` must exist exactly once
- `GET /studio/courses/{course_id}/lessons` is structure-only and must not leak content

## 8. PUBLIC SURFACE POINTER

Public course and lesson read semantics are defined only by `course_public_surface_contract.md`.

This contract defines no public response semantics, public field meaning, visibility rules, or learner-visible projection rules.

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
- `lesson_title` in the content endpoint
- `position` in the content endpoint
- `title` as lesson runtime alias
- `is_intro` as lesson authority
- duplicate `GET /studio/courses`
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
- `DELETE /studio/courses/{course_id}`
- `POST /studio/courses/{course_id}/lessons`
- `PATCH /studio/lessons/{lesson_id}/structure`
- `PATCH /studio/courses/{course_id}/lessons/reorder`
- `DELETE /studio/lessons/{lesson_id}`

Editor frontend may use only this canonical content write surface:

- `PATCH /studio/lessons/{lesson_id}/content`

Frontend model separation law:

- editor structure models must not contain `content_markdown`
- editor content write models must contain only `lesson_id` and `content_markdown`

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
