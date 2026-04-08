# Media Forensic Report (Course Images + Storage) - 2026-01-23

Scope: Course image storage and rendering across Flutter web + backend + Supabase Storage. Assumption: media is already broken and any image you see may be a fallback.

Evidence sources (non-exhaustive):
- `backend/app/routes/api_media.py`
- `backend/app/services/media_transcode_worker.py`
- `backend/app/utils/media_signer.py`
- `backend/app/routes/upload.py`
- `backend/app/routes/studio.py`
- `backend/app/services/storage_service.py`
- `backend/app/utils/profile_media.py`
- `frontend/lib/features/studio/widgets/cover_upload_card.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/shared/utils/course_cover_assets.dart`
- `frontend/lib/shared/widgets/courses_grid.dart`
- `frontend/lib/features/home/presentation/home_dashboard_page.dart`
- `frontend/lib/shared/widgets/app_network_image.dart`
- `supabase/migrations/001_app_schema.sql`
- `supabase/migrations/018_storage_buckets.sql`
- `supabase/migrations/20260102113600_storage_public_media.sql`
- `supabase/migrations/20260118182912_remote_schema.sql`
- `docs/media_pipeline.md`
- `docs/storage_buckets.md`
- `docs/direct_uploads.md`
- `docs/media_architecture.md`
- `docs/verify/LAUNCH_READINESS_REPORT.md`
- `docs/image_inventory.md`

---

## 1) Supabase bucket inventory (with responsibilities)

| Bucket | Intended purpose | Who writes | Who reads | Used by | Notes / faults |
| --- | --- | --- | --- | --- | --- |
| `public-media` | Public assets (course intros, course cover derivatives, marketing/hero/logo) | Worker uploads derived covers via service role (`media_transcode_worker`) | Public clients via public URL | Course cover pipeline (`media_transcode_worker`), public asset URLs | **Critical: mixed responsibilities.** Also `/api/files` serves local disk, not Supabase. `LAUNCH_READINESS_REPORT.md` shows `public-media` flagged as `public=false` in remote DB, which would break all public reads. |
| `course-media` | Private course media + WAV sources | Signed upload URLs from backend (`/api/media/upload-url`, `/api/media/cover-upload-url`), test presign in `/studio/lessons/.../media/presign` | Signed URLs for playback + worker downloads | WAV ingest pipeline, cover source storage | Path conventions inconsistent: some code stores paths with bucket prefix (e.g. `course-media/...`). |
| `lesson-media` | Legacy/DB default bucket for lesson media | Legacy defaults in DB (`app.lesson_media.storage_bucket` default), not current pipeline | Signed/private reads (policy snapshot) | Legacy lesson media and media_objects defaults | **Fault:** still default in schema but not the configured source bucket; causes mismatched bucket routing. |
| `audio_private` | Unknown (policy snapshot only) | Unknown | Unknown | Referenced in storage policies only | Appears in `20260118182912_remote_schema.sql` and `LAUNCH_READINESS_REPORT.md`, but not referenced in app config. |
| `welcome-cards` | Welcome card assets (policy snapshot only) | Unknown | Unknown | Referenced in storage policies only | Not referenced in backend code in this repo. |
| `avatars` | Public avatar assets (policy snapshot only) | Unknown | Public read (policy) | Referenced in storage policies | App currently stores avatars on backend disk with `storage_bucket = profile-avatars` (not Supabase). |
| `thumbnails` | Public thumbnails (policy snapshot only) | Unknown | Public read (policy) | Referenced in storage policies | Not referenced in backend code. |
| `brand` | Unknown (remote DB verify output) | Unknown | Unknown | Listed in `LAUNCH_READINESS_REPORT.md` | Not in migrations or code. |

Additional legacy names used in docs/tests (not in current bucket config): `public`, `lesson_media`, `media`. These mismatches are a systemic risk.

---

## 2) Course image lifecycle (end-to-end)

### 2.1 Frontend (selection + bucket/path decision)

**Cover upload (new pipeline):**
- `CoverUploadCard` uses `MediaPipelineRepository.requestCoverUploadUrl(...)` and then uploads the file via a single PUT (`cover_upload_source_web.dart`).
- Bucket and path are decided by the backend; frontend does not set bucket or storage path.
- Status polling uses `/api/media/{media_id}` and expects `courses.cover_url` to update when ready.

**Cover from existing lesson media:**
- `course_editor_page.dart` allows selecting a lesson media item; it calls `/api/media/cover-from-media`.
- UI preview uses `storage_path` or `media['url']` and has a fallback to a constructed public download path even if `storage_bucket` is missing (`_publicDownloadPathForMedia`).
- Implicit defaults: if `storage_bucket` is null, it infers bucket from the path prefix, and assumes public buckets if the prefix matches.

### 2.2 Backend (DB rows + atomicity)

**/api/media/cover-upload-url** (`api_media.py`):
- Creates a `media_assets` row *before* upload (state = `uploaded`).
- Generates a signed Supabase upload URL using `storage_service.storage_service` (bucket defaults to `media_source_bucket`, i.e. `course-media`).
- Not atomic with upload; if upload fails, the DB row remains and no cover is applied.

**/api/media/cover-from-media** (`api_media.py`):
- Builds a `media_assets` row from an existing lesson media row.
- Uses `storage_bucket` from the lesson media row, falling back to `settings.media_source_bucket` when missing.
- Does not verify that a Supabase object exists at that path.

**Processing** (`media_transcode_worker.py`):
- Downloads the source object via signed URL from the source bucket.
- Transcodes to JPEG, uploads to `public-media`, and computes a public URL.
- Updates `courses.cover_url` and `courses.cover_media_id` only when the new asset is the latest cover.
- If download fails (missing Supabase object or wrong bucket/path), state becomes `failed`, and `cover_url` is not updated.

### 2.3 Supabase Storage (objects + policies)

Expected object paths:
- Source: `media/source/cover/courses/<course_id>/<token>_<filename>` in `course-media`.
- Derived: `media/derived/cover/courses/<course_id>/<token>_<filename>.jpg` in `public-media`.

Observed risks:
- Legacy uploads store paths that include bucket names (ex: `course-media/...`), which diverge from Supabase bucket-relative conventions.
- If the bucket flag for `public-media` is not public (see `LAUNCH_READINESS_REPORT.md`), public cover URLs will 403.
- `storage.objects` policies are not tracked in migrations; remote schema shows policies for some buckets, but not for `public-media`.

### 2.4 UI rendering (cover_url handling + fallbacks)

- `media_signer.attach_cover_links` removes any `cover_url` not explicitly recognized as public (`/api/files/public-media/...` or Supabase public URL for the configured bucket). Legacy `/studio/media/...` values are nulled.
- Frontends treat `cover_url == null` as "no cover" and fall back to local assets or background imagery.
- Network errors (404/403) are usually swallowed and replaced by gradients or empty widgets.

---

## 3) Root causes of disappearing course images

1) **Legacy `cover_url` formats are stripped by the backend.**
   - `attach_cover_links` sets `cover_url = null` for any non-public URL, including legacy `/studio/media/{id}` and `/api/files/...` paths that do not match `/api/files/public-media/...`.
   - Result: UI sees null and shows fallback backgrounds, making the cover appear to "disappear".

2) **Mixed storage backends (local disk vs Supabase) break the cover pipeline.**
   - Non-WAV lesson media uses `/api/upload/course-media` which writes to backend disk (`upload.py`), while cover processing expects source objects in Supabase.
   - `cover-from-media` can point the worker at a local-only path, causing download failure and leaving `cover_url` unchanged.

3) **Bucket/path naming drift and defaults cause mismatches.**
   - DB defaults still use `lesson-media`, tests/docs reference `lesson_media` or `public` buckets, while runtime config expects `course-media` + `public-media`.
   - Some paths include bucket prefixes; others are bucket-relative. This breaks URL construction and object lookup.

4) **Bucket visibility misconfiguration is documented.**
   - `LAUNCH_READINESS_REPORT.md` lists `public-media` as `public=false` in remote DB output, which would cause 403 for public cover URLs.

5) **UI fallbacks hide real failures.**
   - Course cards, grids, and home sections silently replace missing covers with gradients or the app background, masking storage errors.

---

## 4) Fallback behavior inventory (and what it hides)

| Fallback | Location | What it hides | Why dangerous | Remove or make explicit |
| --- | --- | --- | --- | --- |
| Local course cover assets by slug | `CourseCoverAssets.resolve(...)` | Missing/invalid `cover_url` or broken storage objects | Hides broken uploads and stale cover URLs | Make explicit; only allow for clearly labeled seed/demo courses |
| Gradient/placeholder cover in course grid | `CoursesGrid.buildCover()` | 404/403/network errors for cover URLs | Masks storage failures as design | Make explicit (e.g., "cover missing" overlay) |
| Background image fallback in Home explore list | `_CourseIconFallback` in `home_dashboard_page.dart` | Missing cover URL or load failures | Makes failures look intentional (app background) | Make explicit and log metrics |
| Silent image failures | `AppNetworkImage` returns `SizedBox.shrink()` on error | Unauthorized/404 media loads | Errors disappear from UI; hard to detect regressions | At minimum surface a "missing image" state |
| Legacy `/studio/media/{id}` fallback | `media_signer.attach_media_links` | Missing Supabase paths, missing public URLs | Keeps legacy flow alive, hides missing `storage.objects` | Deprecate or gate with explicit feature flag + telemetry |
| Implicit public download path | `_publicDownloadPathForMedia` in course editor | Missing `storage_bucket` and inconsistent path formats | Produces `/api/files/...` even when objects live in Supabase | Remove implicit inference; require explicit bucket/path |
| Default `storage_bucket = 'lesson-media'` | DB defaults + `profile_media.py` | Missing/unknown bucket values | Routes lookups to wrong bucket | Remove default or migrate to explicit bucket values |

---

## 5) Ownership + source of truth audit

| Media type | Source of truth (intended) | Storage bucket | DB reference | Notes / violations |
| --- | --- | --- | --- | --- |
| App background | Build-time asset `assets/images/bakgrund.png` | N/A | None | OK (single owner). |
| Course image | `app.courses.cover_url` + `app.courses.cover_media_id` (from `app.media_assets`) | `public-media` (derived), `course-media` (source) | `courses.cover_url`, `courses.cover_media_id` | **Violation:** multiple owners + legacy `/studio/media` values; frontend also uses slug-based local assets. |
| Module image | Not implemented (no schema field) | N/A | None | **Violation:** no owner; any UI usage is implicit. |
| Lesson media (images/video/audio) | `app.lesson_media` with explicit `storage_bucket` + `storage_path`, or `media_asset_id` for pipeline | `course-media` / `public-media` / `lesson-media` (legacy) | `lesson_media.storage_bucket`, `lesson_media.storage_path`, `lesson_media.media_asset_id`, `media_objects` | **Violation:** multiple storage models (media_objects vs media_assets) and bucket defaults misaligned. |
| Audio master (WAV) | `app.media_assets` row with `original_object_path` | `course-media` | `media_assets.original_object_path`, `lesson_media.media_asset_id` | OK if `media_assets` is the only source; currently coexists with legacy lesson_media paths. |

---

## 6) Supabase RLS + policy verification (from repo state)

- Buckets are created by migrations (`018_storage_buckets.sql`, `20260102113600_storage_public_media.sql`).
- Storage policies are **not tracked** in migrations. The only explicit policy definitions are in the remote schema snapshot (`20260118182912_remote_schema.sql`) and the launch report.
- Remote schema policies include:
  - `storage_owner_private_rw` (ALL) and `storage_signed_private_read` (SELECT) for `course-media`, `lesson-media`, `audio_private`, `welcome-cards`.
  - `storage_public_read_avatars_thumbnails` (SELECT) for `avatars` and `thumbnails`.
  - `storage_service_role_full_access` (ALL).
- There is **no policy** for `public-media` in the snapshot; public read relies on the bucket `public` flag.
- `LAUNCH_READINESS_REPORT.md` shows `public-media` marked `public=false` and calls this out as a bucket sanity failure.

Implications:
- If `public-media` is not truly public, every cover URL will fail even if the object exists.
- Because policies are not versioned in migrations, environments may drift silently.
- Frontend reads should not depend on service role. Today, any `/api/files/...` or `/studio/media/...` path is a backend-disk path, not Supabase, and bypasses storage policies entirely.

---

## 7) Exact failure points (where media breaks)

1) **Legacy cover_url values** -> `media_signer.attach_cover_links` -> `cover_url` nulled -> UI fallback.
2) **Cover-from-media using local lesson uploads** -> worker fetch from Supabase fails -> `media_assets.state = failed` -> `cover_url` not updated.
3) **Bucket mismatch or missing `storage.objects` row** -> signed URL download 404 -> worker fails -> cover missing.
4) **Bucket visibility mismatch (`public-media` not public)** -> public URL 403 -> image load fails -> fallback.
5) **`/api/files` paths in production** -> backend expects local disk -> 404 -> fallback.

---

## 8) Media architecture truth (rules, not code)

1) A course cover is valid only if:
   - A `storage.objects` row exists in `public-media` for the derived image path, and
   - `courses.cover_url` points to the Supabase public URL for that object, and
   - `courses.cover_media_id` references the latest `media_assets` row for that course.

2) A lesson media item is valid only if:
   - `lesson_media.storage_bucket` is explicit and matches a real Supabase bucket, and
   - `lesson_media.storage_path` is bucket-relative (no bucket prefix), and
   - the corresponding `storage.objects` row exists.

3) WAV ingest source of truth is `app.media_assets` (original object path + bucket). `lesson_media.media_asset_id` must be the only linkage; raw WAV paths should not be used for playback.

4) Public assets must be served from Supabase public URLs; `/api/files` and `/studio/media` are legacy and must not be used in production responses.

5) Bucket names must be consistent across code, migrations, and docs. Any bucket name not present in migrations is treated as unsupported.

---

## 9) Summary (Phase 1 conclusion)

- The current system mixes legacy local-disk media with Supabase Storage. This breaks the cover pipeline and makes `cover_url` unreliable.
- Backend filtering (`attach_cover_links`) nulls legacy cover URLs, causing silent fallbacks in the UI.
- Bucket naming drift (`lesson-media` vs `lesson_media` vs `public`) and path conventions (bucket-prefixed vs bucket-relative) lead to missing `storage.objects` rows and failed downloads.
- Bucket visibility and policy drift is documented in `LAUNCH_READINESS_REPORT.md`, which indicates `public-media` is not public.

Phase 1 is complete with this report. No implementation changes have been made.
