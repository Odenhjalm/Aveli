# PERSISTED PREVIEW AUDIT LER-007

DATE: `2026-04-23`

SCOPE: deterministic alignment of Course Editor Preview Mode to the
`lesson_document_v1` persisted content contract after `LER-006`.

## Contract Decision

Preview is not an authoring surface and is not a draft mirror. Its only content
authority is the backend read projection for the selected lesson's saved
`content_document`.

Preview may hydrate media display metadata, but only for media IDs already
embedded in the persisted document and only through backend-authored placement
objects.

## Implementation Result

- The Course Editor preview loader reads saved lesson content through
  `readLessonContent`.
- The preview document assigned to UI state is `content.contentDocument`.
- Preview media IDs are extracted from that persisted document, not from local
  editor draft state.
- Media display objects are loaded via `fetchLessonMediaPlacements`.
- Preview rendering uses `LessonDocumentPreview`.
- Preview rendering passes backend-authored media metadata to the document
  renderer.

## Explicit Non-Authority

The LER-007 preview path does not use:

- local `_lessonDocument` as preview content
- local `_lessonMedia` as preview media authority
- `content_markdown`
- Quill Delta
- learner Markdown renderer
- preview cache as content truth
- any preview mutation endpoint

## Test Alignment

The widget test now proves a saved `LessonDocument` appears in preview while a
separate unsaved draft document does not. The source-gate regression test now
asserts persisted document loading, persisted-media hydration, document preview
rendering, and forbidden draft/Markdown/cache/mutation tokens inside the scoped
preview functions.

## Verification

- Frontend analyzer passed for the document model, preview renderer, repository,
  Course Editor, and focused tests.
- Frontend unit/widget tests passed for the document model, content read/write
  repository behavior, media routing, and document editor preview.
- Backend source/contract tests passed for fixture corpus, document backend
  contract, write-path dominance, and focused studio lesson endpoints.

## Next Edge

`LER-008` must align learner rendering to the same document renderer. Until
then, remaining learner Markdown rendering is legacy evidence for the next DAG
node, not a contradiction in the completed Course Editor preview path.
