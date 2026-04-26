import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


pytestmark = pytest.mark.anyio("asyncio")


def _cors_header_values(response, header_name: str) -> set[str]:
    raw = response.headers.get(header_name, "")
    return {value.strip().lower() for value in raw.split(",") if value.strip()}


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


async def test_upload_bytes_preflight_allows_put_and_upload_session_header():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.options(
            "/api/media-assets/00000000-0000-0000-0000-000000000001/upload-bytes",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "PUT",
                "Access-Control-Request-Headers": (
                    "authorization,content-type,x-aveli-upload-session"
                ),
            },
        )

    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"
    assert response.headers.get("access-control-allow-credentials") == "true"

    allowed_methods = _cors_header_values(response, "access-control-allow-methods")
    assert {"get", "post", "put", "options"}.issubset(allowed_methods)

    allowed_headers = _cors_header_values(response, "access-control-allow-headers")
    assert {"authorization", "content-type", "x-aveli-upload-session"}.issubset(
        allowed_headers
    )


async def test_upload_bytes_put_route_is_reachable_after_preflight():
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.put(
            "/api/media-assets/00000000-0000-0000-0000-000000000001/upload-bytes",
            content=b"upload-bytes",
            headers={
                "Origin": "http://localhost:3000",
                "Content-Type": "application/octet-stream",
                "X-Aveli-Upload-Session": "00000000-0000-0000-0000-000000000001",
            },
        )

    assert response.status_code == 401
    assert response.status_code not in {405, 503}
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"


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
