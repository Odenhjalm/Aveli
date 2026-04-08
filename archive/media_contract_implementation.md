# MEDIA CONTRACT

**Derived from Current Implementation**

---

## 1. Canonical Media Identity Model

The system operates with two persisted media identities:

### A. `app.media_objects` (Direct / Legacy Object Identity)

Represents storage-backed objects without pipeline state.

Persisted fields:

- `id`
- `owner_id`
- `storage_path`
- `storage_bucket`
- `content_type`
- `byte_size`
- `checksum`
- `original_name`
- `created_at`

Constraint:

- Unique `(storage_path, storage_bucket)`

No lifecycle state machine.

---

### B. `app.media_assets` (Pipeline / Transcoded Identity)

Represents stateful media processed through ingestion pipeline.

Persisted fields:

- `id`
- `owner_id`
- `course_id`
- `lesson_id`
- `media_type`
- `purpose`
- `original_file_name`
- `original_content_type`
- `original_byte_size`
- `storage_bucket`
- `original_object_path`
- `streaming_storage_bucket`
- `streaming_object_path`
- `ingest_format`
- `streaming_format`
- `duration_seconds`
- `codec`
- `state`
- `error_message`
- `attempt_count`
- `max_attempts`
- `next_retry_at`
- `last_error_at`
- `locked_at`
- `lock_owner`
- `created_at`
- `updated_at`
- `processed_at`

---

### C. `app.lesson_media` (Attachment Identity)

A lesson-scoped identity referencing either:

- `media_id` → `app.media_objects.id`
- `media_asset_id` → `app.media_assets.id`
- OR direct `storage_path`

Persisted fields:

- `id`
- `lesson_id`
- `kind`
- `storage_path`
- `storage_bucket`
- `media_id`
- `media_asset_id`
- `duration_seconds`
- `position`
- `created_at`

Constraint:
At least one of:

- `media_id`
- `media_asset_id`
- `storage_path`

---

## 2. Canonical Media States

State machine applies only to `app.media_assets.state`.

Allowed values:

- `uploaded`
- `processing`
- `ready`
- `failed`

Observed transitions:

| From       | To         | Trigger               |
| ---------- | ---------- | --------------------- |
| —          | uploaded   | Creation              |
| uploaded   | processing | Worker lock           |
| failed     | processing | Retry eligible        |
| processing | uploaded   | Stale lock release    |
| processing | uploaded   | Source not ready      |
| processing | ready      | Successful processing |
| processing | failed     | Processing failure    |

`app.media_objects` has no lifecycle state.

---

## 3. Storage Identity

Canonical storage identity:

```
(storage_bucket, object_key)
```

### Buckets Observed

- `course-media` (private)
- `public-media` (public)
- `lesson-media` (legacy/private default)
- `seminar-media` (legacy route usage)

---

### Audio Pipeline Key Patterns

Source:

```
media/source/audio/{resource_prefix}/{uuidhex}_{safe_filename}
```

Derived:

```
media/derived/audio/{resource_prefix}/{uuidhex}.mp3
```

---

### Cover Image Key Patterns

Source:

```
media/source/cover/courses/{course_id}/{uuidhex}_{safe_filename}
```

Derived:

```
media/derived/cover/courses/{course_id}/{uuidhex}.jpg
```

---

### Lesson Image Key Pattern

```
{uuid}.{ext} (public-media bucket)
```

---

### Direct Upload Patterns

```
home-player/{teacher_id}/{uuidhex}_{safe_filename}
lessons/{lesson_id}/{filename}
```

---

## 4. Playback Contract

### Pipeline Audio Playback (`/api/media/playback-url`)

Requirements:

- Authenticated user
- `app.media_assets` exists
- `media_type = 'audio'`
- `state = 'ready'`
- `streaming_object_path` present
- Access gate passes

Access paths depend on `purpose`:

- `lesson_audio`
- `home_player_audio`
- `course_cover`

---

### Legacy Playback (`/media/sign` + `/media/stream/{token}`)

Requirements:

- `lesson_media.id` resolvable
- Storage object exists
- Access mode gate passes

---

### Listing APIs

May include:

- `playback_url`
- `signed_url`
- `download_url`
- `signed_url_expires_at`

---

## 5. Editor Contract

Lesson insertion identity:

```
lesson_media.id
```

Embedded via:

- `data-lesson-media-id`
- `/studio/media/{id}`
- `/media/stream/{jwt}`

Mapping:

- `lesson_media.media_asset_id` → pipeline audio
- `lesson_media.media_id` → object-backed media

Deduplication logic excludes media already embedded by matching:

- `lesson_media_id`
- `/studio/media/{id}`
- decoded `/media/stream/{jwt}` subject id

---

## 6. Resolution Contract

### URL Production Mechanisms

- `POST /api/media/playback-url` → signed storage URL
- `POST /media/sign` → JWT stream URL
- `GET /media/stream/{token}` → byte-range stream

Expiration behavior:

- Storage signed URLs are time-limited
- JWT stream tokens have signer TTL
- Expiry timestamps returned explicitly
- Frontend re-signs when needed

---

### Preview vs Student Resolution

Backend resolution mode determines:

- Access gating
- Link exposure
- `preview_blocked`
- Omission of playback_url

---

## 7. Cross-Layer Invariants

- `lesson_media.id` is canonical embed identity
- `lesson_media` must satisfy schema constraint
- Pipeline playback requires:
  - `state = 'ready'`
  - valid streaming location

- `purpose` determines access semantics
- Storage resolution normalizes bucket/key forms
- Private bucket content served via signed URLs or stream tokens
- Public bucket content may be served directly
- `home_player_uploads` enforces exclusive reference:
  exactly one of `media_id` or `media_asset_id`
- Worker writes derived object paths consumed later by resolution

---

This document reflects current implementation behavior without modification, evaluation, or recommendation.

-
