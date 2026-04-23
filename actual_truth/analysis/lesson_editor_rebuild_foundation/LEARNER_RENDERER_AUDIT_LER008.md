# LEARNER RENDERER AUDIT LER-008

DATE: `2026-04-23`

SCOPE: deterministic alignment of learner lesson rendering to the
`lesson_document_v1` public content surface.

## Contract Decision

Learner rendering must use backend-provided `content_document` as content
truth. `content_markdown` is no longer allowed to drive rebuilt learner
rendering.

Access law remains unchanged: app-entry, course enrollment, unlock position,
and drip checks still gate the lesson route before protected content is read.

## Backend Result

- `LessonContentItem` now carries `content_document`.
- `read_protected_lesson_content_surface` canonicalizes document JSON before
  returning protected content.
- `get_lesson_content_surface_rows` reads `content_document` from
  `app.lesson_content_surface`.
- Existing media composition still resolves lesson media through backend media
  services and returns backend-authored media objects.

## Frontend Result

- `LessonDetail` now stores `LessonDocument`.
- `CoursesRepository.fetchLessonDetail` parses `content_document` and rejects
  `content_markdown` in learner content payloads.
- `LessonPage` renders only when the persisted document contains blocks.
- `LearnerLessonContentRenderer` and `LessonPageRenderer` use
  `LessonDocumentPreview`.
- Learner image, audio, video, and document blocks render from media objects
  provided by the learner content response.

## Explicit Non-Authority

The LER-008 learner render path does not use:

- `content_markdown`
- `contentMarkdown`
- `markdown_to_editor`
- `flutter_quill`
- `PreparedLessonRenderContent`
- `prepareLessonRenderContent`
- Markdown media tokens such as `!image(...)`
- frontend-constructed media URLs

## Test Alignment

- Learner renderer widget tests now build `LessonDocument` fixtures directly.
- Lesson page tests prove extra non-embedded media rows do not become rendered
  content.
- Backend surface tests prove protected content returns canonical document
  shape while preserving media and access semantics.
- Source gates prevent Quill/Markdown learner rendering from returning.

## Next Edge

`LER-009` can now remove or quarantine legacy Markdown and Quill code because
the editor save path, persisted preview path, learner rendering path, media
nodes, and CTA nodes have document-model replacements.
