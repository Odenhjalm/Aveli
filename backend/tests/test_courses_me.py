import uuid

import pytest


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

    initial = await async_client.get("/courses/me", headers=headers)
    assert initial.status_code == 200, initial.text
    assert initial.json().get("items") == []

    catalog = await async_client.get(
        "/courses",
        headers=headers,
        params={"free_intro": True, "limit": 1},
    )
    assert catalog.status_code == 200, catalog.text
    intro_items = catalog.json().get("items") or []
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
    assert enrolled_course["is_free_intro"] is True
