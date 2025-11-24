Bulk Import Checklist

- Goal: prepare per-course manifests and import them via `scripts/import_course.py`.
- Source: see `tasks.md` (Kursimport) – importer and dry-run are ready; this checklist tracks the first batch.

Steps per course

- [ ] Draft manifest (title, slug, description, flags)
- [ ] Validate manifest (`--dry-run`)
- [ ] Add cover (set `cover_url` or `cover_path` and optional `--create-assets-lesson`)
- [ ] Add modules/lessons (no file refs yet)
- [ ] Attach markdown/media (add paths when files exist)
- [ ] Import to local backend
- [ ] QA in app (intro gate, cover, listing, course detail)

Batch Status

- Foundations of SoulWisdom (`courses/foundations-of-soulwisdom.yaml`)
  - [x] Draft  [x] Dry-run  [x] Cover  [x] Modules  [x] Media  [x] Imported  [x] QA
  - QA: Intro lesson (`Start → Välkommen`) loads image/audio (200). Course cover patched to `/studio/media/6cac6773-bfa2-4d67-a449-c4b91d87ac1c` (200 OK).
- Tarot Basics (`courses/tarot-basics.yaml`)
  - [x] Draft  [x] Dry-run  [x] Cover  [x] Modules  [x] Media  [x] Imported  [x] QA
  - QA: Cover `/studio/media/4819993e-6e11-4f32-9624-50f581f40a12` 200 OK, intro lesson media (image/audio) 200 OK, course detail shows new modules.

Template

- Use `courses/_template.yaml` for new courses and adjust fields minimally.
