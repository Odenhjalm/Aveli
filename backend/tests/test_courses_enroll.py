import uuid

import pytest

from app import repositories


async def _grant_app_entry(async_client, headers: dict[str, str], user_id: str) -> None:
    onboarding_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=headers,
    )
    assert onboarding_resp.status_code == 200, onboarding_resp.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="test",
    )


@pytest.mark.anyio("asyncio")
async def test_enroll_free_intro_course_updates_my_courses(async_client):
    email = f"free_intro_{uuid.uuid4().hex[:8]}@example.com"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": "Intro123!",
            "display_name": "Free Intro User",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    access_token = register_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {access_token}"}

    profile_resp = await async_client.get("/profiles/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    await _grant_app_entry(async_client, headers, user_id)

    me_resp = await async_client.get("/courses/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    assert me_resp.json().get("items") == []

    catalog_resp = await async_client.get(
        "/courses",
        headers=headers,
        params={"limit": 100},
    )
    assert catalog_resp.status_code == 200, catalog_resp.text
    items = [
        item
        for item in (catalog_resp.json().get("items") or [])
        if item.get("group_position") == 0
    ]
    if not items:
        pytest.skip("No free intro courses available in clean Supabase dataset")
    course_id = items[0]["id"]

    enroll_resp = await async_client.post(
        f"/courses/{course_id}/enroll", headers=headers
    )
    assert enroll_resp.status_code == 200, enroll_resp.text
    payload = enroll_resp.json()
    assert payload.get("enrolled") is True

    me_after = await async_client.get("/courses/me", headers=headers)
    assert me_after.status_code == 200, me_after.text
    enrolled_ids = [row["id"] for row in me_after.json().get("items", [])]
    assert course_id in enrolled_ids
