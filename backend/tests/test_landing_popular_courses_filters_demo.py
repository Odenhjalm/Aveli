import uuid

import pytest

from app import db


pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(client, email: str, password: str, display_name: str) -> tuple[str, str]:
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    me_resp = await client.get("/auth/me", headers=auth_header(tokens["access_token"]))
    assert me_resp.status_code == 200, me_resp.text
    return tokens["access_token"], me_resp.json()["user_id"]


async def promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def cleanup_course(slug: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.courses WHERE slug = %s", (slug,))
            await conn.commit()


async def test_landing_popular_courses_excludes_example_com(async_client):
    password = "Passw0rd!"

    real_slug = f"popular-real-{uuid.uuid4().hex[:8]}"
    test_slug = f"popular-test-{uuid.uuid4().hex[:8]}"

    real_token, real_id = await register_user(
        async_client,
        f"popular_real_{uuid.uuid4().hex[:8]}@example.org",
        password,
        "Real Teacher",
    )
    test_token, test_id = await register_user(
        async_client,
        f"popular_test_{uuid.uuid4().hex[:8]}@example.com",
        password,
        "Test Teacher",
    )
    await promote_to_teacher(real_id)
    await promote_to_teacher(test_id)

    try:
        real_course_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Real Popular Course",
                "slug": real_slug,
                "description": "Real course for popularity listing test",
                "is_published": True,
                "is_free_intro": True,
                "price_amount_cents": 0,
            },
            headers=auth_header(real_token),
        )
        assert real_course_resp.status_code == 200, real_course_resp.text

        test_course_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Test Popular Course",
                "slug": test_slug,
                "description": "Example.com course should be filtered",
                "is_published": True,
                "is_free_intro": True,
                "price_amount_cents": 0,
            },
            headers=auth_header(test_token),
        )
        assert test_course_resp.status_code == 200, test_course_resp.text

        resp = await async_client.get("/landing/popular-courses")
        assert resp.status_code == 200, resp.text
        slugs = {item.get("slug") for item in (resp.json().get("items") or [])}
        assert real_slug in slugs
        assert test_slug not in slugs
    finally:
        await cleanup_course(real_slug)
        await cleanup_course(test_slug)
        await cleanup_user(real_id)
        await cleanup_user(test_id)
