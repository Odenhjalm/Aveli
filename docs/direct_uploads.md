# Direct Uploads via Supabase Signed URLs

## Flöde
1. Klienten begär `POST /studio/lessons/:lesson_id/media/presign` med `filename`, `content_type`, `media_type` (image/audio/video/document) och ev. `is_intro`.
2. FastAPI svarar med Supabase-signerad PUT-URL + headers (`x-upsert`, `cache-control`, `content-type`) samt `storage_path`/`storage_bucket`.
3. Klienten laddar upp filen direkt till Supabase Storage via URL:en utan att proxas via backend (Flutter → `MediaService.uploadWithPresignedTarget`, Next.js → `uploadWithPresignedUrl`).
4. När uppladdningen är klar anropas `POST /studio/lessons/:lesson_id/media/complete` med `storage_path`, `storage_bucket`, `content_type`, `byte_size` och `original_name` så att `app.lesson_media` uppdateras.

## Storage-policy-exempel
```sql
-- Allow teachers to upload to lesson_media using signed URLs
create policy "lesson_media_upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'lesson_media'
    and auth.role() = 'authenticated'
    and exists (
      select 1 from app.profiles p
      where p.user_id = auth.uid()
        and p.role_v2 in ('teacher', 'admin')
    )
  );

-- Allow teachers/admins to read their own uploads
create policy "lesson_media_read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'lesson_media'
    and (
      owner = auth.uid()
      or exists (
        select 1 from app.teacher_lessons tl
        where tl.lesson_media_path = storage.objects.name
          and tl.teacher_id = auth.uid()
      )
    )
  );
```

## Klientkrav
- Alla PUT-anrop måste inkludera headers från `/media/presign`, särskilt `x-upsert` och `content-type`.
- TTL för uppladdningar är 2 timmar; begär ny presign när popup öppnas.
- Logga `storage_path` och associera med lektion/ägare via RPC efter lyckad uppladdning.

## CLI-hjälp
`scripts/presign_upload.py --bucket course-media --path courses/demo/lesson-1.wav --content-type audio/wav`
returnerar en signerad PUT-URL + headers direkt från Supabase Storage. Perfekt för att verifiera
att service role-nycklar och bucketpolicys fungerar innan Flutter/webb-klienterna integreras.
