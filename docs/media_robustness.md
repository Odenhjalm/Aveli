# Media Robustness (Legacy Lesson Media Compatibility + Migration Tooling)

Goal: make **legacy lesson media** reliably re-insertable in Studio and playable in student view, while keeping the stable marker contract: content persists only `/studio/media/<lesson_media_id>`.

This doc is intentionally opinionated: if an invariant is violated, treat the media as broken and surface a “re-upload required” state rather than silently rendering a placeholder.

---

## Invariants (must hold)

### 1) Stable marker contract (content)

- Persisted `content_markdown` must contain **only** `/studio/media/<lesson_media_id>` for lesson media references.
- `/media/stream/<token>` URLs are **runtime-only** (may expire) and must be normalized back to `/studio/media/<id>` before saving.
- `/api/files/*` URLs are **local-disk-only** and must never be treated as valid production playback URLs for Supabase Storage objects.
- Supabase Storage public URLs (`/storage/v1/...`) are also **runtime-only** and must never be persisted to lesson content.

### 2) Legacy lesson media (DB rows)

A legacy `lesson_media` item (i.e. `media_asset_id IS NULL`) is usable today iff:

- `app.lesson_media.id` exists (this is what the marker points at).
- It has a resolvable storage reference, either:
  - `lesson_media.media_id` → `app.media_objects.storage_bucket` + `storage_path`, OR
  - `lesson_media.storage_bucket` + `lesson_media.storage_path`.
- The `(storage_bucket, storage_path)` pair is **bucket-correct** and `storage_path` is a **bucket-relative key**:
  - no leading `/`
  - no Windows `\`
  - no redundant `bucket/` prefix inside the key
- Bytes exist:
  - Supabase: `storage.objects` contains a row for `(bucket_id = storage_bucket, name = storage_path)`, or
  - Local dev only: the file exists under `backend/media/...` or `backend/assets/uploads/...`.

### 3) New ingest pipeline audio (DB rows)

A pipeline-backed lesson media item is usable today iff:

- `lesson_media.media_asset_id` is set.
- `app.media_assets.state = 'ready'`.
- `app.media_assets.streaming_object_path` is set (bucket-relative) and points at derived audio (never the WAV source).

---

## Data model (what matters for robustness)

### Tables

- `app.lesson_media`
  - Legacy fields: `id`, `lesson_id`, `kind`, `media_id?`, `storage_bucket`, `storage_path?`, `duration_seconds?`, `position`.
  - Pipeline field: `media_asset_id?`.
- `app.media_objects` (legacy backing storage metadata)
  - `storage_bucket`, `storage_path` (historically drifted), `content_type?`, `byte_size`, `original_name?`.
- `app.media_assets` (new pipeline control plane)
  - `state`, `storage_bucket`, `original_object_path`, `streaming_object_path` (when ready), formats/codec/duration.

### Required vs optional by consumer

- **Editor insert / preview**
  - Requires: `lesson_media.id`.
  - Legacy requires: resolvable `(bucket, key)` + access to call `POST /media/sign`.
  - Pipeline audio requires: `media_asset_id` and `state=ready` for playback.
  - Optional but improves UX: `content_type`, `original_name`, `duration_seconds`.

- **Student render**
  - Same storage invariants as editor.
  - Pipeline audio strictly requires `state=ready`.

---

## Storage (buckets, paths, legacy drift)

### Buckets in active use

- Private source bucket: `course-media` (lesson uploads, WAV sources, private media).
- Public bucket: `public-media` (truly public media and derived assets like course cover derivatives).
- Legacy default bucket in schema: `lesson-media` (treat as legacy; don’t write new objects here).

### Path formats encountered (legacy)

- Bucket-prefixed keys stored inside the bucket:
  - `storage_bucket = 'course-media'`, `storage_path = 'course-media/lessons/<...>'` (**drift**).
- Bucket mismatch:
  - `storage_bucket = 'course-media'`, `storage_path = 'public-media/<...>'` (**mismatch**).
- Local disk URLs:
  - `/api/files/<bucket>/<key>` (**not Supabase**; breaks in prod).

---

## Backend pipeline (routes + behavior)

### Upload routes

- Local-disk uploads (legacy/dev): `/api/upload/*` and `/api/files/*`.
- Supabase direct upload (Studio): `POST /studio/lessons/{lesson_id}/media/presign` (bucket `course-media` or `public-media`, key `courses/{course_id}/lessons/{lesson_id}/{media_type}/{uuid}_{filename}`).

### Playback/signing routes (legacy lesson media)

- `POST /media/sign`
  - Access control: validates course ownership/public access based on lesson media.
  - Accepts `mode` for telemetry context: `editor_insert | editor_preview | student_render`.
  - Returns `signed_url = /media/stream/<jwt>`.

- `GET /media/stream/<jwt>`
  - Streams from local disk if present (dev/legacy).
  - Otherwise proxies Supabase Storage via a presigned URL.
  - Compatibility behavior:
    - Normalizes key drift by trying bucket-relative keys when `storage_path` is bucket-prefixed.
    - Tries bucket-mismatch candidates when the key prefix suggests a different bucket.

### Telemetry on failure

Migration creates:

- `app.media_resolution_failures` (event log)
  - `mode`: `editor_insert | editor_preview | student_render`
  - `reason`: `missing_object | bucket_mismatch | key_format_drift | cannot_sign | unsupported`
  - `details`: JSON (bucket/key/candidates/status/error), must not contain secrets.

- `app.lesson_media_issues` (state table)
  - Used to flag irrecoverable legacy media (e.g. bytes missing) so the UI can say “re-upload required”.

### Runtime robustness fields (API → UI)

Lesson media list items (Studio + student) now include computed robustness fields:

- `robustness_category`: `legacy_lesson_media | pipeline_media_asset | orphan | public_static`
- `robustness_status`: `ok | ok_legacy | needs_migration | missing_bytes | manual_review | unsupported | orphaned`
- `robustness_recommended_action`: `keep | auto_migrate | reupload_required | manual_review | safe_to_delete`
- `resolvable_for_editor`: boolean (insert/preview invariants)
- `resolvable_for_student`: boolean (student render invariants)

These are computed server-side using:

- Kind support (`image | video | audio | pdf`)
- Bucket/key normalization (strips legacy `/api/files/*` and Supabase URL prefixes)
- Candidate resolution for bucket/key drift and bucket mismatch
- `storage.objects` existence checks (when available)

---

## Frontend pipeline (insert/preview/student)

Single contract: content is authored/stored as `/studio/media/<lesson_media_id>`, but **rendering** resolves those markers to playable URLs at runtime.

### Where resolution happens

- Studio editor preview:
  - `prepareLessonMarkdownForRendering(..., mode: editor_preview)` replaces markers with playable URLs.
- Studio insertion flows:
  - Resolved for immediate playback, then normalized back to markers on save.
- Student view:
  - Uses the same resolution pipeline with `mode: student_render`.

### Resolver rules (security + robustness)

- Legacy lesson media should resolve via `POST /media/sign` → `/media/stream/<token>`.
- Absolute URLs are only allowed when they target the configured Supabase host and `/storage/v1/` path (downloaded without app Authorization headers).
- Arbitrary third-party media URLs are rejected by the client.

---

## Compatibility gaps (why “old media” breaks)

Concrete failure modes seen in legacy data:

1) `/api/files/*` URL stored/emitted in production
   - Root cause: `/api/files/*` serves backend disk, not Supabase Storage.
   - Symptom: editor preview works locally but breaks in prod; reinsertion fails.

2) Key-format drift (bucket-prefixed keys)
   - Root cause: `storage_path` contains `course-media/...` while also storing `storage_bucket='course-media'`.
   - Symptom: signer looks for object at the wrong key; playback 404.

3) Bucket mismatch
   - Root cause: `storage_bucket` points to bucket A but the key is under bucket B.
   - Symptom: signer checks the wrong bucket; playback 404.

4) Missing metadata
   - Root cause: `content_type`, `original_name`, or `kind` missing/incorrect.
   - Symptom: editor can’t pick correct renderer or shows placeholder.

5) Missing bytes
   - Root cause: object deleted or never existed in Supabase Storage.
   - Symptom: hard 404; must re-upload.

---

## Risk assessment (opinionated)

- `/api/files/*` in Supabase-backed flows
  - Severity: **high**
  - Impact: **editor + student**
  - Likelihood: **high** (legacy content + legacy DB rows)
  - Notes: this is the “silent break” class because it can work in dev and fail in prod.

- Key-format drift (`bucket/` inside key)
  - Severity: **high**
  - Impact: **editor + student**
  - Likelihood: **medium-high**
  - Notes: fixable via resolution normalization + DB migration.

- Bucket mismatch
  - Severity: **medium-high**
  - Impact: **editor + student**
  - Likelihood: **medium**

- Missing bytes
  - Severity: **high**
  - Impact: **editor + student**
  - Likelihood: **medium**
  - Notes: only fix is re-upload (or restoring the object from backups).

- Missing metadata
  - Severity: **medium**
  - Impact: **editor (mostly)**
  - Likelihood: **high**
  - Notes: partially fixable by backfilling from filename extensions.

---

## Migration tool: `media_doctor.py`

Path: `backend/scripts/media_doctor.py`

Dry-run (default): generates deterministic JSON + Markdown reports (no timestamps).

- Run (dry-run): `cd backend && DATABASE_URL=... poetry run python scripts/media_doctor.py`
  - Writes: `./media_robustness_report.json` + `./media_robustness_report.md`
- Run (custom output): `cd backend && DATABASE_URL=... poetry run python scripts/media_doctor.py --output-dir ./tmp/media_report`
- Print to stdout: `--json-out -` and/or `--md-out -`
- Apply (opt-in): `cd backend && DATABASE_URL=... poetry run python scripts/media_doctor.py --apply`

What it does (DB-only, no deletion):

- Normalizes bucket/key drift by stripping redundant bucket prefixes **when bytes exist** at the bucket-relative key.
- Repairs obvious bucket mismatches **when bytes exist** in the bucket implied by the key prefix.
- Backfills:
  - `media_objects.content_type` (from extension) when missing.
  - `lesson_media.kind` when empty/other and derivable.
- Flags irrecoverable items in the report (and upserts `app.lesson_media_issues` when available) when:
  - object missing in `storage.objects`, or
  - storage refs are unusable (`unsupported`).
- Flags DB-level orphans (not referenced by any known UI surface):
  - `app.media_assets` not referenced by `lesson_media`, `courses.cover_media_id`, or `home_player_uploads.media_asset_id`
  - `app.media_objects` not referenced by `lesson_media`, `profiles.avatar_media_id`, `events.image_id`, etc.

What it does not do:

- Does not move or copy storage bytes between buckets.
- Does not invent keys when no candidate exists.
- Does not delete orphan rows; it only reports them as `safe_to_delete`.

---

## Strategy options (choose deliberately)

### A) Hard reset (delete old media)

- Pros: fastest operationally; eliminates unknown legacy drift.
- Cons: breaks historical lessons; high user impact; not acceptable without backups + explicit comms.
- Effort: low engineering, high product/ops cost.
- Long-term robustness: high (because legacy is removed), but only if you prevent regression.

### B) Migration (repair metadata + normalize bucket/key)

- Pros: preserves content; reduces drift; scalable once tooling exists.
- Cons: requires careful dry-run + staged apply; cannot fix missing bytes.
- Effort: medium (tooling + ops runbooks).
- Long-term robustness: high if paired with telemetry + invariants.

### C) Compatibility layer (fallback support at resolution time)

- Pros: immediate improvement without touching data; safest first ship.
- Cons: can hide bad data unless paired with telemetry and issue surfacing.
- Effort: low-medium.
- Long-term robustness: medium unless migration eventually cleans up.

Recommended order: **C → B**, with A only as a last resort.

---

## Report examples

- `docs/examples/media_robustness_report.example.json`
- `docs/examples/media_robustness_report.example.md`

## Canary checklist (before deploy)

- Media changes MUST comply with `docs/MEDIA_CONTRACT_v1.md`.
- Old image (uploaded before fixes) can be inserted into a lesson (Studio).
- Old image renders in Studio preview.
- Old image renders in student view.
- No `/api/files/*` URLs are emitted/used for Supabase Storage-backed objects in production flows.
- Large video upload/resumable support remains out of scope for this deploy.
