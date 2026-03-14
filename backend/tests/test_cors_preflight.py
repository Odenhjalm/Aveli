import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


pytestmark = pytest.mark.anyio("asyncio")


async def test_cors_preflight_allows_frontend_origin():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.options(
            "/missing-preflight-target",
            headers={
                "Origin": "https://app.aveli.app",
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )

    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "https://app.aveli.app"
    assert response.headers.get("access-control-allow-methods")
    assert response.headers.get("access-control-allow-headers")


async def test_lesson_image_preflight_allows_frontend_origin():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.options(
            "/api/upload/lesson-image",
            headers={
                "Origin": "https://app.aveli.app",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )

    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "https://app.aveli.app"
    assert response.headers.get("access-control-allow-methods")
    assert response.headers.get("access-control-allow-headers")
