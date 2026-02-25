import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


pytestmark = pytest.mark.anyio("asyncio")


async def test_cors_preflight_allows_frontend_origin():
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
