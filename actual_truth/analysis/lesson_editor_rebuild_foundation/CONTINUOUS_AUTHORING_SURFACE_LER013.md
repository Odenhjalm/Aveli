# CONTINUOUS AUTHORING SURFACE AUDIT - LER-013

Date: `2026-04-23`

Status: `COMPLETED`

## Decision

The rebuilt editor must present a single continuous writing surface. Users
should experience authoring as one flowing document, not as multiple visible
block editors.

This is a presentation law only. It does not change the storage model,
validation model, preview authority, learner rendering authority, media law,
CTA law, or concurrency law.

## Prior State

`LessonDocumentEditor` already used `lesson_document_v1` internally, but the
authoring surface rendered blocks as separate Cards, list Cards, media
ListTiles, CTA Cards, outlined TextFields, labels, and a separate
`Formatvisning` preview per text block.

That was deterministic, but it did not satisfy the new continuous-writing
experience requirement.

## Materialized Change

- The editor body now exposes one keyed writing surface:
  `lesson_document_continuous_writing_surface`.
- Paragraphs, headings, lists, media nodes, and CTA nodes render inside that
  single surface.
- Text fields are borderless and styled according to document semantics rather
  than wrapped in visible block containers.
- List markers are presentation only; list content still maps to
  `bullet_list` and `ordered_list` item nodes.
- Media and CTA remain explicit document nodes, not Markdown tokens or links.
- Inline mark display is handled by a document-aware text controller, not by a
  secondary Markdown/Quill preview.

## Regression Coverage

`frontend/test/widgets/lesson_document_editor_test.dart` now verifies:

- exactly one continuous writing surface exists
- the surface does not render block Cards or ListTiles
- the old `Formatvisning` per-block display is gone
- editor text fields inside the surface are borderless
- serialized content remains `lesson_document_v1`
- no Markdown media token or `content_markdown` is produced

## Verification

- `flutter analyze lib\api\api_client.dart lib\api\api_paths.dart lib\main.dart lib\features\studio\presentation\course_editor_page.dart lib\features\courses\presentation\lesson_page.dart lib\editor\document\lesson_document.dart lib\editor\document\lesson_document_editor.dart test\widgets\lesson_document_editor_test.dart`
  passed with no issues.
- `flutter test test\widgets\lesson_document_editor_test.dart` passed:
  `6 passed`.
- Broad frontend editor, preview, learner, media, and repository suite passed:
  `70 passed`.
- `pytest backend\tests\test_ler012_final_aggregate_editor_gate.py -q`
  passed: `6 passed`, with the existing `python_multipart` warning.
- Broad backend aggregate/audit gate suite passed: `82 passed`, with the
  existing `python_multipart` warning.
- `python -m json.tool actual_truth\DETERMINED_TASKS\lesson_editor_rebuild\task_manifest.json`
  completed.

## Stop Condition Review

- Markdown was not reintroduced.
- Quill was not reintroduced.
- Legacy adapter/guard/session paths were not reintroduced.
- `content_document` persistence authority remains unchanged.
- Preview and learner rendering remain governed by persisted document content.
- ETag / If-Match behavior remains unchanged.

## Final Assertion

The Course Editor authoring experience now presents one continuous writing
surface while retaining deterministic `lesson_document_v1` block and node
mapping internally.
