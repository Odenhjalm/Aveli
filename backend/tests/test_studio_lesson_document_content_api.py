from __future__ import annotations

import uuid

import pytest

from app import db, repositories

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _paragraph_document(text: str) -> dict[str, object]:
    return {
        "schema_version": "lesson_document_v1",
        "blocks": [
            {
                "type": "paragraph",
                "children": [
                    {
                        "text": text,
                        "marks": ["bold"],
                    }
                ],
            }
        ],
    }


async def _register_teacher(async_client) -> tuple[str, str]:
    password = "Passw0rd!"
    response = await async_client.post(
        "/auth/register",
        json={
            "email": f"document_teacher_{uuid.uuid4().hex[:8]}@example.com",
            "password": password,
        },
    )
    assert response.status_code == 201, response.text
    token = response.json()["access_token"]

    profile = await async_client.get("/profiles/me", headers=auth_header(token))
    assert profile.status_code == 200, profile.text
    user_id = str(profile.json()["user_id"])

    create_profile = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(token),
        json={"display_name": "Document Teacher", "bio": None},
    )
    assert create_profile.status_code == 200, create_profile.text
    complete = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(token),
    )
    assert complete.status_code == 200, complete.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )

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


async def _cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("delete from auth.users where id = %s::uuid", (user_id,))
            await conn.commit()


async def test_studio_lesson_content_api_uses_document_with_etag_cas(async_client):
    teacher_token, teacher_id = await _register_teacher(async_client)
    course_id: str | None = None
    lesson_id: str | None = None

    try:
        course = await async_client.post(
            "/studio/courses",
            headers=auth_header(teacher_token),
            json={
                "title": "Document API Course",
                "slug": f"document-api-{uuid.uuid4().hex[:8]}",
                "course_group_id": str(uuid.uuid4()),
                "price_amount_cents": None,
                "drip_enabled": False,
                "drip_interval_days": None,
            },
        )
        assert course.status_code == 200, course.text
        course_id = str(course.json()["id"])

        lesson = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
            json={"lesson_title": "Document lesson", "position": 1},
        )
        assert lesson.status_code == 200, lesson.text
        lesson_id = str(lesson.json()["id"])

        initial = await async_client.get(
            f"/studio/lessons/{lesson_id}/content",
            headers=auth_header(teacher_token),
        )
        assert initial.status_code == 200, initial.text
        assert initial.json() == {
            "lesson_id": lesson_id,
            "content_document": {
                "schema_version": "lesson_document_v1",
                "blocks": [],
            },
            "media": [],
        }
        initial_etag = initial.headers.get("etag")
        assert initial_etag

        missing_precondition = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers=auth_header(teacher_token),
            json={"content_document": _paragraph_document("Missing precondition")},
        )
        assert missing_precondition.status_code == 428, missing_precondition.text

        invalid = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={**auth_header(teacher_token), "If-Match": initial_etag},
            json={
                "content_document": {
                    "schema_version": "lesson_document_v1",
                    "blocks": [
                        {
                            "type": "paragraph",
                            "children": [{"text": "Bad", "marks": ["strike"]}],
                        }
                    ],
                }
            },
        )
        assert invalid.status_code == 400, invalid.text

        document = _paragraph_document("Persisted document")
        write = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={**auth_header(teacher_token), "If-Match": initial_etag},
            json={"content_document": document},
        )
        assert write.status_code == 200, write.text
        assert write.json() == {"lesson_id": lesson_id, "content_document": document}
        replacement_etag = write.headers.get("etag")
        assert replacement_etag
        assert replacement_etag != initial_etag

        stale = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={**auth_header(teacher_token), "If-Match": initial_etag},
            json={"content_document": _paragraph_document("Stale")},
        )
        assert stale.status_code == 412, stale.text

        after = await async_client.get(
            f"/studio/lessons/{lesson_id}/content",
            headers=auth_header(teacher_token),
        )
        assert after.status_code == 200, after.text
        assert after.json()["content_document"] == document
        assert after.headers.get("etag") == replacement_etag
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
        await _cleanup_user(teacher_id)
