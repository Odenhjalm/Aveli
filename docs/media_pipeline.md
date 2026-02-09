# WAV ingest + playback pipeline

This pipeline ingests WAV studio masters, transcodes them server-side, and
serves only compressed audio to end users. The backend is a control plane plus
background processing; it never proxies large media to clients.

## Storage layout

- Source uploads (WAV): `media/source/audio/...`
- Derived streaming assets (MP3): `media/derived/audio/...`

Both live in the Supabase Storage bucket configured in the backend (default:
`course-media`). CDN delivery is enabled in Supabase Storage.

## Lifecycle states

Media assets move through these states (stored in `app.media_assets.state`):

- `uploaded` — WAV uploaded, awaiting processing
- `processing` — ffmpeg transcode running
- `ready` — MP3 available for streaming
- `failed` — transcode error (recoverable)

State is exposed to the frontend via lesson media payloads and the
`GET /api/media/{media_id}` status endpoint.

## API overview

### Upload URL (teachers only)

`POST /api/media/upload-url`

Creates a media asset record in `app.media_assets`, issues a signed upload URL,
and (when a lesson is supplied) attaches a `lesson_media` entry that references
`media_asset_id` instead of a direct storage path.

Only WAV is allowed:

- `audio/wav`
- `audio/x-wav`

### Playback URL

`POST /api/media/playback-url`

Returns a signed URL for the derived MP3 only. Requests are rejected until the
asset reaches `ready`. WAV source paths are never exposed.

### Status

`GET /api/media/{media_id}`

Returns the current state plus processing metadata (codec, duration, etc.).

## Background worker

`app.services.media_transcode_worker` polls `app.media_assets` and performs:

1. Download WAV from storage (streamed to disk).
2. Transcode via ffmpeg to MP3 at 192 kbps (libmp3lame).
3. Upload derived asset to `media/derived/audio/...`.
4. Update DB record (`streaming_object_path`, `duration_seconds`, `codec`, `state`).

The worker uses backoff on failures and releases stale locks on startup.

## Frontend behavior

- Teachers upload WAVs via the Studio WAV card.
- The UI warns about long processing time and polls until ready/failed.
- Students request playback URLs for `media_asset_id` and stream MP3 via
  the HTML5 audio element (range requests enabled by CDN).

## Course cover images

Course covers follow the same ingest -> processing -> ready invariant as WAV audio.

Storage layout:

- Source uploads (images): `media/source/cover/courses/<course_id>/...`
- Derived public assets (JPEG): `media/derived/cover/courses/<course_id>/...`

The derived assets are written to the public bucket configured in the backend
(default: `public-media`).

API:

- `POST /api/media/cover-upload-url` issues a signed upload URL for the source
  image (JPG/PNG/WebP).
- `POST /api/media/cover-from-media` queues a cover from existing lesson media.
- `POST /api/media/cover-clear` clears the canonical cover for a course.

Processing:

- The worker downloads the source image, transcodes to JPEG via ffmpeg, uploads
  to the public bucket, and updates `media_assets` + `courses.cover_url` only
  when ready.
- The UI only renders `cover_url` when the asset is ready; no signed URLs are
  used for cover rendering.

## Lesson editor video blocks

Lesson videos are rendered as standalone block content in both Studio editor
and lesson playback views.

- Quill video embeds (`BlockEmbed.video`) and legacy `<video ...></video>`
  markdown are both supported.
- Rendering uses `LessonVideoBlock` + `InlineVideoPlayer` (same player as
  Home) for consistent controls, loading states, and activation behavior.
- Pointer interaction is direct: click/tap on the video surface toggles
  play/pause/resume (same behavior as Home).
- Video blocks are constrained by responsive layout breakpoints (not text-size
  scaling), so they fill available editor content width while preserving media
  aspect ratio.
- Editor/player semantics are exposed via Flutter `Semantics` labels/hints so
  keyboard users can activate playback with the play control.
