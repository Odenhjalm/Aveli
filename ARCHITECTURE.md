# Architecture

## WAV Upload Contract

- There is no replace or swap concept for WAV uploads.
- Every user-initiated upload creates a new `app.media_assets` record via `/api/media/upload-url`.
- `media_assets.state == "failed"` is terminal and represents a historical record only.
- Failed WAV assets are never resumed or reused; new user uploads always create new assets.
- Resume is a background optimization for in-flight uploads, never a user-facing action.
- Client-side `localStorage` (`aveli.wavUpload.*`) is a helper cache; the DB is the source of truth.

## Media Ingest Prerequisite (Source Object)

- Source object existence in storage is a hard prerequisite for ingest.
- Workers treat missing source objects as a wait condition and defer processing.
- Upload completion timing must never cause ingest failure.
- `processing_attempts` must not be consumed until the source object exists.
- `state = failed` is reserved for true processing errors only (after the source exists).
