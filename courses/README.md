Courses Manifests

- This folder holds per-course manifests for bulk import using `scripts/import_course.py`.
- Manifests are YAML or JSON. Prefer YAML for readability.
- Keep manifests file-only (no local media references) until assets are ready; add `cover_path` and markdown/media paths later when files exist.

How to validate and import

- Dry-run (no uploads, validates manifest structure and referenced files):
  - `python scripts/import_course.py --base-url http://127.0.0.1:8080 --email teacher@example.com --password teacher123 --manifest courses/<file>.yaml --dry-run`
- Import:
  - `python scripts/import_course.py --base-url http://127.0.0.1:8080 --email teacher@example.com --password teacher123 --manifest courses/<file>.yaml`
- Optional: upload cover to a dedicated `_Assets` lesson and auto-set `cover_url`:
  - add `--create-assets-lesson`
- Optional: skip uploading duplicates / clean old ones:
  - add `--cleanup-duplicates`

Bulk import

- Validate all manifests:
  - `python scripts/bulk_import.py --dry-run`
- Import all manifests (order controlled by `courses/order.txt` if present):
  - `python scripts/bulk_import.py --base-url http://127.0.0.1:8080 --email teacher@example.com --password teacher123`
- Import a subset:
  - `python scripts/bulk_import.py --only tarot-basics --base-url ... --email ... --password ...`
- Optional flags:
  - `--create-assets-lesson` and/or `--cleanup-duplicates`

Notes

- Leave `cover_url` empty or use `cover_path` once the file exists locally. Sample assets live under `courses/assets/<slug>/` and can be replaced with real material.
- Avoid `markdown`/`media` paths until the files exist to keep dry-run green.
- See `scripts/course_manifest.example.yaml` and `docs/README.md` for full spec.
