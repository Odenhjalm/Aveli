Docs Overview

- Course Import (text + media)
- SFU / LiveKit troubleshooting

Course Import

- Purpose: move course content (markdown, audio, images, video) into the database using the existing Studio API.
- Script: `scripts/import_course.py`
- Manifest: YAML or JSON. Example at `scripts/course_manifest.example.yaml`.

Minimal manifest keys
- `title` (string) – course title
- `slug` (string) – URL-friendly id
- `description` (string, optional)
- `is_free_intro` (bool, optional)
- `is_published` (bool, optional)
- `price_cents` (int, optional)
- `cover_path` (string, optional) – local image file path to upload; auto-sets `cover_url`
- `cover_url` (string, optional) – public URL alternative to `cover_path`
- `modules` (list)
  - `title` (string)
  - `lessons` (list)
    - `title` (string)
    - `markdown` (string, optional) – relative path to a .md file
    - `is_intro` (bool, optional)
    - `media` (list, optional)
      - items: `{ path: <relative file path> }` or just a string path

Example (YAML)

title: Foundations of SoulWisdom
slug: foundations-of-soulwisdom
description: Intro to practices and core ideas
is_free_intro: true
is_published: false
price_cents: 0
cover_path: media/cover.jpg
modules:
  - title: Start
    lessons:
      - title: Välkommen
        markdown: lessons/welcome.md
        is_intro: true
        media:
          - path: media/welcome.jpg
          - path: media/intro_audio.mp3

Run the import

- Backend running locally (see top-level README for backend dev).
- Dry run to validate manifest & files (no uploads):
  - `python scripts/import_course.py --manifest /path/to/manifest.yaml --base-url http://127.0.0.1:8000 --email x --password y --dry-run`
  - Add `--max-size-mb 100` to warn on files >100 MB.
- Then import for real:
  - `python scripts/import_course.py \
     --base-url http://127.0.0.1:8000 \
     --email teacher@example.com \
     --password teacher123 \
     --manifest /full/path/to/course_manifest.yaml`
- Add `--create-assets-lesson` to upload the cover into a dedicated module/lesson (`_Assets`/`_Course Assets`).
- Student course page hides any module or lesson whose title begins with `_`.

Notes
- Media uploads are subject to `LESSON_MEDIA_MAX_BYTES` (bytes) in backend env.
- On web, protected media must be public/signed URLs (headers aren’t attached by `<img>`); mobile/desktop attach Authorization automatically where needed.

SFU / LiveKit troubleshooting
-----------------------------

See `docs/sfu_troubleshooting.md` for common failure modes, metrics to inspect, and guidance on replaying webhook jobs.
