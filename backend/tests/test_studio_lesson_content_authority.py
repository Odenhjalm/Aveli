import uuid

import pytest

from app import db, repositories
from app.repositories import courses as courses_repo

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(
    async_client,
    *,
    prefix: str,
    promote_teacher: bool,
) -> tuple[str, str]:
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": f"{prefix}_{uuid.uuid4().hex[:8]}@example.com",
            "password": password,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    token = register_resp.json()["access_token"]

    profile_resp = await async_client.get("/profiles/me", headers=auth_header(token))
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])

    create_profile_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(token),
        json={"display_name": prefix, "bio": None},
    )
    assert create_profile_resp.status_code == 200, create_profile_resp.text

    complete_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(token),
    )
    assert complete_resp.status_code == 200, complete_resp.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )

    if promote_teacher:
        async with db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    update app.auth_subjects
                       set role = 'teacher'
                     where user_id = %s::uuid
                    """,
                    (user_id,),
                )
                await conn.commit()

    return token, user_id


async def cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("delete from auth.users where id = %s::uuid", (user_id,))
            await conn.commit()


async def create_course_and_lesson(async_client, token: str) -> tuple[str, str]:
    course_resp = await async_client.post(
        "/studio/courses",
        headers=auth_header(token),
        json={
            "title": "Content Authority Course",
            "slug": f"content-authority-{uuid.uuid4().hex[:8]}",
            "course_group_id": str(uuid.uuid4()),
            "price_amount_cents": None,
            "drip_enabled": False,
            "drip_interval_days": None,
        },
    )
    assert course_resp.status_code == 200, course_resp.text
    course_id = str(course_resp.json()["id"])

    lesson_resp = await async_client.post(
        f"/studio/courses/{course_id}/lessons",
        headers=auth_header(token),
        json={"lesson_title": "Content lesson", "position": 1},
    )
    assert lesson_resp.status_code == 200, lesson_resp.text
    assert "content_markdown" not in lesson_resp.json()
    assert "media" not in lesson_resp.json()
    assert "etag" not in lesson_resp.json()
    return course_id, str(lesson_resp.json()["id"])


async def read_content(async_client, *, token: str, lesson_id: str):
    response = await async_client.get(
        f"/studio/lessons/{lesson_id}/content",
        headers=auth_header(token),
    )
    assert response.status_code == 200, response.text
    assert set(response.json()) == {"lesson_id", "content_markdown", "media"}
    etag = response.headers.get("etag")
    assert etag
    return response, etag


async def test_studio_lesson_content_endpoint_is_only_backend_content_authority(
    async_client,
):
    teacher_token, teacher_id = await register_user(
        async_client,
        prefix="content_teacher",
        promote_teacher=True,
    )
    other_token, other_id = await register_user(
        async_client,
        prefix="other_teacher",
        promote_teacher=True,
    )
    course_id = None
    lesson_id = None

    try:
        course_id, lesson_id = await create_course_and_lesson(
            async_client,
            teacher_token,
        )

        initial_read, initial_etag = await read_content(
            async_client,
            token=teacher_token,
            lesson_id=lesson_id,
        )
        assert initial_read.json() == {
            "lesson_id": lesson_id,
            "content_markdown": "",
            "media": [],
        }

        missing_token = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers=auth_header(teacher_token),
            json={"content_markdown": "# Missing token must fail"},
        )
        assert missing_token.status_code == 428, missing_token.text

        write = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={**auth_header(teacher_token), "If-Match": initial_etag},
            json={"content_markdown": "# Canonical content"},
        )
        assert write.status_code == 200, write.text
        assert set(write.json()) == {"lesson_id", "content_markdown"}
        assert write.json() == {
            "lesson_id": lesson_id,
            "content_markdown": "# Canonical content",
        }
        replacement_etag = write.headers.get("etag")
        assert replacement_etag
        assert replacement_etag != initial_etag

        stale_write = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={**auth_header(teacher_token), "If-Match": initial_etag},
            json={"content_markdown": "# Stale write must not persist"},
        )
        assert stale_write.status_code == 412, stale_write.text

        read_after_stale, read_after_stale_etag = await read_content(
            async_client,
            token=teacher_token,
            lesson_id=lesson_id,
        )
        assert read_after_stale.json()["content_markdown"] == "# Canonical content"
        assert read_after_stale_etag == replacement_etag

        structure_list = await async_client.get(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
        )
        assert structure_list.status_code == 200, structure_list.text
        listed = structure_list.json()["items"][0]
        assert set(listed) == {"id", "course_id", "lesson_title", "position"}
        assert "content_markdown" not in listed
        assert "media" not in listed
        assert "etag" not in listed

        structure_update_with_content = await async_client.patch(
            f"/studio/lessons/{lesson_id}/structure",
            headers=auth_header(teacher_token),
            json={"lesson_title": "Still structure", "content_markdown": "Nope"},
        )
        assert structure_update_with_content.status_code == 422

        unauthorized_read = await async_client.get(
            f"/studio/lessons/{lesson_id}/content",
            headers=auth_header(other_token),
        )
        assert unauthorized_read.status_code == 403, unauthorized_read.text

        stored = await courses_repo.get_lesson(lesson_id)
        assert stored is not None
        assert stored["content_markdown"] == "# Canonical content"
    finally:
        if lesson_id:
            await async_client.delete(
                f"/studio/lessons/{lesson_id}",
                headers=auth_header(teacher_token),
            )
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_user(other_id)
        await cleanup_user(teacher_id)


async def test_studio_lesson_content_accepts_canonical_emphasis_markdown(async_client):
    teacher_token, teacher_id = await register_user(
        async_client,
        prefix="content_teacher_valid",
        promote_teacher=True,
    )
    course_id = None
    lesson_id = None

    try:
        course_id, lesson_id = await create_course_and_lesson(
            async_client,
            teacher_token,
        )
        _read, etag = await read_content(
            async_client,
            token=teacher_token,
            lesson_id=lesson_id,
        )

        write = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={**auth_header(teacher_token), "If-Match": etag},
            json={
                "content_markdown": "This is plain, *italic*, and **bold**.",
            },
        )
        assert write.status_code == 200, write.text
        assert write.json()["content_markdown"] == (
            "This is plain, *italic*, and **bold**."
        )
    finally:
        if lesson_id:
            await async_client.delete(
                f"/studio/lessons/{lesson_id}",
                headers=auth_header(teacher_token),
            )
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_user(teacher_id)


async def test_studio_lesson_content_rejects_direct_api_bypass_with_malformed_markdown(
    async_client,
):
    teacher_token, teacher_id = await register_user(
        async_client,
        prefix="content_teacher_invalid",
        promote_teacher=True,
    )
    course_id = None
    lesson_id = None

    try:
        course_id, lesson_id = await create_course_and_lesson(
            async_client,
            teacher_token,
        )
        _read, etag = await read_content(
            async_client,
            token=teacher_token,
            lesson_id=lesson_id,
        )

        seed = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={**auth_header(teacher_token), "If-Match": etag},
            json={"content_markdown": "# Canonical content"},
        )
        assert seed.status_code == 200, seed.text

        bypass = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={
                **auth_header(teacher_token),
                "If-Match": seed.headers["etag"],
            },
            json={
                "content_markdown": r"This is plain, \*italic\*, and **bold**.",
            },
        )
        assert bypass.status_code == 400, bypass.text
        assert bypass.json()["detail"] == (
            "Invalid lesson markdown. Formatting must be corrected before saving."
        )

        stored = await courses_repo.get_lesson(lesson_id)
        assert stored is not None
        assert stored["content_markdown"] == "# Canonical content"
    finally:
        if lesson_id:
            await async_client.delete(
                f"/studio/lessons/{lesson_id}",
                headers=auth_header(teacher_token),
            )
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_user(teacher_id)
