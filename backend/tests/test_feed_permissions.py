import uuid

import pytest


pytestmark = [
    pytest.mark.anyio("asyncio"),
    pytest.mark.skip(
        reason="legacy quarantine: /feed is not mounted in canonical runtime; see test_unmounted_surface_guardrails.py"
    ),
]


async def test_feed_requires_auth(async_client):
    resp = await async_client.get('/feed')
    assert resp.status_code == 401


async def test_feed_returns_seeded_items(async_client):
    email = f"feed_{uuid.uuid4().hex[:6]}@example.com"
    password = 'Passw0rd!'
    register_resp = await async_client.post(
        '/auth/register',
        json={
            'email': email,
            'password': password,
            'display_name': 'Feed User',
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()

    resp = await async_client.get(
        '/feed',
        headers={'Authorization': f"Bearer {tokens['access_token']}"},
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert 'items' in payload and isinstance(payload['items'], list)
