# Home Player Audit For Media Control Plane

Scope: read-only architecture audit of the existing Home media player and its teacher-side Home upload control panel. No product code was changed; this document is the only new artifact.

## 1. Executive Summary

The Home player is not the same runtime path as the lesson player. Its actual runtime is a curated feed endpoint, `GET /home/audio`, that unions two explicit source types on the backend:

- `app.home_player_course_links` rows that point to `app.lesson_media`
- `app.home_player_uploads` rows that point to either `app.media_objects` or `app.media_assets`

Evidence: [home.py#L14](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/home.py#L14), [courses.py#L1213](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1213), [courses.py#L1323](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1323).

Why it likely stayed stable:

- The Home player consumes one pre-normalized backend feed instead of resolving media ad hoc in the UI.
- The feed is explicitly curated. It does not depend on lesson markdown parsing.
- The UI is intentionally audio-only and effectively mp3-only at play time, which sharply reduces the playback surface.
- Pipeline-backed items are gated on readiness before play is attempted.
- Direct teacher uploads use deterministic storage paths and dedicated library tables.
- Access is checked twice: once when assembling the feed, and again when issuing playback URLs.

Evidence: [home_dashboard_page.dart#L653](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L653), [home_dashboard_page.dart#L663](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L663), [lesson_playback_service.py#L65](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L65), [lesson_playback_service.py#L87](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L87).

How it differs from the newer Media Control Plane path:

- The lesson player now has a canonical lesson-media resolver and always goes through `POST /api/media/lesson-playback`.
- The Home player does not. It either:
  - uses `media_asset_id` and calls `POST /api/media/playback-url`, or
  - uses pre-attached legacy signed/public URLs from the feed itself.

Evidence: [lesson_media_playback_resolver.dart#L66](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/shared/utils/lesson_media_playback_resolver.dart#L66), [home_dashboard_page.dart#L818](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L818), [home_dashboard_page.dart#L843](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L843), [api_media.py#L881](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L881), [api_media.py#L899](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L899).

What this teaches the Media Control Plane:

- Preserve a single backend projection for runtime playback.
- Preserve deterministic storage identity before the frontend sees an item.
- Preserve hard readiness gating.
- Preserve simple access rules at runtime.
- Avoid adding more parallel runtime identifiers or playback APIs than necessary.

### Direct Answers

| Question | Answer |
| --- | --- |
| Canonical identity used by Home player | There is no single identity for every Home source. Linked course media uses `lesson_media.id`. Direct WAV Home uploads use `media_assets.id`. Direct MP3/MP4 Home uploads use `media_objects.id`. The library row ids in `home_player_uploads` and `home_player_course_links` are management ids, not the runtime playback ids. |
| Tables in Home flow | `app.home_player_uploads`, `app.home_player_course_links`, `app.lesson_media`, `app.media_objects`, `app.media_assets`, `app.lessons`, `app.courses`, `app.profiles`, `app.enrollments`, plus `storage.buckets` and `storage.objects` for storage behavior. |
| Does Home rely on `media_assets`, `media_objects`, or direct storage refs? | Yes, all of them, but through one normalized feed query. |
| How Home upload control panel creates records | MP3/MP4: upload to signed storage path, then create `media_objects` and `home_player_uploads`. WAV: create `media_assets` through `/api/media/upload-url`, upload source file, then create `home_player_uploads` pointing at `media_asset_id`. Course links: upsert `home_player_course_links` with `lesson_media_id`. |
| Storage path determination | Direct MP3/MP4: `home-player/{teacher_id}/{token}_{filename}` in `course-media`. WAV source: `media/source/audio/home-player/{user_id}/{filename}` in `course-media`. Derived WAV output: `media/derived/audio/home-player/{user_id}/{filename}.mp3` in `course-media`. |
| Does Home depend on processing state? | Yes for pipeline-backed audio. Course-linked asset rows are only included when `ma.state = 'ready'`. Direct Home WAV uploads are shown while processing but the play button is disabled until `ready`. |
| Processing/transcoding assumptions | Yes, but only for the WAV pipeline branch. The Home UI only attempts audio playback for mp3-compatible items. Direct MP3 uploads bypass transcoding entirely. |
| How playback URLs are built | Legacy/private items get a signed app URL `/media/stream/<jwt>` or a public URL when the object is in `public-media`. Pipeline items get a Supabase presigned playback URL from `POST /api/media/playback-url`. |
| Backend endpoint vs direct URL construction | Both. Home uses a backend playback endpoint for pipeline assets and direct pre-attached signed/public URLs for legacy items. |
| Buckets used | `course-media` for all Home-specific uploads and WAV-derived audio; linked lesson media may also resolve from `public-media` or legacy `lesson-media`. |
| Auth model | Authenticated API calls gate feed access and URL issuance. Actual media bytes are then served by either short-lived app-signed `/media/stream/<jwt>` URLs or Supabase presigned URLs. Public bucket objects bypass signing. |
| Fallback logic | Minimal. Feed items either have a playable URL or they do not. Home does not use the newer lesson resolver fallback path. |
| Main playback failure conditions | Unsupported kind/content type, pipeline asset not `ready`, missing signed/download URL, auth denial, or missing storage object/path. |
| What shows the play button | The selected item must be `kind == audio`, content type must be mp3-compatible when known, and pipeline items must be `ready`; legacy items must already have a non-empty signed or download URL. |
| Legacy vs newer coupling | Both. Home is coupled to legacy `media_objects` for direct MP3/MP4 uploads and legacy linked lesson media, and to newer `media_assets` for WAV uploads and ready pipeline-linked lesson media. |
| Does Home bypass Media Control Plane logic? | Yes. It does not use the lesson-media canonical resolver path that backs `POST /api/media/lesson-playback`; instead it uses feed-attached legacy URLs or direct `media_asset_id` playback URLs. |

## 2. System Components

### Frontend Components

- Home feed repository: `HomeAudioRepository.fetchHomeAudio()` calls `GET /home/audio`. Evidence: [home_audio_repository.dart#L107](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/data/home_audio_repository.dart#L107).
- Home screen polling and selection logic: `_syncHomeAudioPolling()` polls while any asset-backed item is not `ready`. Evidence: [home_dashboard_page.dart#L59](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L59).
- Home player control logic: `_HomeAudioListState` filters items, decides whether playback is allowed, and chooses pipeline vs legacy playback. Evidence: [home_dashboard_page.dart#L393](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L393), [home_dashboard_page.dart#L663](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L663), [home_dashboard_page.dart#L818](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L818), [home_dashboard_page.dart#L843](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L843).
- Shared playback state: `MediaPlaybackController` owns the active media id and URL. Evidence: [media_playback_controller.dart#L49](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/media/application/media_playback_controller.dart#L49).

### Teacher Upload Control Panel

- The Home library page is `StudioProfilePage`, specifically the "Media for Home" and "Linked from courses" sections. Evidence: [profile_media_page.dart#L99](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/presentation/profile_media_page.dart#L99).
- Direct upload flow entry point: `_uploadHomeMedia()`. Evidence: [profile_media_page.dart#L900](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/presentation/profile_media_page.dart#L900).
- Course-link flow entry point: `_linkFromCourses()`. Evidence: [profile_media_page.dart#L948](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/presentation/profile_media_page.dart#L948).
- Upload routing decides between WAV pipeline and direct MP3/MP4 storage uploads. Evidence: [home_player_upload_routing.dart#L22](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_routing.dart#L22).
- Upload dialog implements both branches and status polling. Evidence: [home_player_upload_dialog.dart#L18](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L18), [home_player_upload_dialog.dart#L122](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L122), [home_player_upload_dialog.dart#L323](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L323), [home_player_upload_dialog.dart#L511](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L511).

### Backend Runtime Components

- Home runtime feed endpoint: `GET /home/audio`. Evidence: [home.py#L14](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/home.py#L14).
- Feed assembly service: `courses_service.list_home_audio_media()`. Evidence: [courses_service.py#L612](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/courses_service.py#L612).
- Underlying feed query: `courses_repo.list_home_audio_media()`. Evidence: [courses.py#L1201](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1201).
- Legacy link attachment: `media_signer.attach_media_links()`. Evidence: [media_signer.py#L229](/home/rodenhjalm/Aveli-media-control-plane/backend/app/utils/media_signer.py#L229).
- Pipeline playback endpoint: `POST /api/media/playback-url`. Evidence: [api_media.py#L881](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L881).
- Lesson-player canonical endpoint, used for comparison but not by Home feed playback: `POST /api/media/lesson-playback`. Evidence: [api_media.py#L899](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L899).
- Legacy signed stream route: `POST /media/sign` plus `GET /media/stream/{token}`. Evidence: [media.py#L563](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/media.py#L563), [media.py#L577](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/media.py#L577).
- Storage proxy/streaming helper: `_build_streaming_response()`. Evidence: [media.py#L190](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/media.py#L190).

### Backend Upload/Library Components

- Home library endpoint: `GET /studio/home-player/library`. Evidence: [studio.py#L538](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L538).
- Direct MP3/MP4 upload-url issuance: `POST /studio/home-player/uploads/upload-url`. Evidence: [studio.py#L564](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L564).
- Upload-url refresh: `POST /studio/home-player/uploads/upload-url/refresh`. Evidence: [studio.py#L636](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L636).
- Home upload record creation: `POST /studio/home-player/uploads`. Evidence: [studio.py#L708](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L708).
- Course-link creation: `POST /studio/home-player/course-links`. Evidence: [studio.py#L868](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L868).
- WAV ingest upload-url issuance: `POST /api/media/upload-url` with `purpose = home_player_audio`. Evidence: [api_media.py#L307](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L307).
- Derived-audio worker: `media_transcode_worker`. Evidence: [media_transcode_worker.py#L228](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/media_transcode_worker.py#L228).

## 3. Media Identity Model

The Home player does not have one single global media identity. It has a source-specific identity model that is flattened into one feed response.

### Identity by Source Type

| Source type | Management row | Feed `id` returned by `/home/audio` | Playback key used by frontend | Backing storage owner |
| --- | --- | --- | --- | --- |
| Linked course media | `home_player_course_links.lesson_media_id` | `lesson_media.id` | `media_asset_id` when present, otherwise feed-attached signed/public URL | `lesson_media` resolves through `media_assets`, `media_objects`, or `lesson_media.storage_*` |
| Direct Home MP3/MP4 upload | `home_player_uploads.media_id` | `media_objects.id` | feed-attached signed/public URL | `media_objects` |
| Direct Home WAV upload | `home_player_uploads.media_asset_id` | `media_assets.id` | `POST /api/media/playback-url` with `media_asset_id` | `media_assets` |

Evidence for the linked branch: `lm.id` is emitted as feed `id`, and `lm.media_asset_id` is carried alongside it. Evidence: [courses.py#L1271](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1271), [courses.py#L1288](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1288).

Evidence for the direct-upload branch: the feed emits `coalesce(ma.id, mo.id) AS id`, `mo.id AS media_id`, and `ma.id AS media_asset_id`. Evidence: [courses.py#L1323](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1323), [courses.py#L1341](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1341), [courses.py#L1342](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1342).

### What This Means

- `home_player_uploads.id` and `home_player_course_links.id` are library-management ids.
- The Home runtime does not play by those ids.
- For linked course items, Home is still anchored to `lesson_media.id`.
- For direct uploads, Home is anchored to the backing byte record id, not the library row id.

This is the single biggest identity difference between Home and the lesson player. The lesson player has moved toward "lesson media as the public runtime id"; Home still mixes "lesson media id" and "byte-record id" depending on source.

### Example Code References

- Feed fetch: [home_audio_repository.dart#L112](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/data/home_audio_repository.dart#L112)
- Pipeline playback uses `mediaAssetId`: [home_dashboard_page.dart#L822](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L822)
- Legacy playback uses pre-attached URL from the feed item: [home_dashboard_page.dart#L847](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L847)

## 4. Upload Pipeline

The teacher-facing control panel actually exposes three different Home-library operations:

- direct MP3/MP4 upload
- WAV upload through the media pipeline
- link existing course media into Home

### 4.1 Direct MP3/MP4 Upload

Frontend flow:

- The teacher opens the Home library page and clicks "Ladda upp". Evidence: [profile_media_page.dart#L114](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/presentation/profile_media_page.dart#L114).
- `_uploadHomeMedia()` picks a file and classifies it via `detectHomePlayerUploadRoute()`. Evidence: [profile_media_page.dart#L900](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/presentation/profile_media_page.dart#L900), [home_player_upload_routing.dart#L22](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_routing.dart#L22).
- Non-WAV files go through `_uploadViaHomeStorage()`. Evidence: [home_player_upload_dialog.dart#L117](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L117), [home_player_upload_dialog.dart#L323](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L323).
- The dialog requests `/studio/home-player/uploads/upload-url`. Evidence: [home_player_upload_dialog.dart#L351](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L351), [studio_repository.dart#L391](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/data/studio_repository.dart#L391).

Backend flow:

- `POST /studio/home-player/uploads/upload-url` only accepts MP3 and MP4, rejects WAV, enforces size limits, and signs uploads into `course-media` under `home-player/{teacher_id}/{token}_{filename}`. Evidence: [studio.py#L577](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L577), [studio.py#L597](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L597), [studio.py#L609](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L609).
- After the browser uploads bytes directly to storage, the frontend calls `POST /studio/home-player/uploads` with `storage_bucket`, `storage_path`, `content_type`, `byte_size`, and `original_name`. Evidence: [studio_repository.dart#L423](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/data/studio_repository.dart#L423), [home_player_upload_dialog.dart#L481](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L481).
- The backend validates the path prefix, verifies the object exists, creates a `media_objects` row, then creates a `home_player_uploads` row pointing at `media_id`. Evidence: [studio.py#L744](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L744), [studio.py#L764](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L764), [studio.py#L798](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L798), [studio.py#L810](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L810).

Resulting identifiers:

- storage object path in `course-media`
- `app.media_objects.id`
- `app.home_player_uploads.id`

The Home runtime feed later uses `media_objects.id`, not `home_player_uploads.id`.

### 4.2 WAV Upload Through Media Pipeline

Frontend flow:

- WAV files are routed to `_uploadViaMediaPipeline()`. Evidence: [home_player_upload_dialog.dart#L112](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L112), [home_player_upload_dialog.dart#L122](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L122).
- The frontend requests `POST /api/media/upload-url` with `purpose = home_player_audio`. Evidence: [home_player_upload_dialog.dart#L300](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L300), [media_pipeline_repository.dart#L196](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/media/data/media_pipeline_repository.dart#L196).
- After upload, the frontend does not call `/api/media/upload-url/complete`; instead it creates the Home library row by calling `POST /studio/home-player/uploads` with `media_asset_id`, then polls asset status until `ready`. Evidence: [home_player_upload_dialog.dart#L300](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L300), [home_player_upload_dialog.dart#L507](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L507).

Backend flow:

- `POST /api/media/upload-url` accepts `purpose = home_player_audio`, forbids `course_id` and `lesson_id`, and builds the source path `media/source/audio/home-player/{user_id}/{filename}`. Evidence: [api_media.py#L329](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L329), [api_media.py#L339](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L339), [media_paths.py#L87](/home/rodenhjalm/Aveli-media-control-plane/backend/app/utils/media_paths.py#L87).
- The same request immediately creates a `media_assets` row with `purpose = home_player_audio`, `media_type = audio`, and initial state `uploaded`. Evidence: [api_media.py#L385](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L385).
- `POST /studio/home-player/uploads` then validates that the asset belongs to the teacher and that its purpose is exactly `home_player_audio` before creating a `home_player_uploads` row pointing at `media_asset_id`. Evidence: [studio.py#L722](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L722), [studio.py#L728](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L728), [studio.py#L732](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L732).
- The transcode worker rewrites `media/source/audio/...` to `media/derived/audio/...`, uploads an mp3, and marks the asset `ready`. Evidence: [media_transcode_worker.py#L46](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/media_transcode_worker.py#L46), [media_transcode_worker.py#L243](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/media_transcode_worker.py#L243), [media_transcode_worker.py#L263](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/media_transcode_worker.py#L263).

Resulting identifiers:

- source storage path in `course-media`
- `app.media_assets.id`
- `app.home_player_uploads.id`

The Home runtime feed later uses `media_assets.id`, not `home_player_uploads.id`.

### 4.3 Link Existing Course Media Into Home

Frontend flow:

- The teacher opens the "Lankat fran kurser" section and chooses "Lanka media". Evidence: [profile_media_page.dart#L170](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/presentation/profile_media_page.dart#L170), [profile_media_page.dart#L948](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/presentation/profile_media_page.dart#L948).
- The selectable source list comes from `list_teacher_lesson_media_sources()`. Evidence: [studio.py#L545](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L545), [teacher_profile_media.py#L249](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/teacher_profile_media.py#L249).
- The frontend posts `lesson_media_id` and title to `POST /studio/home-player/course-links`. Evidence: [studio_repository.dart#L468](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/data/studio_repository.dart#L468), [profile_media_page.dart#L974](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/presentation/profile_media_page.dart#L974).

Backend flow:

- The backend verifies that the current teacher owns the course containing that `lesson_media` row. Evidence: [studio.py#L882](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L882), [home_player_library.py#L218](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/home_player_library.py#L218).
- It only allows audio or video source kinds. Evidence: [studio.py#L890](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L890).
- It upserts `app.home_player_course_links` on `(teacher_id, lesson_media_id)`. Evidence: [home_player_library.py#L239](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/home_player_library.py#L239).

Resulting identifiers:

- `app.home_player_course_links.id`
- `app.home_player_course_links.lesson_media_id`

The Home runtime feed later uses `lesson_media.id` as the item id.

## 5. Playback Resolution Path

### 5.1 Direct MP3/MP4 Home Upload

```text
teacher picks mp3/mp4
-> POST /studio/home-player/uploads/upload-url
-> signed upload to course-media/home-player/{teacher}/{token}_{filename}
-> POST /studio/home-player/uploads
-> create media_objects row
-> create home_player_uploads row
-> GET /home/audio
-> backend returns item id = media_objects.id + signed_url/download_url
-> Home UI uses preferredUrl
-> mediaRepository.resolvePlaybackUrl()
-> inline audio player
```

Evidence: [studio.py#L564](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L564), [studio.py#L798](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L798), [courses.py#L1323](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1323), [home_dashboard_page.dart#L843](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L843).

### 5.2 Direct WAV Home Upload

```text
teacher picks wav
-> POST /api/media/upload-url (purpose = home_player_audio)
-> create media_assets row (state = uploaded)
-> signed upload to course-media/media/source/audio/home-player/{user}/{filename}
-> POST /studio/home-player/uploads (media_asset_id)
-> create home_player_uploads row
-> worker transcodes source wav to course-media/media/derived/audio/home-player/{user}/{filename}.mp3
-> worker marks media_assets.state = ready
-> GET /home/audio
-> backend returns item id = media_assets.id, media_asset_id = media_assets.id
-> Home UI calls POST /api/media/playback-url
-> backend authorizes and returns presigned playback URL
-> inline audio player
```

Evidence: [api_media.py#L307](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L307), [home_player_upload_dialog.dart#L300](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/studio/widgets/home_player_upload_dialog.dart#L300), [media_transcode_worker.py#L243](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/media_transcode_worker.py#L243), [home_dashboard_page.dart#L818](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L818).

### 5.3 Linked Course Media in Home

```text
teacher picks existing lesson_media row
-> POST /studio/home-player/course-links
-> upsert home_player_course_links(lesson_media_id)
-> GET /home/audio
-> backend joins lesson_media + media_objects + media_assets
-> item id = lesson_media.id
-> if media_asset_id exists and is ready:
   frontend calls POST /api/media/playback-url with media_asset_id
-> else:
   backend has already attached signed/public legacy URL on the feed item
-> inline audio player
```

Evidence: [courses.py#L1213](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1213), [courses.py#L1242](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1242), [courses.py#L1271](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1271), [home_dashboard_page.dart#L818](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L818), [home_dashboard_page.dart#L843](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L843).

### 5.4 Important Runtime Observation

The Home player does not use the same playback path as the lesson content player.

- Lesson content always resolves via `POST /api/media/lesson-playback`. Evidence: [lesson_media_playback_resolver.dart#L66](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/shared/utils/lesson_media_playback_resolver.dart#L66).
- Home feed playback does not call that endpoint. It uses `POST /api/media/playback-url` for asset-backed items or uses feed-attached signed/public URLs for legacy items. Evidence: [home_dashboard_page.dart#L818](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L818), [home_dashboard_page.dart#L843](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L843).

That is a concrete bypass of the newer Media Control Plane-style lesson resolver.

## 6. Storage Model

### Bucket Contract

Configured buckets:

- `course-media` is the default private source bucket. Evidence: [config.py#L205](/home/rodenhjalm/Aveli-media-control-plane/backend/app/config.py#L205).
- `public-media` is the public bucket. Evidence: [config.py#L206](/home/rodenhjalm/Aveli-media-control-plane/backend/app/config.py#L206).
- `lesson-media` still exists as a legacy private bucket in schema defaults and storage migrations. Evidence: [001_app_schema.sql#L263](/home/rodenhjalm/Aveli-media-control-plane/supabase/migrations/001_app_schema.sql#L263), [20260102113600_storage_public_media.sql#L20](/home/rodenhjalm/Aveli-media-control-plane/supabase/migrations/20260102113600_storage_public_media.sql#L20).

Storage visibility:

- `public-media` is created as public.
- `course-media` and `lesson-media` are created as private.

Evidence: [20260102113600_storage_public_media.sql#L20](/home/rodenhjalm/Aveli-media-control-plane/supabase/migrations/20260102113600_storage_public_media.sql#L20), [20260102113600_storage_public_media.sql#L25](/home/rodenhjalm/Aveli-media-control-plane/supabase/migrations/20260102113600_storage_public_media.sql#L25), [20260102113600_storage_public_media.sql#L30](/home/rodenhjalm/Aveli-media-control-plane/supabase/migrations/20260102113600_storage_public_media.sql#L30).

### Home-Specific Paths

| Path family | Bucket | Public or private | Used for |
| --- | --- | --- | --- |
| `home-player/{teacher_id}/{token}_{filename}` | `course-media` | private | direct MP3/MP4 Home uploads |
| `media/source/audio/home-player/{user_id}/{filename}` | `course-media` | private | Home WAV source uploads |
| `media/derived/audio/home-player/{user_id}/{filename}.mp3` | `course-media` | private | worker-generated Home WAV playback assets |

Evidence: [studio.py#L609](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L609), [media_paths.py#L87](/home/rodenhjalm/Aveli-media-control-plane/backend/app/utils/media_paths.py#L87), [media_transcode_worker.py#L46](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/media_transcode_worker.py#L46).

### Linked Course Media Paths

Linked course items may resolve from:

- `ma.streaming_object_path` or `ma.original_object_path` when `lesson_media.media_asset_id` exists
- `mo.storage_path` when `lesson_media.media_id` exists
- `lesson_media.storage_path` as a direct storage tuple fallback

Evidence: [courses.py#L1278](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1278), [courses.py#L1283](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1283).

### URL Generation Rules

- Public objects in `public-media` become stable public URLs through `StorageService.public_url()` or `media_signer._public_download_path()`. Evidence: [storage_service.py#L72](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/storage_service.py#L72), [media_signer.py#L158](/home/rodenhjalm/Aveli-media-control-plane/backend/app/utils/media_signer.py#L158).
- Private legacy objects get app-signed `/media/stream/<jwt>` links when signing succeeds; the feed model otherwise falls back to `download_url`, which is typically `/studio/media/{id}` for non-public legacy objects. Evidence: [media_signer.py#L54](/home/rodenhjalm/Aveli-media-control-plane/backend/app/utils/media_signer.py#L54), [media_signer.py#L245](/home/rodenhjalm/Aveli-media-control-plane/backend/app/utils/media_signer.py#L245), [home_audio_repository.dart#L59](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/data/home_audio_repository.dart#L59).
- Private pipeline objects get Supabase presigned playback URLs. Evidence: [lesson_playback_service.py#L133](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L133), [storage_service.py#L86](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/storage_service.py#L86).
- Upload URLs are always signed server-side through Supabase Storage. Evidence: [storage_service.py#L174](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/storage_service.py#L174).

## 7. Failure Conditions

### Runtime Failures

| Failure condition | Where enforced | Effect on Home player |
| --- | --- | --- |
| Item is not `kind == audio` | Home UI filter | Item is excluded from playable playlist entirely |
| Content type is not mp3-compatible when known | Home UI filter | Play button disabled and status says Home uses mp3 audio |
| Pipeline asset is not `ready` | Home UI + backend playback | Item can appear in library/feed, but play stays disabled until ready |
| Pipeline asset has failed processing | Home UI | Play stays disabled and status shows processing failed |
| Legacy item has no signed/download URL | Home UI | Play button disabled |
| User lacks teacher ownership or enrollment | feed query and playback auth | Item is excluded from feed or playback URL request fails with 403 |
| Storage path or object is missing | stream/proxy or playback-url issuer | playback fails with 404 or 503 |
| Linked course media points at unpublished or inaccessible course | feed query and lesson auth | item is filtered out or denied |
| Video is uploaded or linked into Home | Home UI filter | library item exists, but Home dashboard remains audio-only |

Evidence: [home_dashboard_page.dart#L653](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L653), [home_dashboard_page.dart#L663](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L663), [home_dashboard_page.dart#L674](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L674), [lesson_playback_service.py#L87](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L87), [media.py#L190](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/media.py#L190).

### Why These Failures Are Rare in Practice

- Upload routes constrain file types early.
- Storage paths are deterministic and prefix-validated.
- Course-linked pipeline rows are only included when `ma.state = 'ready'`.
- Direct pipeline uploads are visible while processing, but the Home UI refuses playback until `ready`.
- The Home UI narrows the playback surface to audio items only.
- Access rules are simple and consistent: teacher, intro/free-intro, or enrolled member.

Evidence: [studio.py#L577](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L577), [studio.py#L761](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L761), [courses.py#L1242](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1242), [home_dashboard_page.dart#L663](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L663).

### Subtle Edge Case

There is one code-level edge case worth calling out:

- `attach_media_links()` prepares a legacy `download_url` for non-public legacy objects when legacy media is enabled, and `HomeAudioItem.preferredUrl` uses `signedUrl ?? downloadUrl`. If signing fails or is disabled, the frontend can therefore fall back to `/studio/media/{id}`. Evidence: [media_signer.py#L245](/home/rodenhjalm/Aveli-media-control-plane/backend/app/utils/media_signer.py#L245), [media_signer.py#L280](/home/rodenhjalm/Aveli-media-control-plane/backend/app/utils/media_signer.py#L280), [home_audio_repository.dart#L59](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/data/home_audio_repository.dart#L59).
- But `/studio/media/{media_id}` resolves only lesson-media rows through `models.get_media()`. Evidence: [studio.py#L1865](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L1865).

That means a legacy direct Home upload backed only by `media_objects.id` is safe when the signed `/media/stream/<jwt>` branch is available, but can fail if the frontend has to fall back to `/studio/media/{media_object_id}`. This is another reason production signing matters for the Home legacy branch.

## 8. Architectural Invariants

These are the clearest invariants that appear to have made the Home player stable enough to survive broader pipeline instability.

1. Runtime playback is driven by a single curated feed projection, not by distributed frontend resolution logic.
2. Home media is explicit. A teacher either uploads directly into `home_player_uploads` or explicitly links a `lesson_media` row into `home_player_course_links`.
3. Storage identity is materialized before the frontend renders the item: every feed row already carries `storage_path`, `storage_bucket`, `media_id`, `media_asset_id`, `media_state`, and metadata.
4. The Home dashboard is intentionally audio-only. This removes most of the complexity of mixed media rendering.
5. The Home dashboard is effectively mp3-only at play time. It refuses unsupported audio and waits for transcoding to finish.
6. Pipeline items are never treated as playable until `state == ready`.
7. Access is enforced at two layers: feed selection and playback URL issuance.
8. Direct Home uploads are decoupled from lesson markdown and course content structure.
9. Upload path families are deterministic and bucket-relative.
10. The UI chooses one of two playback branches per item: pipeline asset or pre-resolved legacy/public URL. It does not try many resolver branches client-side.

Evidence: [courses.py#L1266](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1266), [home_dashboard_page.dart#L653](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L653), [home_dashboard_page.dart#L663](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L663), [studio.py#L609](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L609), [api_media.py#L345](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L345), [lesson_playback_service.py#L65](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L65).

## 9. Comparison With Media Control Plane

### Home Runtime vs Current Lesson/MCP Runtime

| Dimension | Home player | Current lesson/MCP path |
| --- | --- | --- |
| Primary runtime endpoint | `GET /home/audio` | `POST /api/media/lesson-playback` |
| Runtime source | curated union of `home_player_*` tables | per-lesson canonical resolver over `lesson_media` |
| Public runtime id | mixed: `lesson_media.id`, `media_asset.id`, or `media_object.id` | `lesson_media.id` |
| Asset-backed playback | `POST /api/media/playback-url` with `media_asset_id` | resolver decides whether to use `media_asset` or legacy storage |
| Legacy playback | pre-attached signed/public URLs on feed items | backend lesson resolver chooses legacy branch when needed |
| Upload surface | direct MP3/MP4 plus WAV pipeline plus explicit links | lesson audio pipeline plus lesson passthrough uploads |
| UI media surface | audio-only dashboard | mixed lesson content rendering |

Evidence: [home.py#L14](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/home.py#L14), [api_media.py#L881](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L881), [api_media.py#L899](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L899), [lesson_playback_service.py#L391](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L391).

### What Is Simpler in Home

- Explicit library curation instead of implicit discovery.
- One backend feed already shaped for the exact UI.
- Audio-only playback surface.
- Direct MP3 path that bypasses transcoding entirely.
- Hard play gating based on `ready` and URL presence.

### What Is More Complex in the Newer System

- The newer lesson path must reconcile `lesson_media`, `media_assets`, `media_objects`, and direct storage tuples through a canonical resolver. Evidence: [media_resolver_service.py#L146](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L146).
- It must preserve authored `lesson_media.id` semantics while still supporting legacy and pipeline storage backends. Evidence: [media_resolver_service.py#L225](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L225).
- It has a larger render surface, including images, documents, and video.

### What Home Still Gets Wrong

- Home is more stable, but it is not fully unified. It still mixes identities by source type.
- `enabled_for_home_player` exists on `teacher_profile_media`, but the actual Home runtime query does not use `teacher_profile_media` at all. Evidence: [20260201133000_teacher_profile_media_home_player_flags.sql#L6](/home/rodenhjalm/Aveli-media-control-plane/supabase/migrations/20260201133000_teacher_profile_media_home_player_flags.sql#L6), [studio.py#L495](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L495), [home.py#L19](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/home.py#L19).

That unused flag is a sign that the Home library path and the teacher-profile-media path are adjacent features, not the same runtime system.

## 10. Lessons For Media Control Plane

1. Keep one backend projection per runtime surface. The Home player is stable partly because the frontend does not have to assemble media contracts itself.
2. Keep playback deterministic. A feed item should arrive with a single known playback branch.
3. Keep upload paths canonical and bucket-relative. Both Home upload branches are stable because their path families are rigid.
4. Keep readiness explicit. The Home UI refuses to play unfinished pipeline assets instead of speculating.
5. Keep curation explicit. `home_player_course_links` is much simpler than trying to infer Home eligibility from all lesson media.
6. Keep access checks simple and repeatable. Home rechecks access at playback issuance even after feed filtering.
7. Avoid mixing management ids and runtime ids in the long-term Media Control Plane API. Home survives this today, but it is a real architectural weakness.
8. Avoid multiple playback APIs for the same runtime surface. Home currently works around complexity by bypassing the lesson resolver, but the final Media Control Plane should converge instead of adding a fourth parallel path.

## 11. Recommendations

1. Preserve the Home pattern of a dedicated backend read model for runtime media, even if the underlying storage implementation changes.
2. Preserve deterministic path families and bucket ownership rules before adding more transcoding steps.
3. Preserve hard `ready` gating for pipeline-backed playback; do not let the final Media Control Plane expose half-finished media as playable.
4. Preserve explicit curation semantics like `home_player_course_links` instead of inferring Home eligibility from profile flags or lesson content.
5. Remove identity ambiguity in the final Media Control Plane. Choose one public runtime id per surface and keep `media_asset_id` and `media_object.id` internal whenever possible.
6. Collapse playback issuance toward one canonical backend resolver once the final contract is stable; avoid retaining all of `/media/sign`, `/api/media/playback-url`, and `/api/media/lesson-playback` for the same end-user surface.
7. Either wire `teacher_profile_media.enabled_for_home_player` into the final runtime or remove it from the architecture. As implemented today, it adds conceptual complexity without contributing to Home playback.
8. Preserve Home's small playback surface. The fact that Home currently ignores video at runtime is part of why it has remained dependable.

## Appendix: Reference Diagrams

### Runtime Topology

```text
teacher control panel
-> app.home_player_uploads ------------------.
                                             |
teacher links lesson media                   v
-> app.home_player_course_links -> GET /home/audio -> normalized Home feed
                                             |
                                             v
                                   Home dashboard selection logic
                                   - audio-only
                                   - ready-gated
                                   - pipeline or legacy branch
                                             |
                      .----------------------'----------------------.
                      v                                             v
      POST /api/media/playback-url                       signed/public URL already attached
      with media_asset_id                                on the feed row
                      v                                             v
             presigned Supabase URL                         /media/stream/<jwt>
                      v                                             v
                    player                                        player
```

### Upload Topology

```text
mp3/mp4:
UI -> /studio/home-player/uploads/upload-url
   -> signed upload to course-media/home-player/...
   -> /studio/home-player/uploads
   -> media_objects + home_player_uploads

wav:
UI -> /api/media/upload-url (purpose=home_player_audio)
   -> media_assets(uploaded) + signed upload to course-media/media/source/audio/home-player/...
   -> /studio/home-player/uploads
   -> home_player_uploads(media_asset_id)
   -> worker -> course-media/media/derived/audio/home-player/...mp3
   -> media_assets(ready)

course link:
UI -> /studio/home-player/course-links
   -> home_player_course_links(lesson_media_id)
```
