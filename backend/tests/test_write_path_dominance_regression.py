from __future__ import annotations

import re
from pathlib import Path

from app.main import app


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


def _source_block(source: str, needle: str) -> str:
    try:
        start = source.index(needle)
    except ValueError as exc:
        raise AssertionError(f"Missing source block: {needle}") from exc

    body_marker = ") async {"
    body_marker_index = source.find(body_marker, start)
    if body_marker_index >= 0:
        opening = body_marker_index + len(body_marker) - 1
    else:
        try:
            opening = source.index("{", start)
        except ValueError as exc:
            raise AssertionError(
                f"Missing opening brace for source block: {needle}"
            ) from exc

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


def test_preview_mode_routes_do_not_add_mutation_surface() -> None:
    preview_routes = {
        (method, path)
        for method, path in _route_method_pairs()
        if "preview" in path
    }

    allowed_projection_routes = {
        ("GET", "/api/lesson-media/{lesson_id}/{lesson_media_id}/preview"),
        ("POST", "/api/lesson-media/previews"),
        ("POST", "/api/media/previews"),
    }

    assert preview_routes.issubset(allowed_projection_routes)


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
    media_repo_source = (
        REPO_ROOT
        / "frontend"
        / "lib"
        / "features"
        / "studio"
        / "data"
        / "studio_repository_lesson_media.dart"
    ).read_text(encoding="utf-8")

    preview_toggle = _source_block(
        editor_source,
        "Future<void> _setLessonPreviewMode(bool enabled)",
    )
    preview_reader = _source_block(
        editor_source,
        "Future<_PersistedLessonPreviewSnapshot> _readPersistedLessonPreview({",
    )
    placement_reader = _source_block(
        media_repo_source,
        "Future<List<StudioLessonMediaItem>> fetchLessonMediaPlacements(",
    )

    assert "_readPersistedLessonPreview" in preview_toggle
    for required in (
        "readLessonContent",
        "fetchLessonMediaPlacements",
        "fetchCourseMeta",
        "content.contentMarkdown",
        "course.cover?.resolvedUrl",
    ):
        assert required in preview_reader
    assert "/api/media-placements/$lessonMediaId" in placement_reader

    forbidden_authority_tokens = (
        "_lessonPreviewMarkdown",
        "_syncLessonPreviewMarkdownFromController",
        "_serializeLessonPreviewMarkdownFromController",
        "_currentLessonPreviewMarkdown",
        "editorDeltaToPassivePreviewMarkdown",
        "previewMarkdown",
        "fetchLessonMediaPreviews",
        "/api/lesson-media/previews",
        "/api/lesson-media/$lessonId/$lessonMediaId/preview",
        "updateLessonContent(",
        "updateLessonStructure(",
        "uploadLessonMedia(",
        "deleteLessonMedia(",
        "reorderLessonMedia(",
        "updateCourse(",
        "uploadCourseCover(",
        "clearCourseCover(",
    )
    scoped_sources = {
        "_setLessonPreviewMode": preview_toggle,
        "_readPersistedLessonPreview": preview_reader,
        "fetchLessonMediaPlacements": placement_reader,
    }

    offenders: list[tuple[str, str]] = []
    for name, source in scoped_sources.items():
        for token in forbidden_authority_tokens:
            if token in source:
                offenders.append((name, token))

    assert offenders == []


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
