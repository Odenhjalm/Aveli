import uuid

import pytest


@pytest.mark.anyio("asyncio")
async def test_home_audio_requires_auth(async_client):
    resp = await async_client.get("/home/audio")
    assert resp.status_code == 401


@pytest.mark.anyio("asyncio")
async def test_home_audio_returns_list(async_client):
    email = f"home_audio_{uuid.uuid4().hex[:6]}@example.com"
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": "Home Audio User",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()

    resp = await async_client.get(
        "/home/audio",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        params={"limit": 3},
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert "items" in payload and isinstance(payload["items"], list)
    assert len(payload["items"]) <= 3
    for item in payload["items"]:
        assert item.get("kind") == "audio"
