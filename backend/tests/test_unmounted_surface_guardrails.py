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


def test_legacy_non_mounted_surfaces_remain_unmounted() -> None:
    paths = _route_paths()

    for prefix in (
        "/feed",
        "/community",
        "/sfu",
        "/services",
        "/studio/sessions",
    ):
        assert _prefix_is_mounted(paths, prefix) is False, prefix


def test_legacy_cover_authoring_routes_are_not_test_visible() -> None:
    paths = _route_paths()

    for path in paths:
        assert "/api/media/cover-" not in path


@pytest.mark.parametrize(
    ("method", "path", "kwargs"),
    [
        ("get", "/feed", {}),
        ("get", "/community/messages", {}),
        ("post", "/sfu/token", {"json": {}}),
        ("post", "/api/media/upload-url", {"json": {}}),
        ("post", "/api/media/complete", {"json": {}}),
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
