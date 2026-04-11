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
    }

    assert forbidden.isdisjoint(route_pairs)
    assert not any(
        path == "/api/media" or path.startswith("/api/media/")
        for _, path in route_pairs
    )


def test_canonical_write_routes_remain_mounted() -> None:
    route_pairs = _route_method_pairs()

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
