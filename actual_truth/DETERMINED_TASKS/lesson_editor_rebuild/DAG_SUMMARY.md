# LESSON_EDITOR_REBUILD DAG

## STATUS

LER-012_COMPLETED

`LER-001`, `LER-002`, `LER-003`, `LER-004`, `LER-005`, `LER-006`,
`LER-007`, `LER-008`, `LER-009`, `LER-010`, `LER-011`, and `LER-012`
are complete.

The deterministic lesson editor rebuild DAG is closed. There is no remaining
successor task in this tree.

## Topological Order

1. `LER-001`
2. `LER-002`
3. `LER-003`
4. `LER-004`
5. `LER-005`
6. `LER-006`
7. `LER-007`
8. `LER-008`
9. `LER-009`
10. `LER-010`
11. `LER-011`
12. `LER-012`

## Dependency Graph

- `LER-001 -> LER-002`
- `LER-002 -> LER-003`
- `LER-002 -> LER-004`
- `LER-004 -> LER-005`
- `LER-005 -> LER-006`
- `LER-006 -> LER-007`
- `LER-007 -> LER-008`
- `LER-003 -> LER-009`
- `LER-008 -> LER-009`
- `LER-003 -> LER-010`
- `LER-006 -> LER-010`
- `LER-008 -> LER-010`
- `LER-009 -> LER-011`
- `LER-010 -> LER-011`
- `LER-011 -> LER-012`

## Determinism Notes

- Contract reconciliation is first because current active contracts still
  declare Markdown as canonical.
- Backend and frontend model work split after substrate/API shape is defined.
- `LER-005` completed because the visible Course Editor authoring surface and
  save path now use `lesson_document_v1` / `content_document`, not
  Quill/Markdown authority.
- `LER-006` is eligible only because document-model authoring and save now
  exist.
- `LER-006` completed because media and CTA authoring now persist as
  `lesson_document_v1` nodes and validators reject invalid governed media/CTA
  nodes.
- `LER-007` is eligible only after media/CTA nodes can survive persisted save
  and reload.
- `LER-007` completed because Course Editor Preview Mode now renders the
  persisted `content_document` read projection through `LessonDocumentPreview`
  and hydrates only backend-authored media placements referenced by that saved
  document.
- `LER-008` is eligible because persisted editor preview rendering is no longer
  blocked by draft, Markdown, or Quill preview authority.
- `LER-008` completed because learner lesson reads now expose canonical
  `content_document`, the frontend parses that into `LessonDocument`, and
  learner rendering shares `LessonDocumentPreview` document rules with
  persisted editor preview while media rendering uses backend-authored media
  objects.
- `LER-009` is eligible because document save, persisted preview, learner
  rendering, media nodes, and CTA nodes now have replacements.
- `LER-009` completed because Quill/Markdown editor authority, Markdown
  roundtrip validation, old adapter/session/guard code, and old Markdown
  dependencies were removed from rebuilt editor, preview, learner, and backend
  validation paths. Publish readiness now validates `content_document` rather
  than `content_markdown`.
- `LER-010` is eligible because legacy authority has been removed and the next
  missing gate is a positive document fixture/test corpus for the required
  capabilities.
- `LER-010` completed because the active positive
  `lesson_document_v1` fixture corpus now covers every required editor
  capability and is consumed by backend validation, frontend model, editor
  widget, persisted preview, learner renderer, and ETag tests.
- `LER-011` is eligible because legacy removal and positive corpus coverage
  now exist, so deterministic source gates can be added against forbidden
  authority returning.
- `LER-011` completed because seed-tested deterministic audit gates now
  block legacy Markdown/Quill save authority, backend Flutter/Markdown
  validation, draft preview authority, frontend media URL construction, and
  removed editor-only dependencies from returning to rebuilt editor paths.
- `LER-012` completed because the final aggregate gate now verifies the full
  editor rebuild chain across contracts, backend document validation,
  `content_document` persistence, frontend document authoring, media/CTA
  document nodes, persisted-only preview, learner document rendering, removed
  legacy authority, dependency removal, required test inventory, and broad
  backend/frontend verification.
- Legacy removal waited until document save, render, media, CTA, preview, and
  learner paths had replacements.
- Final gates executed only after tests and removal gates existed.
