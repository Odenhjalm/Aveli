import pytest

from app.main import app


pytestmark = pytest.mark.anyio("asyncio")


def _route_inventory() -> set[tuple[str, str]]:
    return {
        (route.path, method)
        for route in app.routes
        for method in getattr(route, "methods", set())
        if method not in {"HEAD", "OPTIONS"}
    }


def test_legacy_upload_and_avatar_routes_are_not_mounted():
    inventory = _route_inventory()

    forbidden = {
        ("/profile/avatar/init", "POST"),
        ("/profile/avatar/attach", "POST"),
        ("/api/profile/avatar/init", "POST"),
        ("/profiles/me/avatar", "POST"),
        ("/api/upload/profile", "POST"),
        ("/upload/profile", "POST"),
        ("/api/upload/course-media", "POST"),
        ("/upload/course-media", "POST"),
        ("/api/upload/lesson-image", "POST"),
        ("/upload/lesson-image", "POST"),
        ("/upload/public-media", "POST"),
    }

    assert inventory.isdisjoint(forbidden)


async def test_removed_upload_routes_fail_closed_as_not_found(async_client):
    forbidden_paths = (
        "/profile/avatar/init",
        "/profile/avatar/attach",
        "/api/profile/avatar/init",
        "/profiles/me/avatar",
        "/api/upload/profile",
        "/upload/profile",
        "/api/upload/course-media",
        "/upload/course-media",
        "/api/upload/lesson-image",
        "/upload/lesson-image",
        "/upload/public-media",
    )

    for path in forbidden_paths:
        response = await async_client.post(path)
        assert response.status_code == 404, (path, response.text)
