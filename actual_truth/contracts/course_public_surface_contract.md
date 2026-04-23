# COURSE PUBLIC SURFACE CONTRACT

## STATUS

ACTIVE

This contract materializes the canonical, deterministic Course + Lesson public surface domain.
It encodes already-ratified decisions only.
Cross-domain separation doctrine is defined only by `SYSTEM_LAWS.md`.
Implementation drift does not alter this contract.

## 1. CONTRACT LAW

The Course + Lesson public surface domain is governed by the following laws:

The canonical domain flow is:

~~~text
learner structure read -> public structure surfaces -> API response
learner content read -> lesson_content_surface -> API response
frontend render -> backend-provided truth only
~~~

## 2. AUTHORITY MODEL

Canonical authorities are:

- learner structure read authority: `app.course_detail_surface`
- learner content read authority: `app.lesson_content_surface`
- lesson media representation authority inside lesson content: backend read composition, subordinate to the media pipeline contract

Sibling authority outside core structure/content:

- `app.course_public_content.short_description` is not course structure
- `app.course_public_content.short_description` is not lesson content
- it remains a sibling public-content surface

Forbidden as authority:

- `LessonSummary` as content authority

## 3. PUBLIC STRUCTURE AND CONTENT VISIBILITY

Lesson content read context may additionally include:

- lesson identity
- lesson structure
- lesson media

`short_description` is sibling public content and must not be treated as course structure or lesson content.

## 4. CANONICAL ENTRYPOINTS

### Learner Structure Reads

- `GET /courses`
- `GET /courses/{course_id}`
- `GET /courses/by-slug/{slug}`

### Learner Content Read

- `GET /courses/lessons/{lesson_id}`

### Sibling Public-Content Surface Outside Core Structure/Content

- `POST /studio/courses/{course_id}/public`
- `GET /courses/{course_id}/public`

## 5. STRUCTURE READ CONTRACT

### 5.1 Learner Structure Reads

`GET /courses/{course_id}` and `GET /courses/by-slug/{slug}` response:

~~~json
{
  "course": {
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
      "state": "ready",
      "resolved_url": "string"
    },
    "price_amount_cents": 123,
    "drip_enabled": true,
    "drip_interval_days": 7
  },
  "lessons": [
    {
      "id": "uuid",
      "lesson_title": "string",
      "position": 1
    }
  ],
  "short_description": "string | null"
}
~~~

Rules:

- `lessons` is `LessonSummary[]`
- `lessons` may contain only `id`, `lesson_title`, and `position`
- `content_document` is forbidden
- legacy `content_markdown` is forbidden
- `lesson_media` is forbidden
- access does not require enrollment
- `cover` MUST be `null` when no contract-valid resolved course-cover object exists
- Placeholder cover objects with `resolved_url = null` are forbidden
- Course-cover objects may be emitted only for ready image course-cover assets with nonblank playback object path and `playback_format = jpg`
- `teacher` MUST be present and MUST be `{ user_id, display_name } | null`
- `teacher.user_id` is derived from `app.courses.teacher_id`
- `teacher.display_name` is derived from `app.profiles.display_name`
- Frontend MUST NOT infer or synthesize teacher display data
- `group_position` is the only canonical course progression field
- The legacy progression field `step` MUST NOT be emitted or consumed

## 6. CONTENT READ CONTRACT

Endpoint:

`GET /courses/lessons/{lesson_id}`

Response:

~~~json
{
  "lesson": {
    "id": "uuid",
    "course_id": "uuid",
    "lesson_title": "string",
    "position": 1,
    "content_document": {
      "schema_version": "lesson_document_v1",
      "blocks": []
    }
  },
  "course_id": "uuid",
  "lessons": [
    {
      "id": "uuid",
      "lesson_title": "string",
      "position": 1
    }
  ],
  "media": [
    {
      "id": "uuid",
      "lesson_id": "uuid",
      "media_asset_id": "uuid | null",
      "position": 1,
      "media_type": "audio | image | video | document",
      "state": "pending_upload | uploaded | processing | ready | failed",
      "media": {
        "media_id": "string",
        "state": "string",
        "resolved_url": "string | null"
      }
    }
  ]
}
~~~

Rules:

- this endpoint is the canonical `lesson_content_surface`
- it may expose lesson identity, lesson structure, lesson content, and lesson media only
- rebuilt lesson content is exposed as `content_document`
- access requires `course_enrollments` and `lesson.position <= current_unlock_position`
- `media` must use backend-authored media objects only
- structure context inside this response does not authorize structure surfaces to expose content

## 7. FORBIDDEN PATTERNS

The following are forbidden:

- structure reads that expose `content_document`
- structure reads that expose legacy `content_markdown`
- Markdown as rebuilt learner content truth

## 8. FRONTEND ALIGNMENT TARGET

Learner frontend may use only these canonical read surfaces:

- `GET /courses`
- `GET /courses/{course_id}`
- `GET /courses/by-slug/{slug}`
- `GET /courses/lessons/{lesson_id}`

Frontend model separation law:

- learner structure models must not contain `content_document`
- learner structure models must not contain legacy `content_markdown`
- learner content models may contain `content_document`
- frontend must not infer content from lesson structure lists
- frontend must not infer structure mutations from content responses
- frontend must not invent lesson semantics
- frontend must not use `title` as lesson authority
- frontend must not use `is_intro` as lesson authority

Sibling public-content rule:

- if frontend edits `short_description`, it must use the dedicated public-content surface
- `short_description` must not be sent through course structure endpoints

## 9. FINAL ASSERTION

This contract is complete, deterministic, and lockable.

It is valid only if all future implementation preserves these laws:

- no structure-read surface leaks `content_document`
- no structure-read surface leaks legacy `content_markdown`
- legacy aliases and mixed surfaces do not survive as contract truth

This contract is ready to govern deterministic task-tree construction for implementation.
