import uuid

import pytest

from app import db, repositories

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def lesson_document(text: str) -> dict:
    return {
        "schema_version": "lesson_document_v1",
        "blocks": [
            {
                "type": "paragraph",
                "children": [{"text": text}],
            }
        ],
    }


def studio_course_payload(title: str, slug: str) -> dict[str, object]:
    return {
        "title": title,
        "slug": slug,
        "course_group_id": str(uuid.uuid4()),
        "price_amount_cents": None,
        "drip_enabled": False,
        "drip_interval_days": None,
    }


async def register_user(
    client, email: str, password: str, display_name: str
) -> tuple[str, str]:
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    token = tokens["access_token"]

    me_resp = await client.get("/profiles/me", headers=auth_header(token))
    assert me_resp.status_code == 200, me_resp.text
    user_id = me_resp.json()["user_id"]
    create_profile = await client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(token),
        json={"display_name": display_name, "bio": None},
    )
    assert create_profile.status_code == 200, create_profile.text
    complete = await client.post(
        "/auth/onboarding/complete",
        headers=auth_header(token),
    )
    assert complete.status_code == 200, complete.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )
    return token, user_id


async def promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET role = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def read_lesson_content_etag(
    async_client,
    *,
    lesson_id: str,
    token: str,
) -> str:
    response = await async_client.get(
        f"/studio/lessons/{lesson_id}/content",
        headers=auth_header(token),
    )
    assert response.status_code == 200, response.text
    assert set(response.json()) == {"lesson_id", "content_document", "media"}
    etag = response.headers.get("etag")
    assert etag
    return etag


async def test_studio_lessons_belong_directly_to_course(async_client):
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client,
        f"studio_lessons_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    slug = f"studio-course-{uuid.uuid4().hex[:8]}"
    create_course = await async_client.post(
        "/studio/courses",
        headers=auth_header(teacher_token),
        json=studio_course_payload(f"Course {slug}", slug),
    )
    assert create_course.status_code == 200, create_course.text
    course_id = create_course.json()["id"]

    resp_empty = await async_client.get(
        f"/studio/courses/{course_id}/lessons",
        headers=auth_header(teacher_token),
    )
    assert resp_empty.status_code == 200, resp_empty.text
    assert resp_empty.json().get("items") == []

    create_lesson = await async_client.post(
        f"/studio/courses/{course_id}/lessons",
        headers=auth_header(teacher_token),
        json={
            "lesson_title": "Lesson 1",
            "position": 1,
        },
    )
    assert create_lesson.status_code == 200, create_lesson.text
    lesson = create_lesson.json()
    lesson_id = lesson["id"]
    assert lesson["course_id"] == course_id
    assert "content_markdown" not in lesson

    content = await async_client.patch(
        f"/studio/lessons/{lesson_id}/content",
        headers={
            **auth_header(teacher_token),
            "If-Match": await read_lesson_content_etag(
                async_client,
                lesson_id=lesson_id,
                token=teacher_token,
            ),
        },
        json={"content_document": lesson_document("Hello")},
    )
    assert content.status_code == 200, content.text
    assert content.json()["content_document"] == lesson_document("Hello")

    resp = await async_client.get(
        f"/studio/courses/{course_id}/lessons",
        headers=auth_header(teacher_token),
    )
    assert resp.status_code == 200, resp.text
    items = resp.json().get("items") or []
    assert [it.get("id") for it in items] == [lesson_id]
    assert "content_markdown" not in items[0]

    patch = await async_client.patch(
        f"/studio/lessons/{lesson_id}/structure",
        headers=auth_header(teacher_token),
        json={"lesson_title": "Lesson 1 updated"},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json()["lesson_title"] == "Lesson 1 updated"
    assert "content_markdown" not in patch.json()


async def test_studio_reorder_lessons_updates_positions(async_client):
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client,
        f"studio_reorder_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    slug = f"studio-reorder-{uuid.uuid4().hex[:8]}"
    create_course = await async_client.post(
        "/studio/courses",
        headers=auth_header(teacher_token),
        json=studio_course_payload(f"Course {slug}", slug),
    )
    assert create_course.status_code == 200, create_course.text
    course_id = create_course.json()["id"]

    lesson_ids: list[str] = []
    for index, title in enumerate(("Lesson A", "Lesson B", "Lesson C"), start=1):
        create_lesson = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
            json={
                "lesson_title": title,
                "position": index * 10,
            },
        )
        assert create_lesson.status_code == 200, create_lesson.text
        lesson_ids.append(create_lesson.json()["id"])

    reorder = await async_client.patch(
        f"/studio/courses/{course_id}/lessons/reorder",
        headers=auth_header(teacher_token),
        json={
            "lessons": [
                {"id": lesson_ids[0], "position": 2},
                {"id": lesson_ids[1], "position": 3},
                {"id": lesson_ids[2], "position": 1},
            ]
        },
    )
    assert reorder.status_code == 200, reorder.text
    assert reorder.json() == {"ok": True}

    ordered = await async_client.get(
        f"/studio/courses/{course_id}/lessons",
        headers=auth_header(teacher_token),
    )
    assert ordered.status_code == 200, ordered.text
    items = ordered.json().get("items") or []
    assert [item.get("id") for item in items] == [
        lesson_ids[2],
        lesson_ids[0],
        lesson_ids[1],
    ]
    assert [item.get("position") for item in items] == [1, 2, 3]
