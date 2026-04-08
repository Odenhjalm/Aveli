from __future__ import annotations

import uuid

import pytest


pytestmark = pytest.mark.anyio


def _unique_email(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:10]}@example.com"


async def test_change_password_requires_current_password(async_client):
    email = _unique_email("change_password")
    current_password = "Secret123!"
    new_password = "Changed456!"

    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": current_password,
            "display_name": "Password User",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    access_token = tokens["access_token"]
    refresh_token = tokens["refresh_token"]
    headers = {"Authorization": f"Bearer {access_token}"}

    invalid_resp = await async_client.post(
        "/auth/change-password",
        headers=headers,
        json={
            "current_password": "Wrong123!",
            "new_password": new_password,
        },
    )
    assert invalid_resp.status_code == 400, invalid_resp.text
    assert invalid_resp.json()["detail"] == "invalid_current_password"

    change_resp = await async_client.post(
        "/auth/change-password",
        headers=headers,
        json={
            "current_password": current_password,
            "new_password": new_password,
        },
    )
    assert change_resp.status_code == 200, change_resp.text
    assert change_resp.json() == {
        "status": "password_changed",
        "reauth_required": True,
    }

    old_login = await async_client.post(
        "/auth/login",
        json={"email": email, "password": current_password},
    )
    assert old_login.status_code == 401, old_login.text

    new_login = await async_client.post(
        "/auth/login",
        json={"email": email, "password": new_password},
    )
    assert new_login.status_code == 200, new_login.text

    refresh_resp = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert refresh_resp.status_code == 401, refresh_resp.text
