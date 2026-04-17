from __future__ import annotations

from app.main import app


def _route_paths() -> set[str]:
    return {
        route.path
        for route in app.routes
        if getattr(route, "path", None)
    }


def test_sfu_surface_remains_unmounted() -> None:
    paths = _route_paths()

    assert not any(path == "/sfu" or path.startswith("/sfu/") for path in paths)


def test_sfu_livekit_webhook_surface_remains_unmounted() -> None:
    paths = _route_paths()

    assert "/sfu/webhooks/livekit" not in paths
