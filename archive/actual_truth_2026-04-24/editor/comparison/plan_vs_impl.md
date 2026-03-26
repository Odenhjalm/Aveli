# editor — planned vs implemented

## planned sources
- `actual_truth_2026-04-24/Aveli_System_Decisions.md`
- `docs/architecture/aveli_editor_architecture_v2.md`
- `docs/architecture/text_contract.md`
- `docs/markdown_contract_v1.md`

## implemented sources
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/editor/session/editor_session.dart`
- `frontend/lib/editor/session/editor_operation_controller.dart`
- `frontend/lib/editor/adapter/markdown_to_editor.dart`
- `frontend/lib/editor/adapter/editor_to_markdown.dart`
- `frontend/lib/features/studio/presentation/lesson_media_preview.dart`
- `frontend/lib/features/studio/presentation/lesson_media_preview_cache.dart`
- `frontend/lib/features/studio/presentation/lesson_media_preview_hydration.dart`
- `frontend/lib/shared/utils/lesson_content_pipeline.dart`
- `frontend/lib/shared/utils/quill_embed_insertion.dart`
- `frontend/test/widgets/course_editor_screen_test.dart`
- `frontend/test/widgets/lesson_media_preview_editor_regression_test.dart`

## system should be
- The editor should run through a dedicated mutation pipeline around a stable session identity.
- Canonical markdown should remain the sole stored truth while Quill stays an adapter.
- Preview should derive from the same canonical contract as student rendering, not from page-local editor state.

## system is
- `EditorSession` and markdown adapters exist in `frontend/lib/editor/`.
- Session/revision safety is still orchestrated primarily inside `course_editor_page.dart`.
- No `editor_mutation_pipeline.dart` module exists, despite being a named deliverable in the architecture plan.
- Preview hydration exists, but preview and mutation concerns still remain heavily coupled to the page widget and legacy Quill helpers.

## mismatches
- `[important] editor_extract_mutation_pipeline` — the planned mutation-pipeline module is still missing.
- `[important] editor_extract_session_orchestration` — session identity exists, but orchestration still lives mainly in `course_editor_page.dart`.
- `[informational] editor_finish_preview_contract_alignment` — preview uses the intended contract directionally, but the implementation is still page-coupled and not fully isolated from editor-local concerns.
