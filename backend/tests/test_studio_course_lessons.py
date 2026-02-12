import uuid

import pytest

from app import db

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(
    client, email: str, password: str, display_name: str
) -> tuple[str, str]:
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
    token = tokens["access_token"]

    me_resp = await client.get("/auth/me", headers=auth_header(token))
    assert me_resp.status_code == 200, me_resp.text
    user_id = me_resp.json()["user_id"]
    return token, user_id


async def promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


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
        json={"title": f"Course {slug}", "slug": slug},
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
        "/studio/lessons",
        headers=auth_header(teacher_token),
        json={
            "course_id": course_id,
            "title": "Lesson 1",
            "position": 1,
            "is_intro": False,
            "content_markdown": "Hello",
        },
    )
    assert create_lesson.status_code == 200, create_lesson.text
    lesson = create_lesson.json()
    lesson_id = lesson["id"]
    assert lesson["course_id"] == course_id

    resp = await async_client.get(
        f"/studio/courses/{course_id}/lessons",
        headers=auth_header(teacher_token),
    )
    assert resp.status_code == 200, resp.text
    items = resp.json().get("items") or []
    assert [it.get("id") for it in items] == [lesson_id]

    patch = await async_client.patch(
        f"/studio/lessons/{lesson_id}",
        headers=auth_header(teacher_token),
        json={"title": "Lesson 1 updated"},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json()["title"] == "Lesson 1 updated"


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
        json={"title": f"Course {slug}", "slug": slug},
    )
    assert create_course.status_code == 200, create_course.text
    course_id = create_course.json()["id"]

    lesson_ids: list[str] = []
    for index, title in enumerate(("Lesson A", "Lesson B", "Lesson C"), start=1):
        create_lesson = await async_client.post(
            "/studio/lessons",
            headers=auth_header(teacher_token),
            json={
                "course_id": course_id,
                "title": title,
                "position": index,
                "is_intro": False,
                "content_markdown": f"Content {title}",
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
