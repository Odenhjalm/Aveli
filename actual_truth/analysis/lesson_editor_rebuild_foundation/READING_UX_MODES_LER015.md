# READING UX MODES AUDIT - LER-015

Date: `2026-04-23`

Status: `COMPLETED`

## Decision

The editor and learner reading surfaces must not expose internal model,
schema, Markdown, Quill, or debug labels to users. Reading style is a
presentation concern only.

The required UX is:

- a clean white editor writing surface
- Glass reading mode preserving the existing translucent style
- Paper reading mode with a white surface, subtle horizontal visual guide
  lines, and high-contrast text
- local-only reading-mode state in preview and learner surfaces

## Evidence

- `frontend/lib/editor/document/lesson_document_editor.dart` previously used a
  semitransparent editor shell and rendered internal model text below the
  writing surface.
- `frontend/lib/features/studio/presentation/course_editor_page.dart` rendered
  persisted preview through `LessonDocumentPreview` with no reading-mode state.
- `frontend/lib/features/courses/presentation/lesson_page.dart` rendered
  learner content inside a `GlassCard` with no user choice for Paper mode.
- `LessonDocumentPreview` already owned the shared persisted/learner document
  rendering path, so adding presentation-only reading mode there avoids
  duplicate renderer semantics.

## Materialized Behavior

- Editor shell background is `Colors.white`.
- The single continuous writing surface remains `Colors.white`.
- Internal model footer text was removed from editor UI.
- Preview helper copy now refers to saved content rather than the internal
  document model.
- `LessonDocumentReadingMode.glass` returns the existing preview widget tree.
- `LessonDocumentReadingMode.paper` wraps the same preview content in a white
  paper surface with visual-only horizontal lines.
- Course Editor Preview Mode and learner lesson content both expose the same
  Glass/Paper toggle.

## Contract Boundaries

- `lesson_document_v1` is unchanged.
- Backend APIs are unchanged.
- ETag / If-Match behavior is unchanged.
- Media and CTA nodes still render through the existing document renderer.
- Reading mode is not serialized and is not part of saved lesson content.
- No Markdown, Quill, or legacy rendering authority was reintroduced.

## Regression Coverage

`frontend/test/widgets/lesson_document_editor_test.dart` verifies:

- preview can switch Glass -> Paper -> Glass
- Paper mode does not mutate canonical document JSON
- editor shell and continuous writing surface are white
- internal model/Markdown footer text is not rendered

`frontend/test/widgets/lesson_preview_rendering_test.dart` verifies:

- learner content exposes the reading-mode toggle
- Paper mode renders the paper surface
- toggling modes does not mutate canonical document JSON
- learner document rendering still preserves existing content output

## Verification

- Focused frontend analyzer passed.
- Focused editor/preview/learner widget tests passed: `14 passed`.
- Broad task-scoped frontend regression passed: `41 passed`.
- Deterministic backend audit gates passed: `24 passed`, with the existing
  `python_multipart` warning.
- `task_manifest.json` validates as JSON.
- String audit confirmed no user-facing rebuilt editor/preview UI text still
  renders the removed internal model footer.

## Final Assertion

The UX change is presentation-only. The editor, persisted preview, and learner
rendering still use `lesson_document_v1` as the only document authority while
offering a cleaner white authoring surface and selectable Glass/Paper reading
modes.
