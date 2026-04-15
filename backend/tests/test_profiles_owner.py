import uuid

import pytest

from .utils import auth_header, register_auth_user


pytestmark = pytest.mark.anyio("asyncio")


async def _create_profile(
    async_client,
    *,
    access_token: str,
    display_name: str,
    bio: str | None = None,
) -> dict:
    payload = {"display_name": display_name}
    if bio is not None:
        payload["bio"] = bio
    resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(access_token),
        json=payload,
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


async def test_profiles_me_limits_updates_to_the_authenticated_user(async_client):
    password = "Passw0rd!"
    owner = await register_auth_user(
        async_client,
        email=f"owner_{uuid.uuid4().hex[:6]}@example.com",
        password=password,
        display_name="Owner",
    )
    other = await register_auth_user(
        async_client,
        email=f"other_{uuid.uuid4().hex[:6]}@example.com",
        password=password,
        display_name="Other",
    )
    await _create_profile(
        async_client,
        access_token=owner["access_token"],
        display_name="Owner",
    )
    await _create_profile(
        async_client,
        access_token=other["access_token"],
        display_name="Other",
    )

    patch_resp = await async_client.patch(
        "/profiles/me",
        headers=auth_header(owner["access_token"]),
        json={"display_name": "Owner Updated", "bio": "Canonical bio"},
    )
    assert patch_resp.status_code == 200, patch_resp.text
    assert patch_resp.json()["display_name"] == "Owner Updated"
    assert patch_resp.json()["bio"] == "Canonical bio"

    owner_profile = await async_client.get(
        "/profiles/me",
        headers=auth_header(owner["access_token"]),
    )
    assert owner_profile.status_code == 200, owner_profile.text
    assert owner_profile.json()["display_name"] == "Owner Updated"
    assert owner_profile.json()["bio"] == "Canonical bio"

    other_profile = await async_client.get(
        "/profiles/me",
        headers=auth_header(other["access_token"]),
    )
    assert other_profile.status_code == 200, other_profile.text
    assert other_profile.json()["display_name"] == "Other"
    assert other_profile.json()["bio"] is None


async def test_profiles_me_is_projection_only_and_excludes_authority_fields(
    async_client,
):
    user = await register_auth_user(
        async_client,
        email=f"profile_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Projection User",
    )
    await _create_profile(
        async_client,
        access_token=user["access_token"],
        display_name="Projection User",
    )

    me_resp = await async_client.get(
        "/profiles/me",
        headers=auth_header(user["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text

    payload = me_resp.json()
    assert set(payload) == {
        "user_id",
        "email",
        "display_name",
        "bio",
        "photo_url",
        "avatar_media_id",
        "created_at",
        "updated_at",
    }


async def test_profiles_me_patch_rejects_non_projection_authority_fields(async_client):
    user = await register_auth_user(
        async_client,
        email=f"forbidden_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Forbidden Fields",
    )
    await _create_profile(
        async_client,
        access_token=user["access_token"],
        display_name="Forbidden Fields",
    )

    resp = await async_client.patch(
        "/profiles/me",
        headers=auth_header(user["access_token"]),
        json={
            "display_name": "Allowed",
            "photo_url": "https://example.com/avatar.png",
            "onboarding_state": "completed",
            "role_v2": "teacher",
            "is_admin": True,
        },
    )
    assert resp.status_code == 422, resp.text

    payload = resp.json()
    assert payload["status"] == "error"
    assert payload["error_code"] == "validation_error"
    assert payload["message"] == "Begaran innehaller ogiltiga eller saknade falt."
    assert "detail" not in payload
    assert "error" not in payload

    field_errors = payload["field_errors"]
    assert {entry["field"] for entry in field_errors} == {
        "photo_url",
        "onboarding_state",
        "role_v2",
        "is_admin",
    }
    assert {entry["error_code"] for entry in field_errors} == {"extra_forbidden"}
