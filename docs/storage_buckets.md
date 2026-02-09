# Storage Buckets & Media Policy

AVELI uses Supabase Storage plus the FastAPI media service to keep course files and profile assets consistent across platforms. This document summarizes every bucket, who can access it, and how signed URLs / caching behave.

## Bucket matrix

| Bucket | Visibility | Purpose | Served via |
| --- | --- | --- | --- |
| `public-media` | Public | Truly public assets (covers/hero/logos) and optionally intro lesson media. | Supabase public URL (CDN). Local dev fallback: `/api/files/<path>`. |
| `course-media` | Private | Lesson media + WAV sources that require access control. | Signed tokens (`/media/stream/<token>`) or Supabase presigns issued server-side. |

- Intro lessons may upload to `public-media` for CDN-servning, but draft/non-intro uploads should remain in `course-media`.
- Private lesson media should never receive a stable public URL; clients must use signed tokens.
- Profile/hero/logo uploads continue to use dedicated folders under `public-media/` (e.g. `public-media/avatars/<user_id>/avatar.png`).

## Upload routing

| Endpoint | Bucket | Notes |
| --- | --- | --- |
| `POST /api/upload/profile` | `public-media` (under `users/` + user id) | Image-only; response includes a stable public URL for the uploaded image. |
| `POST /studio/lessons/{lesson_id}/media/presign` + `POST /studio/lessons/{lesson_id}/media/complete` | `course-media` or `public-media` | Canonical lesson media upload flow (direct-to-Supabase). Backend chooses bucket + path. |
| `POST /api/upload/course-media` | legacy/dev | Writes to backend disk and is not production-safe (disabled unless `MEDIA_ALLOW_LEGACY_MEDIA=true`). |

`app.media_objects.storage_bucket` now mirrors the physical bucket (`public-media` or `course-media`). Any code that consumes media rows can rely on this column to determine whether a signed URL is required.

## Signed downloads

- When `MEDIA_SIGNING_SECRET` is configured, every private media row gets a signed link via `media_signer.issue_signed_url` with TTL `MEDIA_SIGNING_TTL_SECONDS`.
- `/media/stream/<token>` verifies the token, enforces `Cache-Control: private, max-age=<TTL>` and `Content-Disposition: inline; filename="…"`, and supports HTTP range requests for audio/video scrubbing.
- If signing is disabled for local dev, `MEDIA_ALLOW_LEGACY_MEDIA=true` re-exposes the legacy `/studio/media/{media_id}` path so the Flutter app keeps working.

## Storage buckets in Supabase

Migration `supabase/migrations/018_storage_buckets.sql` seeds the storage buckets directly in Postgres:

```sql
insert into storage.buckets (id, name, public) values ('public-media', 'public-media', true);
insert into storage.buckets (id, name, public) values ('course-media', 'course-media', false);
insert into storage.buckets (id, name, public) values ('lesson-media', 'lesson-media', false);
```

Re-run the migration or execute the SQL snippet on any environment where storage is empty (the statements are idempotent). You can verify the current state via:

```bash
psql "$DATABASE_URL" -c "select id, public from storage.buckets order by id;"
```

This ensures every environment (local, staging, prod) agrees on which buckets exist and how uploads/signatures should be routed.
