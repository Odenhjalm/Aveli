import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


pytestmark = pytest.mark.anyio("asyncio")


async def test_auth_login_preflight_allows_production_origin():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.options(
            "/auth/login",
            headers={
                "Origin": "https://aveli.app",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )

    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "https://aveli.app"
    assert response.headers.get("access-control-allow-credentials") == "true"
    assert response.headers.get("access-control-allow-methods")
    assert response.headers.get("access-control-allow-headers")


async def test_auth_login_preflight_allows_localhost_origin_with_dynamic_port():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.options(
            "/auth/login",
            headers={
                "Origin": "http://localhost:51829",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )

    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:51829"
    assert response.headers.get("access-control-allow-credentials") == "true"
    assert response.headers.get("access-control-allow-methods")
    assert response.headers.get("access-control-allow-headers")


async def test_auth_login_preflight_allows_loopback_origin_with_dynamic_port():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.options(
            "/auth/login",
            headers={
                "Origin": "http://127.0.0.1:51829",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )

    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://127.0.0.1:51829"
    assert response.headers.get("access-control-allow-credentials") == "true"
    assert response.headers.get("access-control-allow-methods")
    assert response.headers.get("access-control-allow-headers")
