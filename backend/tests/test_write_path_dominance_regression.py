from __future__ import annotations

import inspect
import re
from pathlib import Path

from app.main import app
from app.repositories import courses as courses_repo
from app.routes import studio
from app.services import courses_service


REPO_ROOT = Path(__file__).resolve().parents[2]


def _route_method_pairs() -> set[tuple[str, str]]:
    pairs: set[tuple[str, str]] = set()
    for route in app.routes:
        path = getattr(route, "path", None)
        methods = getattr(route, "methods", None)
        if not path or not methods:
            continue
        for method in methods:
            if method not in {"HEAD", "OPTIONS"}:
                pairs.add((str(method).upper(), str(path)))
    return pairs


def _allowed_preview_projection_routes() -> set[tuple[str, str]]:
    return {
        ("GET", "/api/lesson-media/{lesson_id}/{lesson_media_id}/preview"),
        ("POST", "/api/lesson-media/previews"),
        ("POST", "/api/media/previews"),
    }


def _source_block(source: str, needle: str) -> str:
    try:
        start = source.index(needle)
    except ValueError as exc:
        raise AssertionError(f"Missing source block: {needle}") from exc

    body_match = re.search(r"\)\s*(?:async\s*)?\{", source[start:])
    if body_match is None:
        raise AssertionError(f"Missing opening brace for source block: {needle}")
    opening = start + body_match.end() - 1

    depth = 0
    for index in range(opening, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[opening : index + 1]

    raise AssertionError(f"Unterminated source block: {needle}")


def test_noncanonical_write_routes_cannot_regain_dominance() -> None:
    route_pairs = _route_method_pairs()

    forbidden = {
        ("POST", "/studio/lessons"),
        ("PATCH", "/studio/lessons/{lesson_id}"),
        ("POST", "/api/lesson-media/{lesson_id}/upload-url"),
        ("POST", "/api/lesson-media/{lesson_id}/{lesson_media_id}/complete"),
        ("PATCH", "/api/lesson-media/{lesson_id}/reorder"),
        ("DELETE", "/api/lesson-media/{lesson_id}/{lesson_media_id}"),
        ("POST", "/studio/lessons/{lesson_id}/media/presign"),
        ("POST", "/studio/lessons/{lesson_id}/media/complete"),
        ("POST", "/studio/lessons/{lesson_id}/media"),
        ("DELETE", "/studio/media/{media_id}"),
        ("PATCH", "/studio/lessons/{lesson_id}/media/reorder"),
        ("PATCH", "/admin/teachers/{teacher_id}/priority"),
        ("DELETE", "/admin/teachers/{teacher_id}/priority"),
    }

    assert forbidden.isdisjoint(route_pairs)
    allowed_api_media_routes = {
        ("POST", "/api/media/profile-avatar/init"),
    }
    assert not any(
        (method, path) not in allowed_api_media_routes
        and (path == "/api/media" or path.startswith("/api/media/"))
        for method, path in route_pairs
    )


def test_studio_courses_read_route_is_mounted_exactly_once() -> None:
    matches = [
        route
        for route in app.routes
        if getattr(route, "path", None) == "/studio/courses"
        and "GET" in getattr(route, "methods", set())
    ]

    assert len(matches) == 1


def test_canonical_write_routes_remain_mounted() -> None:
    route_pairs = _route_method_pairs()

    assert ("POST", "/courses/lessons/{lesson_id}/complete") in route_pairs
    assert ("POST", "/studio/courses") in route_pairs
    assert ("PATCH", "/studio/courses/{course_id}") in route_pairs
    assert ("PUT", "/studio/courses/{course_id}/drip-authoring") in route_pairs
    assert ("POST", "/studio/courses/{course_id}/reorder") in route_pairs
    assert ("POST", "/studio/courses/{course_id}/move-family") in route_pairs
    assert ("DELETE", "/studio/courses/{course_id}") in route_pairs
    assert ("PATCH", "/studio/course-families/{course_family_id}") in route_pairs
    assert ("DELETE", "/studio/course-families/{course_family_id}") in route_pairs
    assert ("POST", "/studio/courses/{course_id}/lessons") in route_pairs
    assert ("PATCH", "/studio/lessons/{lesson_id}/structure") in route_pairs
    assert ("PATCH", "/studio/lessons/{lesson_id}/content") in route_pairs
    assert ("DELETE", "/studio/lessons/{lesson_id}") in route_pairs
    assert (
        "POST",
        "/api/lessons/{lesson_id}/media-assets/upload-url",
    ) in route_pairs
    assert (
        "POST",
        "/api/media-assets/{media_asset_id}/upload-completion",
    ) in route_pairs
    assert ("POST", "/api/lessons/{lesson_id}/media-placements") in route_pairs
    assert ("GET", "/api/media-placements/{lesson_media_id}") in route_pairs
    assert ("PATCH", "/api/lessons/{lesson_id}/media-placements/reorder") in route_pairs
    assert ("DELETE", "/api/media-placements/{lesson_media_id}") in route_pairs


def test_media_placement_integrity_aggregate_gate() -> None:
    route_pairs = _route_method_pairs()
    delete_route_source = inspect.getsource(
        studio.canonical_delete_lesson_media_placement
    )

    guard_index = delete_route_source.index(
        "courses_service.lesson_content_references_lesson_media"
    )
    conflict_index = delete_route_source.index("status.HTTP_409_CONFLICT")
    delete_index = delete_route_source.index("courses_repo.delete_lesson_media")

    assert ("DELETE", "/api/media-placements/{lesson_media_id}") in route_pairs
    assert guard_index < conflict_index < delete_index
    assert "Lesson media is still referenced by lesson content" in delete_route_source

    preview_routes = {
        (method, path) for method, path in route_pairs if "preview" in path
    }
    assert preview_routes - _allowed_preview_projection_routes() == set()


def test_preview_mode_routes_do_not_add_mutation_surface() -> None:
    preview_routes = {
        (method, path) for method, path in _route_method_pairs() if "preview" in path
    }

    assert preview_routes.issubset(_allowed_preview_projection_routes())


def test_application_code_does_not_write_runtime_media_directly() -> None:
    write_patterns = (
        re.compile(r"\binsert\s+into\s+app\.runtime_media\b", re.IGNORECASE),
        re.compile(r"\bupdate\s+app\.runtime_media\b", re.IGNORECASE),
        re.compile(r"\bdelete\s+from\s+app\.runtime_media\b", re.IGNORECASE),
        re.compile(r"\bruntime_media\s+set\b", re.IGNORECASE),
    )

    offenders: list[tuple[str, str]] = []
    for path in (REPO_ROOT / "backend" / "app").rglob("*.py"):
        text = path.read_text(encoding="utf-8")
        for pattern in write_patterns:
            if pattern.search(text):
                offenders.append((str(path.relative_to(REPO_ROOT)), pattern.pattern))

    assert offenders == []


def test_course_editor_preview_mode_uses_persisted_read_projection_only() -> None:
    editor_source = (
        REPO_ROOT
        / "frontend"
        / "lib"
        / "features"
        / "studio"
        / "presentation"
        / "course_editor_page.dart"
    ).read_text(encoding="utf-8")
    preview_toggle = _source_block(
        editor_source,
        "Future<void> _setLessonPreviewMode(bool enabled)",
    )
    preview_loader = _source_block(
        editor_source,
        "Future<void> _loadPersistedLessonPreview({",
    )
    preview_media_loader = _source_block(
        editor_source,
        "Future<List<LessonDocumentPreviewMedia>> _readPersistedPreviewMedia(",
    )
    preview_builder_start = editor_source.index(
        "Widget _buildLessonPreviewMode(BuildContext context)"
    )
    preview_builder = editor_source[
        preview_builder_start : preview_builder_start + 5000
    ]

    assert "_loadPersistedLessonPreview" in preview_toggle
    for required in (
        "readLessonContent",
        "content.contentDocument",
        "_readPersistedPreviewMedia(content)",
        "_lessonPreviewDocument = content.contentDocument",
        "preview.source.authority=backend_read",
    ):
        assert required in preview_loader
    for required in (
        "_persistedPreviewMediaIds(content)",
        "fetchLessonMediaPlacements(mediaIds)",
        "_previewMediaFromPlacement",
    ):
        assert required in preview_media_loader
    for required in (
        "LessonDocumentPreview",
        "document: previewDocument",
        "media: previewMedia",
    ):
        assert required in preview_builder

    forbidden_authority_tokens = (
        "_syncLessonPreviewMarkdownFromController",
        "_serializeLessonPreviewMarkdownFromController",
        "_currentLessonPreviewMarkdown",
        "editorDeltaToPassivePreviewMarkdown",
        "fetchLessonMediaPreviews",
        "/api/lesson-media/previews",
        "/api/lesson-media/$lessonId/$lessonMediaId/preview",
        "fetchCourseMeta(",
        "updateLessonContent(",
        "updateLessonStructure(",
        "uploadLessonMedia(",
        "deleteLessonMedia(",
        "reorderLessonMedia(",
        "updateCourse(",
        "uploadCourseCover(",
        "clearCourseCover(",
        "_lessonDocument",
        "_lessonMedia",
    )
    scoped_sources = {
        "_setLessonPreviewMode": preview_toggle,
        "_loadPersistedLessonPreview": preview_loader,
        "_readPersistedPreviewMedia": preview_media_loader,
        "_buildLessonPreviewMode": preview_builder,
    }

    offenders: list[tuple[str, str]] = []
    for name, source in scoped_sources.items():
        for token in forbidden_authority_tokens:
            if token in source:
                offenders.append((name, token))

    assert offenders == []


def test_course_editor_media_and_cta_authoring_uses_document_nodes_only() -> None:
    editor_source = (
        REPO_ROOT
        / "frontend"
        / "lib"
        / "features"
        / "studio"
        / "presentation"
        / "course_editor_page.dart"
    ).read_text(encoding="utf-8")
    media_insert = _source_block(
        editor_source,
        "void _insertMediaBlockIntoDocument({",
    )
    media_dispatch = _source_block(
        editor_source,
        "bool _insertMediaIntoLesson(",
    )
    cta_insert = _source_block(editor_source, "Future<void> _insertMagicLink() async")

    assert "_lessonDocument.insertMedia" in media_insert
    assert "_lessonDocument.insertCta" in cta_insert
    assert all(
        token in media_dispatch
        for token in (
            "_insertImageIntoLesson",
            "_insertDocumentIntoLesson",
            "_insertVideoIntoLesson",
            "_insertAudioIntoLesson",
        )
    )

    forbidden_tokens = (
        "!image(",
        "!audio(",
        "!video(",
        "!document(",
        "lessonMediaIdFromEmbedValue",
        "AudioBlockEmbed",
        "videoBlockEmbedValueFromLessonMedia",
        "_insertDocumentLinkIntoLesson",
        "replaceTextWithEmbeds",
        "insertText(",
    )
    scoped_sources = {
        "_insertMediaBlockIntoDocument": media_insert,
        "_insertMediaIntoLesson": media_dispatch,
        "_insertMagicLink": cta_insert,
    }
    offenders: list[tuple[str, str]] = []
    for name, source in scoped_sources.items():
        for token in forbidden_tokens:
            if token in source:
                offenders.append((name, token))

    assert offenders == []


def test_learner_lesson_rendering_uses_document_surface_only() -> None:
    lesson_source = (
        REPO_ROOT
        / "frontend"
        / "lib"
        / "features"
        / "courses"
        / "presentation"
        / "lesson_page.dart"
    ).read_text(encoding="utf-8")
    repository_source = (
        REPO_ROOT
        / "frontend"
        / "lib"
        / "features"
        / "courses"
        / "data"
        / "courses_repository.dart"
    ).read_text(encoding="utf-8")
    service_source = (
        REPO_ROOT / "backend" / "app" / "services" / "courses_service.py"
    ).read_text(encoding="utf-8")
    schema_source = (
        REPO_ROOT / "backend" / "app" / "schemas" / "__init__.py"
    ).read_text(encoding="utf-8")

    for required in (
        "LearnerLessonContentRenderer(",
        "required this.document",
        "LessonPageRenderer(",
        "LessonDocumentPreview(",
        "mediaBuilder:",
        "contentDocument",
    ):
        assert required in lesson_source
    for required in (
        "LessonDocument.fromJson",
        "_rejectLegacyLessonContentFields",
        "_requiredField(payload, 'content_document')",
    ):
        assert required in repository_source
    for required in (
        '"content_document": content_document',
        'row.get("content_document")',
    ):
        assert required in service_source
    assert "content_document: Dict[str, Any]" in schema_source

    forbidden_lesson_tokens = (
        "markdown_to_editor",
        "flutter_quill",
        "FlutterQuillEmbeds",
        "PreparedLessonRenderContent",
        "prepareLessonRenderContent",
        "contentMarkdown",
        "content_markdown",
        "LessonQuill",
        "markdown:",
    )
    offenders = [token for token in forbidden_lesson_tokens if token in lesson_source]

    assert offenders == []


def test_legacy_markdown_quill_authority_removed_from_rebuilt_editor_paths() -> None:
    removed_paths = [
        REPO_ROOT
        / "frontend"
        / "lib"
        / "editor"
        / "adapter"
        / "editor_to_markdown.dart",
        REPO_ROOT
        / "frontend"
        / "lib"
        / "editor"
        / "adapter"
        / "markdown_to_editor.dart",
        REPO_ROOT
        / "frontend"
        / "lib"
        / "editor"
        / "adapter"
        / "lesson_markdown_validation.dart",
        REPO_ROOT
        / "frontend"
        / "lib"
        / "editor"
        / "guardrails"
        / "lesson_markdown_integrity_guard.dart",
        REPO_ROOT
        / "frontend"
        / "lib"
        / "editor"
        / "normalization"
        / "quill_delta_normalizer.dart",
        REPO_ROOT
        / "frontend"
        / "lib"
        / "editor"
        / "session"
        / "editor_operation_controller.dart",
        REPO_ROOT / "frontend" / "lib" / "editor" / "session" / "editor_session.dart",
        REPO_ROOT
        / "frontend"
        / "lib"
        / "shared"
        / "utils"
        / "lesson_content_pipeline.dart",
        REPO_ROOT / "frontend" / "tool" / "lesson_markdown_roundtrip.dart",
        REPO_ROOT / "frontend" / "tool" / "lesson_markdown_roundtrip_harness_test.dart",
        REPO_ROOT / "backend" / "app" / "utils" / "lesson_markdown_validator.py",
    ]

    assert [
        str(path.relative_to(REPO_ROOT)) for path in removed_paths if path.exists()
    ] == []

    pubspec = (REPO_ROOT / "frontend" / "pubspec.yaml").read_text(encoding="utf-8")
    course_editor = (
        REPO_ROOT
        / "frontend"
        / "lib"
        / "features"
        / "studio"
        / "presentation"
        / "course_editor_page.dart"
    ).read_text(encoding="utf-8")
    main_source = (REPO_ROOT / "frontend" / "lib" / "main.dart").read_text(
        encoding="utf-8"
    )
    publish_query_source = inspect.getsource(courses_repo.list_course_publish_lessons)
    service_source = inspect.getsource(courses_service._derive_course_content_ready)

    for token in (
        "flutter_quill",
        "flutter_quill_extensions",
        "markdown_quill",
        "markdown_widget",
    ):
        assert token not in pubspec
    for token in (
        "flutter_quill",
        "QuillController",
        "quill.Document",
        "EditorSession",
        "EditorOperationQuillController",
        "editor_test_bridge",
        "content_markdown",
        "markdown_to_editor",
        "editor_to_markdown",
    ):
        assert token not in course_editor
    assert "FlutterQuillLocalizations" not in main_source
    assert "content_document" in publish_query_source
    assert "content_markdown" not in publish_query_source
    for token in (
        "lesson_content_utils",
        "normalize_lesson_markdown_for_storage",
        "_LESSON_MEDIA_TOKEN_PATTERN",
        "validate_lesson_markdown",
        "markdown=",
    ):
        assert token not in service_source


def test_governed_frontend_media_paths_use_backend_authored_media_objects() -> None:
    scoped_paths = list(
        (REPO_ROOT / "frontend" / "lib" / "features" / "studio" / "data").rglob(
            "*.dart"
        )
    )
    scoped_paths.append(
        REPO_ROOT
        / "frontend"
        / "lib"
        / "features"
        / "studio"
        / "presentation"
        / "lesson_media_preview_cache.dart"
    )

    forbidden_tokens = (
        "ApiPaths.mediaAttach",
        "ApiPaths.mediaUploadUrl",
        "ApiPaths.mediaComplete",
        "/api/media/attach",
        "/api/media/upload-url",
        "/api/media/complete",
        "/api/lesson-media/$lessonId/upload-url",
        "/api/lesson-media/$lessonId/$lessonMediaId/complete",
        "/api/lesson-media/$lessonId/$lessonMediaId",
        "/api/lesson-media/$lessonId/reorder",
        "preview_ready",
        "original_name",
        "resolved_preview_url",
    )

    offenders: list[tuple[str, str]] = []
    for path in scoped_paths:
        text = path.read_text(encoding="utf-8")
        for token in forbidden_tokens:
            if token in text:
                offenders.append((str(path.relative_to(REPO_ROOT)), token))

    assert offenders == []
