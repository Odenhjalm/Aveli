from __future__ import annotations

from pathlib import Path

from tools.lesson_editor_authority_audit import (
    assert_no_findings,
    dart_source_block,
    forbidden_regex_findings,
    forbidden_token_findings,
    missing_token_findings,
    python_decorated_function_block,
    read_repo_text,
)


REPO_ROOT = Path(__file__).resolve().parents[2]

FRONTEND_EDITOR_FORBIDDEN_TOKENS = (
    "serializeEditorDeltaToCanonicalMarkdown",
    "validateLessonMarkdownIntegrity",
    "editorDeltaToPassivePreviewMarkdown",
    "flutter_quill",
    "FlutterQuillEmbeds",
    "QuillController",
    "quill.Document",
    "EditorSession",
    "EditorOperationQuillController",
    "editor_test_bridge",
    "markdown_to_editor",
    "editor_to_markdown",
    "markdown_quill",
    "markdown_widget",
    "content_markdown",
    "contentMarkdown",
    "!image(",
    "!audio(",
    "!video(",
    "!document(",
)

BACKEND_VALIDATION_FORBIDDEN_TOKENS = (
    "lesson_markdown_validator",
    "validate_lesson_markdown",
    "lesson_content_utils",
    "subprocess",
    "Popen(",
    "markdown_quill",
    "flutter",
    "content_markdown",
)

FRONTEND_MEDIA_AUTHORITY_FORBIDDEN_TOKENS = (
    "/api/lesson-media/previews",
    "/api/lesson-media/$lessonId",
    "ApiPaths.mediaPreviews",
    "mediaPreviews =",
    "resolved_preview_url",
    "storage_path",
    "signed_url",
    "preview_ready",
)

FORBIDDEN_DEPENDENCY_PATTERNS = (
    r"\bflutter_quill\b",
    r"\bflutter_quill_extensions\b",
    r"\bmarkdown_quill\b",
    r"\bmarkdown_widget\b",
    r"^\s+markdown:\s",
)


def test_seeded_gate_detects_legacy_markdown_quill_save_authority() -> None:
    seeded = """
      import 'package:flutter_quill/flutter_quill.dart';
      final markdown = serializeEditorDeltaToCanonicalMarkdown(controller.document);
      validateLessonMarkdownIntegrity(markdown);
      await repo.updateLessonContent(id, contentMarkdown: markdown, ifMatch: etag);
    """

    findings = forbidden_token_findings(
        seeded,
        scope="seeded_frontend_save",
        tokens=FRONTEND_EDITOR_FORBIDDEN_TOKENS,
    )

    detected = {finding.token for finding in findings}
    assert "flutter_quill" in detected
    assert "serializeEditorDeltaToCanonicalMarkdown" in detected
    assert "validateLessonMarkdownIntegrity" in detected
    assert "contentMarkdown" in detected


def test_seeded_gate_detects_backend_flutter_markdown_validation() -> None:
    seeded = """
      from app.utils import lesson_markdown_validator
      import subprocess

      def validate(payload):
          subprocess.run(["flutter", "test"])
          return lesson_markdown_validator.validate_lesson_markdown(payload)
    """

    findings = forbidden_token_findings(
        seeded,
        scope="seeded_backend_validation",
        tokens=BACKEND_VALIDATION_FORBIDDEN_TOKENS,
    )

    detected = {finding.token for finding in findings}
    assert "lesson_markdown_validator" in detected
    assert "validate_lesson_markdown" in detected
    assert "subprocess" in detected
    assert "flutter" in detected


def test_seeded_gate_detects_draft_preview_and_frontend_media_url_authority() -> None:
    seeded_preview = """
      Future<void> _loadPersistedLessonPreview() async {
        setState(() {
          _lessonPreviewDocument = _lessonDocument;
        });
      }
      Widget _buildLessonPreviewMode(BuildContext context) {
        return LessonDocumentPreview(document: _lessonDocument);
      }
    """
    seeded_media = """
      static const mediaPreviews = '/api/lesson-media/previews';
      final url = payload['resolved_preview_url'] ?? payload['signed_url'];
      final path = payload['storage_path'];
    """

    preview_findings = forbidden_token_findings(
        seeded_preview,
        scope="seeded_preview",
        tokens=(
            "_lessonPreviewDocument = _lessonDocument",
            "document: _lessonDocument",
        ),
    )
    media_findings = forbidden_token_findings(
        seeded_media,
        scope="seeded_media",
        tokens=FRONTEND_MEDIA_AUTHORITY_FORBIDDEN_TOKENS,
    )

    assert {finding.token for finding in preview_findings} == {
        "_lessonPreviewDocument = _lessonDocument",
        "document: _lessonDocument",
    }
    assert "/api/lesson-media/previews" in {finding.token for finding in media_findings}
    assert "resolved_preview_url" in {finding.token for finding in media_findings}


def test_seeded_gate_detects_media_block_regressions() -> None:
    seeded = """
      void _insertMediaBlockIntoDocument({
        required String mediaType,
        required String lessonMediaId,
      }) {
        final nextDocument = _lessonDocument.insertMedia(
          _lessonDocument.blocks.length,
          mediaType: mediaType,
          lessonMediaId: lessonMediaId,
        );
        final legacyIndex = _resolvedLessonDocumentInsertionIndex();
      }

      Text('Media: ${block.mediaType}\\n${block.lessonMediaId}');
      final title = 'Media saknas: ${block.mediaType}';
      final label = media.originalName ?? media.mediaAssetId;
      return mediaAssetId;
    """

    findings = forbidden_token_findings(
        seeded,
        scope="seeded_media_block_regressions",
        tokens=(
            "_lessonDocument.blocks.length,",
            "_resolvedLessonDocumentInsertionIndex();",
            "Media: ${block.mediaType}",
            "${block.lessonMediaId}",
            "Media saknas: ${block.mediaType}",
            "media.originalName ?? media.mediaAssetId",
            "return mediaAssetId;",
        ),
    )

    detected = {finding.token for finding in findings}
    assert "_lessonDocument.blocks.length," in detected
    assert "_resolvedLessonDocumentInsertionIndex();" in detected
    assert "Media: ${block.mediaType}" in detected
    assert "${block.lessonMediaId}" in detected
    assert "media.originalName ?? media.mediaAssetId" in detected
    assert "return mediaAssetId;" in detected


def test_seeded_dependency_gate_detects_removed_editor_packages() -> None:
    seeded_pubspec = """
    dependencies:
      flutter_quill: 11.0.0
      flutter_quill_extensions: 11.0.0
      markdown_quill: 4.0.0
      markdown_widget: 2.0.0
      markdown: 7.0.0
    """

    findings = forbidden_regex_findings(
        seeded_pubspec,
        scope="seeded_pubspec",
        patterns=FORBIDDEN_DEPENDENCY_PATTERNS,
    )

    detected = {finding.token for finding in findings}
    assert r"\bflutter_quill\b" in detected
    assert r"\bmarkdown_quill\b" in detected
    assert r"^\s+markdown:\s" in detected


def test_rebuilt_editor_authoring_paths_have_no_legacy_authority_tokens() -> None:
    paths = (
        "frontend/lib/features/studio/presentation/course_editor_page.dart",
        "frontend/lib/editor/document/lesson_document.dart",
        "frontend/lib/editor/document/lesson_document_editor.dart",
    )

    findings = []
    for path in paths:
        findings.extend(
            forbidden_token_findings(
                read_repo_text(REPO_ROOT, path),
                scope=path,
                tokens=FRONTEND_EDITOR_FORBIDDEN_TOKENS,
            )
        )

    assert_no_findings(findings)


def test_studio_content_transport_uses_document_and_etag_only() -> None:
    repository_source = read_repo_text(
        REPO_ROOT,
        "frontend/lib/features/studio/data/studio_repository.dart",
    )
    read_block = dart_source_block(
        repository_source,
        "Future<StudioLessonContentRead> readLessonContent(",
    )
    write_block = dart_source_block(
        repository_source,
        "Future<StudioLessonContentWriteResult> updateLessonContent(",
    )

    assert_no_findings(
        missing_token_findings(
            read_block,
            scope="StudioRepository.readLessonContent",
            tokens=(
                "'/studio/lessons/$id/content'",
                "_requiredEtagHeader(response, 'Studio lesson content read')",
                "StudioLessonContentRead.fromResponse",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            write_block,
            scope="StudioRepository.updateLessonContent",
            tokens=(
                "'/studio/lessons/$id/content'",
                "data: {'content_document': contentDocument.toJson()}",
                "Options(headers: {'If-Match': contentToken})",
                "_requiredEtagHeader(response, 'Updated studio lesson content')",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            read_block + write_block,
            scope="StudioRepository.content_transport",
            tokens=("content_markdown", "contentMarkdown", "markdown"),
        )
    )


def test_backend_content_route_schema_and_validation_use_document_authority() -> None:
    routes_source = read_repo_text(REPO_ROOT, "backend/app/routes/studio.py")
    schemas_source = read_repo_text(REPO_ROOT, "backend/app/schemas/__init__.py")
    route_block = python_decorated_function_block(
        routes_source, "update_lesson_content"
    )

    assert_no_findings(
        missing_token_findings(
            route_block,
            scope="backend.routes.update_lesson_content",
            tokens=(
                "payload: schemas.StudioLessonContentUpdate",
                "content_document=payload.content_document",
                'request.headers.get("if-match")',
                'response.headers["ETag"]',
                "schemas.StudioLessonContent(**row",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            schemas_source,
            scope="backend.schemas.studio_lesson_content",
            tokens=(
                "class StudioLessonContentUpdate(BaseModel):",
                'model_config = ConfigDict(extra="forbid")',
                "content_document: Dict[str, Any]",
                "class StudioLessonContentRead(BaseModel):",
                "class StudioLessonContent(BaseModel):",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            route_block + schemas_source,
            scope="backend.route_schema_content_authority",
            tokens=("content_markdown", "contentMarkdown"),
        )
    )


def test_backend_validation_runtime_has_no_flutter_or_markdown_harness() -> None:
    paths = (
        "backend/app/utils/lesson_document_validator.py",
        "backend/app/services/courses_service.py",
        "backend/app/routes/studio.py",
        "backend/app/schemas/__init__.py",
    )
    findings = []
    for path in paths:
        findings.extend(
            forbidden_token_findings(
                read_repo_text(REPO_ROOT, path),
                scope=path,
                tokens=BACKEND_VALIDATION_FORBIDDEN_TOKENS,
            )
        )

    assert_no_findings(findings)


def test_course_editor_preview_gate_is_persisted_read_only() -> None:
    editor_source = read_repo_text(
        REPO_ROOT,
        "frontend/lib/features/studio/presentation/course_editor_page.dart",
    )
    preview_toggle = dart_source_block(
        editor_source,
        "Future<void> _setLessonPreviewMode(bool enabled)",
    )
    preview_loader = dart_source_block(
        editor_source,
        "Future<void> _loadPersistedLessonPreview({",
    )
    preview_media_loader = dart_source_block(
        editor_source,
        "Future<List<LessonDocumentPreviewMedia>> _readPersistedPreviewMedia(",
    )
    preview_builder = dart_source_block(
        editor_source,
        "Widget _buildLessonPreviewMode(BuildContext context)",
    )
    scoped_source = "\n".join(
        [preview_toggle, preview_loader, preview_media_loader, preview_builder]
    )

    assert_no_findings(
        missing_token_findings(
            preview_loader,
            scope="CourseEditor._loadPersistedLessonPreview",
            tokens=(
                "readLessonContent",
                "_readPersistedPreviewMedia(content)",
                "_lessonPreviewDocument = content.contentDocument",
                "preview.source.authority=backend_read",
                "persisted_only=true",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            preview_builder,
            scope="CourseEditor._buildLessonPreviewMode",
            tokens=(
                "LessonDocumentPreview",
                "document: previewDocument",
                "media: previewMedia",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            scoped_source,
            scope="CourseEditor.preview_authority",
            tokens=(
                "_lessonPreviewDocument = _lessonDocument",
                "document: _lessonDocument",
                "fetchLessonMediaPreviews",
                "/api/lesson-media/previews",
                "updateLessonContent(",
                "uploadLessonMedia(",
                "deleteLessonMedia(",
                "reorderLessonMedia(",
                "content_markdown",
                "contentMarkdown",
            ),
        )
    )


def test_media_block_editor_regression_gate_is_top_inserted_and_document_ordered() -> None:
    course_editor = read_repo_text(
        REPO_ROOT,
        "frontend/lib/features/studio/presentation/course_editor_page.dart",
    )
    document_editor = read_repo_text(
        REPO_ROOT,
        "frontend/lib/editor/document/lesson_document_editor.dart",
    )
    document_model = read_repo_text(
        REPO_ROOT,
        "frontend/lib/editor/document/lesson_document.dart",
    )

    insert_block = dart_source_block(
        course_editor, "void _insertMediaBlockIntoDocument({"
    )
    move_block = dart_source_block(document_editor, "void _moveBlock(")

    assert_no_findings(
        missing_token_findings(
            insert_block,
            scope="CourseEditor._insertMediaBlockIntoDocument",
            tokens=(
                "const insertionIndex = 0;",
                "_lessonDocument.insertMedia(",
                "insertionIndex,",
                "_lessonDocumentInsertionIndex = 1;",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            insert_block,
            scope="CourseEditor.media_insert_not_top",
            tokens=(
                "_lessonDocument.blocks.length,",
                "_resolvedLessonDocumentInsertionIndex();",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            document_editor,
            scope="LessonDocumentEditor.position_and_move_controls",
            tokens=(
                "media = const <LessonDocumentPreviewMedia>[]",
                "_mediaFileName",
                "_mediaTypeLabel",
                "fileName,",
                "mediaTypeLabel,",
                "onInsertionIndexChanged",
                "int insertionIndex(LessonDocument document)",
                "lesson_document_media_move_up_",
                "lesson_document_media_move_down_",
                "Flytta media upp",
                "Flytta media ned",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            move_block,
            scope="LessonDocumentEditor._moveBlock",
            tokens=(
                "widget.document.moveBlock(blockIndex, targetIndex)",
                "nextTarget.insertionIndex(next)",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            document_model,
            scope="LessonDocument.moveBlock_primitives",
            tokens=(
                "LessonDocument moveBlock(int fromIndex, int toIndex)",
                "LessonDocument moveBlockUp(int index)",
                "LessonDocument moveBlockDown(int index)",
            ),
        )
    )


def test_media_block_user_facing_no_leak_regression_gate() -> None:
    document_editor = read_repo_text(
        REPO_ROOT,
        "frontend/lib/editor/document/lesson_document_editor.dart",
    )
    course_editor = read_repo_text(
        REPO_ROOT,
        "frontend/lib/features/studio/presentation/course_editor_page.dart",
    )
    learner_page = read_repo_text(
        REPO_ROOT,
        "frontend/lib/features/courses/presentation/lesson_page.dart",
    )

    assert_no_findings(
        missing_token_findings(
            document_editor,
            scope="LessonDocumentEditor.safe_media_copy",
            tokens=("_mediaFileName", "_mediaTypeLabel", "Namnlös fil"),
        )
    )
    assert_no_findings(
        missing_token_findings(
            course_editor,
            scope="CourseEditor.safe_preview_media_label",
            tokens=("_safeLessonPreviewMediaLabel(media.originalName)",),
        )
    )
    assert_no_findings(
        missing_token_findings(
            learner_page,
            scope="Learner.safe_media_labels",
            tokens=("Lektionsljud", "Lektionsvideo", "Lektionsfil"),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            document_editor,
            scope="LessonDocumentEditor.user_facing_media_no_leak",
            tokens=(
                "Media: ${block.mediaType}",
                "Media saknas: ${block.mediaType}",
                "block.lessonMediaId,",
                "'Status: $state'",
                "Infogad media\\nFlytta blocket med pilarna.",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            course_editor,
            scope="CourseEditor.preview_media_label_no_asset_id",
            tokens=("label: media.originalName ?? media.mediaAssetId",),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            learner_page,
            scope="Learner.media_label_no_asset_id",
            tokens=(
                "label: item.mediaAssetId",
                "final mediaAssetId = item.mediaAssetId?.trim();",
                "return mediaAssetId;",
            ),
        )
    )


def test_frontend_governed_media_paths_do_not_construct_legacy_preview_urls() -> None:
    paths = (
        "frontend/lib/api/api_paths.dart",
        "frontend/lib/api/api_client.dart",
        "frontend/lib/features/studio/data/studio_repository.dart",
        "frontend/lib/features/studio/data/studio_repository_lesson_media.dart",
        "frontend/lib/features/studio/presentation/course_editor_page.dart",
        "frontend/lib/features/studio/presentation/lesson_media_preview_cache.dart",
    )

    findings = []
    for path in paths:
        findings.extend(
            forbidden_token_findings(
                read_repo_text(REPO_ROOT, path),
                scope=path,
                tokens=FRONTEND_MEDIA_AUTHORITY_FORBIDDEN_TOKENS,
            )
        )

    assert_no_findings(findings)


def test_editor_only_markdown_quill_dependencies_stay_removed() -> None:
    pubspec = read_repo_text(REPO_ROOT, "frontend/pubspec.yaml")
    lockfile = read_repo_text(REPO_ROOT, "frontend/pubspec.lock")

    assert_no_findings(
        forbidden_regex_findings(
            pubspec + "\n" + lockfile,
            scope="frontend.pubspec",
            patterns=FORBIDDEN_DEPENDENCY_PATTERNS,
        )
    )
