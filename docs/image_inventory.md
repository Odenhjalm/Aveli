# Image Source Inventory — October 2025

This note captures every user-facing image source in the apps, how the bytes are loaded, and the failure modes observed while testing on 2025‑10‑13.

## 1. Sources & Fallbacks

| Area / Widget | Source | Endpoint / Storage | Transport | Fallback behaviour | Notes |
| --- | --- | --- | --- | --- | --- |
| Avatars (`AppAvatar`, profile chips) | `AppNetworkImage(url, requiresAuth: true)` | `GET /profiles/avatar/{media_id}` → `media/avatars/<user_id>/…` | Adds `Authorization` header on mobile/desktop; open on web | Vector icon placeholder | Works offline once cached; backend endpoint is public today. |
| Course cards (`CourseCard`, `CoursesGrid`, home explore carousel) | `CourseCoverAssets.resolve(assets, slug, cover_url)` (BackendAssetResolver → `/assets/images/courses/...`) else `NetworkImage` | `/studio/media/{lesson_media_id}` or `/assets/images/courses/<slug>.png` | Plain HTTPS | Gradient + icon overlay | Needs valid `lesson_media` row; backend asset fallback covers seedkurser. |
| Studio → preview stream (`MediaToolbar`, upload history) | `Image.network(download_url)` | `/studio/media/{lesson_media_id}` | Plain HTTPS | `Icons.broken_image_outlined` | Requires asset to exist; inherits 404/401 from backend. |
| Lesson content (`LessonPage`) | `MediaRepository.cacheMediaBytes()` -> `Image.memory` | `/studio/media/{lesson_media_id}` (public) | Uses API client; no auth headers in `<img>` | Empty container | Protects web from auth restrictions by bypassing `<img>` element. |
| Service cards (`ServiceCard`) | `Image.network` | `service.thumbnail_url` (external CDN) | HTTPS (should be) | Gradient + icon overlay | Pending audit: ensure all thumbnails use HTTPS in production. |
| Static backgrounds (`AppScaffold`, `FullBleedBackground`) | `BackendAssetResolver.imageProvider('images/bakgrund.png')` | `GET /assets/images/bakgrund.png` | HTTPS | N/A | Served via FastAPI static mount; cached by browser/client. |

## 2. Observed Issues (QA run 2025‑10‑13)

### 2.1 Missing course cover

```
select c.slug, c.cover_url, lm.id is not null as lesson_media_exists
from app.courses c
left join app.lesson_media lm on lm.id = nullif(split_part(c.cover_url, '/', 4), '')::uuid
order by slug;
```

Result:

| slug | cover_url | lesson_media_exists |
| --- | --- | --- |
| `att-tänka-själv-4yfs-hbuo58am2l` | `/studio/media/546f3e91-5be9-4191-b2e1-1154013fa602` | **false** |

- The stored `cover_url` points at a `lesson_media` ID that no longer exists, so `/studio/media/546f3e91-…` returns 404.
- All other current courses (`foundations-of-soulwisdom`, `qa-course-72647740`, `tarot-basics`, `tystnad-4mon-hbv2trkifi`) have valid `lesson_media` records.  
- Action: re-upload a cover or patch the course to reference an existing media ID. Tracked in `tasks.md` under “Image backlog”.

### 2.2 Null course cover

| slug | cover_url |
| --- | --- |
| `vem-tänker-och-vem-hör-tankar-aevu-hbuo6wmmc1` | `/studio/media/b1be5776-b4bb-496a-9d7c-2465b8e48d85` (backend) |

Course now references backend media `/studio/media/b1be5776-b4bb-496a-9d7c-2465b8e48d85`; fallback ligger på `/assets/images/courses/vem_tanker_cover.png`.

### 2.3 Other checks

- Media bytes for lessons (`app.lesson_media`) are consistent; every referenced `media_id` resolves to `app.media_objects`.
- No additional 404s were observed during the run; QA placeholders were removed from the database before this audit (see `docs/missing_course_covers.md`).
- Clear‑text HTTP requests are blocked in release builds (guard present in `main.dart`). Android dev tooling already installs `network_security_config` for `10.0.2.2`.

## 3. Next Steps

1. **Restore cover for `att-tänka-själv-4yfs-hbuo58am2l`.** Either re-upload via Studio or patch `cover_url` to a valid `/studio/media/{lesson_media_id}`.
2. **Done:** backend cover uploaded for `vem-tänker-och-vem-hör-tankar-…`; keep asset fallback in sync if image changes.
3. **Service thumbnails audit.** Spot-check `service.thumbnail_url` values to confirm HTTPS usage before iOS release.
4. Keep this document up to date after future imports or media clean-up jobs. The SQL snippets above can be re-run to verify integrity quickly.

## 4. Emulator log findings (Android)

We planned to capture `flutter run --verbose` output alongside targeted `adb logcat` traces to document any remaining 404/401/cleartext warnings on Android. The current workstation does not expose an Android emulator or physical device (`flutter devices` only reports Linux desktop and Chrome), so no Android-specific logs could be collected in this session.

### What to capture once an emulator is available

1. Launch the Pixel 7 (API 34) emulator documented in `BRA_KOMMANDON.md`, or attach a physical Android device with developer mode enabled.
2. Run:
   ```bash
   flutter run --verbose -d emulator-5554 > out/flutter_run_verbose.log 2>&1
   ```
   Let the session reach the profile/media views that previously generated missing-image warnings, then quit (`q`).
3. In a separate shell:
   ```bash
   adb logcat -v time | tee out/adb_cleartext_media.log
   ```
   Filter afterwards for `Image resource service`, `http://`, `Cleartext traffic`, and any 401/404 responses from `studio/media`.
4. Summarise the findings (affected URLs, HTTP status codes, timing) in this section and link any relevant issues back to the owning tasks.

Until those steps complete, the checklist item in `tasks.md` remains open.
