import pytest
from fastapi import Response
from httpx import ASGITransport, AsyncClient

from app.main import app, fastapi_app


pytestmark = pytest.mark.anyio("asyncio")


async def test_cors_exposes_etag_header_to_browser_clients():
    async def etag_response(response: Response):
        response.headers["ETag"] = '"cors-test-etag"'
        return {"ok": True}

    original_routes = list(fastapi_app.router.routes)
    fastapi_app.add_api_route(
        "/__tests__/cors-etag",
        etag_response,
        methods=["GET"],
        include_in_schema=False,
    )

    transport = ASGITransport(app=app, raise_app_exceptions=False)
    try:
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            response = await client.get(
                "/__tests__/cors-etag",
                headers={"Origin": "https://aveli.app"},
            )
    finally:
        fastapi_app.router.routes[:] = original_routes
        fastapi_app.openapi_schema = None

    assert response.status_code == 200
    assert response.headers.get("etag") == '"cors-test-etag"'
    assert response.headers.get("access-control-allow-origin") == "https://aveli.app"
    assert response.headers.get("access-control-allow-credentials") == "true"
    assert response.headers.get("access-control-expose-headers") == "ETag"


async def test_cors_header_present_on_error():
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.get(
            "/non-existent-route",
            headers={"Origin": "https://aveli.app"},
        )

    assert response.status_code == 404
    assert response.headers.get("access-control-allow-origin") == "https://aveli.app"
    assert response.headers.get("access-control-allow-credentials") == "true"
    assert response.headers.get("access-control-allow-methods")
    assert response.headers.get("access-control-allow-headers")


async def test_cors_header_present_on_unauthorized_response():
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.get(
            "/courses/me",
            headers={"Origin": "https://aveli.app"},
        )

    assert response.status_code == 401
    assert response.headers.get("access-control-allow-origin") == "https://aveli.app"
    assert response.headers.get("access-control-allow-credentials") == "true"
    assert response.headers.get("access-control-allow-methods")
    assert response.headers.get("access-control-allow-headers")


async def test_cors_header_present_on_internal_server_error():
    async def explode():
        raise RuntimeError("boom")

    original_routes = list(fastapi_app.router.routes)
    fastapi_app.add_api_route(
        "/__tests__/cors-boom",
        explode,
        methods=["GET"],
        include_in_schema=False,
    )

    transport = ASGITransport(app=app, raise_app_exceptions=False)
    try:
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            response = await client.get(
                "/__tests__/cors-boom",
                headers={"Origin": "https://aveli.app"},
            )
    finally:
        fastapi_app.router.routes[:] = original_routes
        fastapi_app.openapi_schema = None

    assert response.status_code == 500
    assert response.headers.get("access-control-allow-origin") == "https://aveli.app"
    assert response.headers.get("access-control-allow-credentials") == "true"
    assert response.headers.get("access-control-allow-methods")
    assert response.headers.get("access-control-allow-headers")
