# LER-013 CONTINUOUS AUTHORING SURFACE

TYPE: `OWNER`
TASK_TYPE: `FRONTEND_UX_CONTRACT_ALIGNMENT`
DEPENDS_ON: `[LER-012]`

## Goal

Materialize the post-final contract amendment that the Course Editor authoring
surface must feel like one flowing document instead of multiple visible block
containers, while keeping deterministic `lesson_document_v1` block/node
mapping.

## Required Outputs

- contract law for a single continuous authoring surface
- frontend `LessonDocumentEditor` renders one continuous writing surface
- text, list, media, and CTA nodes remain mapped to `lesson_document_v1`
- no Markdown, Quill, or legacy conversion path is reintroduced
- widget regression coverage for the continuous surface

## Forbidden

- visible per-block Card/ListTile authoring containers as the writing model
- Markdown textarea fallback
- Quill editor fallback
- legacy adapter/guard/session pathways returning
- weakening `content_document` persistence or ETag / If-Match behavior

## Verification

Run frontend analyzer and widget tests for `LessonDocumentEditor`, then rerun
the LER aggregate/audit gate affected by manifest extension.

## Execution Record

EXECUTION_STATUS: `COMPLETED`

Completed on: `2026-04-23`

### Materialized Outputs

- Added continuous authoring surface law to
  `actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md`.
- Added Course + Lesson Editor contract language that continuous authoring is
  presentation-only and must still map to `lesson_document_v1`.
- Reworked `frontend/lib/editor/document/lesson_document_editor.dart` so the
  authoring area exposes one
  `lesson_document_continuous_writing_surface` under the toolbar instead of
  stacked Cards/ListTiles and outlined per-block containers.
- Kept deterministic internal edit targets for paragraph, heading, list item,
  media, and CTA nodes.
- Added styled document text rendering in editor text controllers so inline
  marks can display within the writing surface without a separate
  `Formatvisning` block.
- Added widget regression coverage in
  `frontend/test/widgets/lesson_document_editor_test.dart`.
- Updated `LER-012` aggregate gate to allow post-final follow-up tasks without
  weakening the original `LER-001` through `LER-012` order assertion.

### Verification Evidence

- `dart format lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  completed.
- `flutter analyze lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  passed with no issues.
- `flutter test test\widgets\lesson_document_editor_test.dart` passed:
  `6 passed`.
- Broad frontend editor, preview, learner, media, and repository suite passed:
  `70 passed`.
- Broad backend aggregate/audit gate suite passed: `82 passed`, with the
  existing `python_multipart` warning.
- `python -m json.tool actual_truth\DETERMINED_TASKS\lesson_editor_rebuild\task_manifest.json`
  completed.

### Deterministic Result

`LER-013` materializes the continuous writing surface requirement without
reintroducing Markdown, Quill, or legacy pathways. The editor still persists
and validates `lesson_document_v1` through the existing `content_document`
authority.
