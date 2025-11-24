# Media Architecture

## Nuvarande publika bucket
- `public` bucket innehåller historiska kursvideor som exponeras via okrypterade URL:er.
- Signering saknas → alla med URL kan se innehållet.
- Ingen Content-Disposition → filer namnges slumpmässigt vid nedladdning.

## Privat bucket `lesson_media`
- Ny bucket `lesson_media` skapas i Supabase Storage och markeras som privat.
- Alla nya uppladdningar (lektioner, övningar, profilvideor) ska använda `lesson_media`.
- RLS-policy krävs: lärare/admin har read/write, autentiserade elever read, anonyma none.

## Signerade URL:er
- Backend genererar URL:er med `StorageService.get_presigned_url(path, ttl, filename)`.
- Tidsgräns (TTL) styrs per begäran, standard 10 minuter via `media_signing_ttl_seconds`.
- URL:en kompletteras med `download`-param och `Content-Disposition`-header (`inline`).
- Flutter-klienten hämtar först presigned URL från `/media/presign`, därefter laddas media direkt från Supabase CDN.

## Content-Disposition
- Namn tas från filens metadata eller `filename` i API-anropet.
- Headern byggs via `build_content_disposition` för RFC 6266-stöd.
- Tester i `backend/tests/test_storage_service.py` verifierar att headern genereras korrekt.
