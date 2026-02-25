import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


pytestmark = pytest.mark.anyio("asyncio")


async def test_cors_header_present_on_error():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.get(
            "/non-existent-route",
            headers={"Origin": "https://app.aveli.app"},
        )

    assert response.status_code == 404
    assert response.headers.get("access-control-allow-origin") == "https://app.aveli.app"


async def test_cors_preflight_courses_me():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.options(
            "/courses/me",
            headers={
                "Origin": "https://app.aveli.app",
                "Access-Control-Request-Method": "GET",
            },
        )

    assert response.status_code in (200, 204)
    assert response.headers.get("access-control-allow-origin") == "https://app.aveli.app"
