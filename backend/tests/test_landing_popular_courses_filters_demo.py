import uuid

import pytest

from app import db


pytestmark = pytest.mark.anyio("asyncio")


async def insert_teacher(email: str, display_name: str) -> str:
    user_id = str(uuid.uuid4())
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO auth.users (
                    id,
                    email,
                    encrypted_password,
                    created_at,
                    updated_at
                )
                VALUES (%s::uuid, %s, 'test-hash', now(), now())
                """,
                (user_id, email.strip().lower()),
            )
            await cur.execute(
                """
                INSERT INTO app.auth_subjects (
                    user_id,
                    email,
                    role,
                    onboarding_state
                )
                VALUES (%s::uuid, %s, 'teacher', 'completed')
                """,
                (user_id, email.strip().lower()),
            )
            await cur.execute(
                """
                INSERT INTO app.profiles (user_id, display_name, bio, created_at, updated_at)
                VALUES (%s::uuid, %s, null, now(), now())
                """,
                (user_id, display_name),
            )
            await conn.commit()
    return user_id


async def insert_course(*, teacher_id: str, slug: str, title: str, sellable: bool) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.courses (
                    teacher_id,
                    title,
                    slug,
                    course_group_id,
                    group_position,
                    visibility,
                    content_ready,
                    price_amount_cents,
                    stripe_product_id,
                    active_stripe_price_id,
                    sellable,
                    drip_enabled,
                    drip_interval_days
                )
                VALUES (
                    %s::uuid,
                    %s,
                    %s,
                    %s::uuid,
                    1,
                    'public',
                    true,
                    9900,
                    %s,
                    %s,
                    %s,
                    false,
                    null
                )
                """,
                (
                    teacher_id,
                    title,
                    slug,
                    str(uuid.uuid4()),
                    f"prod_{slug}",
                    f"price_{slug}",
                    sellable,
                ),
            )
            await conn.commit()


async def cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.profiles WHERE user_id = %s::uuid", (user_id,))
            await cur.execute(
                "DELETE FROM app.auth_subjects WHERE user_id = %s::uuid",
                (user_id,),
            )
            await cur.execute("DELETE FROM auth.users WHERE id = %s::uuid", (user_id,))
            await conn.commit()


async def cleanup_course(slug: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.courses WHERE slug = %s", (slug,))
            await conn.commit()


async def test_landing_popular_courses_uses_canonical_discovery(async_client):
    real_slug = f"popular-real-{uuid.uuid4().hex[:8]}"
    test_slug = f"popular-test-{uuid.uuid4().hex[:8]}"

    real_id = await insert_teacher(
        f"popular_real_{uuid.uuid4().hex[:8]}@example.org",
        "Real Teacher",
    )
    test_id = await insert_teacher(
        f"popular_test_{uuid.uuid4().hex[:8]}@example.com",
        "Test Teacher",
    )

    try:
        await insert_course(
            teacher_id=real_id,
            slug=real_slug,
            title="Real Popular Course",
            sellable=True,
        )
        await insert_course(
            teacher_id=test_id,
            slug=test_slug,
            title="Non-discoverable Popular Course",
            sellable=False,
        )

        resp = await async_client.get("/landing/popular-courses")
        assert resp.status_code == 200, resp.text
        items = resp.json().get("items") or []
        slugs = {item.get("slug") for item in items}
        assert real_slug in slugs
        assert test_slug not in slugs
        real_item = next(item for item in items if item.get("slug") == real_slug)
        assert set(real_item) == {
            "id",
            "slug",
            "title",
            "course_group_id",
            "group_position",
            "cover_media_id",
            "cover",
            "price_amount_cents",
            "drip_enabled",
            "drip_interval_days",
        }
        assert "resolved_cover_url" not in real_item
        assert "cover_url" not in real_item
    finally:
        await cleanup_course(real_slug)
        await cleanup_course(test_slug)
        await cleanup_user(real_id)
        await cleanup_user(test_id)
