# Direct Uploads via Supabase Signed URLs

## Flöde
1. Klienten begär `POST /studio/lessons/:lesson_id/media/presign` med `filename`, `content_type`, `media_type` (image/audio/video/document) och ev. `is_intro`.
2. FastAPI svarar med Supabase-signerad PUT-URL + headers (`x-upsert`, `cache-control`, `content-type`) samt `storage_path`/`storage_bucket`.
3. Klienten laddar upp filen direkt till Supabase Storage via URL:en utan att proxas via backend (Flutter → `MediaService.uploadWithPresignedTarget`, Next.js → `uploadWithPresignedUrl`).
4. När uppladdningen är klar anropas `POST /studio/lessons/:lesson_id/media/complete` med `storage_path`, `storage_bucket`, `content_type`, `byte_size` och `original_name` så att `app.lesson_media` uppdateras.

## Kontrakt (bucket + path)
- Bucket styrs av backend:
  - Default: `course-media` (privat).
  - Intro-lektioner kan routas till `public-media` (publik) för CDN-servning.
- `storage_path` är alltid bucket-relativ (ingen bucket-prefix i nyckeln).
- Nyckelformat:
  - `courses/<course_id>/lessons/<lesson_id>/<media_type>/<uuid>_<filename>`
- WAV (`audio/wav`, `.wav`) stöds inte här och måste gå via WAV-ingest (`POST /api/media/upload-url`).

## Klientkrav
- Alla PUT-anrop måste inkludera headers från `/studio/lessons/:lesson_id/media/presign`, särskilt `x-upsert` och `content-type`.
- TTL för uppladdningar är 2 timmar; begär ny presign när popup öppnas.
- Logga `storage_path` och associera med lektion/ägare via RPC efter lyckad uppladdning.

## CLI-hjälp
`scripts/presign_upload.py --bucket course-media --path courses/demo/lesson-1.wav --content-type audio/wav`
returnerar en signerad PUT-URL + headers direkt från Supabase Storage. Perfekt för att verifiera
att service role-nycklar och bucketpolicys fungerar innan Flutter/webb-klienterna integreras.
