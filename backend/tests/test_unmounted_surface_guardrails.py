from __future__ import annotations

import pytest

from app.main import app


pytestmark = pytest.mark.anyio("asyncio")


def _route_paths() -> set[str]:
    return {
        route.path
        for route in app.routes
        if getattr(route, "path", None)
    }


def _prefix_is_mounted(paths: set[str], prefix: str) -> bool:
    return any(path == prefix or path.startswith(f"{prefix}/") for path in paths)


def _schema_property_names(schema: object) -> set[str]:
    names: set[str] = set()
    if isinstance(schema, dict):
        properties = schema.get("properties")
        if isinstance(properties, dict):
            names.update(str(key) for key in properties)
        for value in schema.values():
            names.update(_schema_property_names(value))
    elif isinstance(schema, list):
        for value in schema:
            names.update(_schema_property_names(value))
    return names


def test_legacy_non_mounted_surfaces_remain_unmounted() -> None:
    paths = _route_paths()

    for prefix in (
        "/feed",
        "/community",
        "/media",
        "/api/upload",
        "/api/files",
        "/upload",
        "/sfu",
        "/services",
        "/studio/sessions",
    ):
        assert _prefix_is_mounted(paths, prefix) is False, prefix


def test_legacy_cover_authoring_routes_are_not_test_visible() -> None:
    paths = _route_paths()

    for path in paths:
        assert "/api/media/cover-" not in path


def test_legacy_media_listing_routes_are_hidden_from_openapi() -> None:
    paths = set(app.openapi().get("paths", {}))

    assert "/studio/lessons/{lesson_id}/media" not in paths
    assert "/api/lesson-media/{lesson_id}" not in paths
    assert "/api/lesson-media/{lesson_id}/{lesson_media_id}/preview" in paths
    assert "/api/lesson-media/previews" in paths


def test_mounted_openapi_media_schemas_exclude_forbidden_legacy_fields() -> None:
    forbidden = {
        "upload_url",
        "storage_path",
        "object_path",
        "signed_url",
        "download_url",
    }
    schemas = app.openapi().get("components", {}).get("schemas", {})

    assert _schema_property_names(schemas).isdisjoint(forbidden)


@pytest.mark.parametrize(
    ("method", "path", "kwargs"),
    [
        ("get", "/feed", {}),
        ("get", "/community/messages", {}),
        ("post", "/sfu/token", {"json": {}}),
        ("post", "/api/media/upload-url", {"json": {}}),
        ("post", "/api/media/complete", {"json": {}}),
        ("post", "/api/upload/course-media", {"json": {}}),
        ("post", "/upload/public-media", {"json": {}}),
        ("get", "/api/files/public-media/demo.png", {}),
        ("get", "/media/demo", {}),
        ("get", "/services", {}),
        ("post", "/studio/sessions", {"json": {}}),
    ],
)
async def test_legacy_non_mounted_surfaces_return_404(
    async_client,
    method: str,
    path: str,
    kwargs: dict[str, object],
) -> None:
    response = await getattr(async_client, method)(path, **kwargs)
    assert response.status_code == 404, response.text
