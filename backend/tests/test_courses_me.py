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
async def test_courses_me_returns_enrolled_courses(async_client):
    # In clean Supabase there may be no seeded courses; ensure endpoint shape works.
    register = await async_client.post(
        "/auth/register",
        json={
            "email": f"me_{uuid.uuid4().hex[:8]}@example.com",
            "password": "Intro123!",
            "display_name": "Course QA",
        },
    )
    assert register.status_code == 201, register.text
    token = register.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    me = await async_client.get("/profiles/me", headers=headers)
    assert me.status_code == 200, me.text
    await _grant_app_entry(async_client, headers, str(me.json()["user_id"]))

    resp = await async_client.get("/courses/me", headers=headers)
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    items = payload.get("items", [])
    assert isinstance(items, list)


@pytest.mark.anyio("asyncio")
async def test_courses_me_updates_after_free_intro_enrollment(async_client):
    email = f"free_intro_{uuid.uuid4().hex[:8]}@example.com"

    register = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": "Intro123!",
            "display_name": "Intro QA",
        },
    )
    assert register.status_code == 201, register.text
    token = register.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    me = await async_client.get("/profiles/me", headers=headers)
    assert me.status_code == 200, me.text
    user_id = str(me.json()["user_id"])
    await _grant_app_entry(async_client, headers, user_id)

    initial = await async_client.get("/courses/me", headers=headers)
    assert initial.status_code == 200, initial.text
    assert initial.json().get("items") == []

    catalog = await async_client.get(
        "/courses",
        headers=headers,
        params={"limit": 100},
    )
    assert catalog.status_code == 200, catalog.text
    intro_items = [
        item
        for item in (catalog.json().get("items") or [])
        if item.get("group_position") == 0
    ]
    if not intro_items:
        pytest.skip("No free intro courses available in clean Supabase dataset")
    course = intro_items[0]

    enroll = await async_client.post(
        f"/courses/{course['id']}/enroll", headers=headers
    )
    assert enroll.status_code == 200, enroll.text
    assert enroll.json().get("enrolled") is True

    mine = await async_client.get("/courses/me", headers=headers)
    assert mine.status_code == 200, mine.text
    courses = mine.json().get("items") or []
    assert any(row["id"] == course["id"] for row in courses)

    enrolled_course = next(row for row in courses if row["id"] == course["id"])
    assert enrolled_course["title"] == course["title"]
    assert enrolled_course["slug"] == course["slug"]
    assert enrolled_course["group_position"] == 0
