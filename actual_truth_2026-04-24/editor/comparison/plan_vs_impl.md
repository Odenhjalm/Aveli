# editor — planned vs implemented

## planned sources
- docs/architecture/aveli_editor_architecture_v2.md

## implemented sources
- frontend/lib/features/studio/presentation/course_editor_page.dart
- frontend/lib/editor/session/editor_session.dart
- frontend/lib/editor/session/editor_operation_controller.dart
- frontend/lib/shared/utils/lesson_content_pipeline.dart
- frontend/lib/shared/utils/quill_embed_insertion.dart
- frontend/test/widgets/course_editor_screen_test.dart
- frontend/test/widgets/lesson_media_preview_editor_regression_test.dart
- frontend/test/unit/quill_embed_insertion_test.dart

## gaps
- Full migration to the session-based architecture is described but not fully implemented in visible runtime code.
- Existing editor code still relies heavily on direct quill mutation paths.

## contradictions
- Plan documents request phased refactor and guard/session model improvements, while current implementation remains in mixed legacy/transitional form.
