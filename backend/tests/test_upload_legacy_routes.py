import uuid

import pytest
from fastapi import HTTPException

from app import db, models
from app.routes import upload as upload_routes


pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_teacher(async_client):
    email = f"upload_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Secret123!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Teacher"},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = auth_header(tokens["access_token"])
    profile_resp = await async_client.get("/auth/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = profile_resp.json()["user_id"]
    await promote_to_teacher(user_id)
    return headers, user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def create_lesson(async_client, headers):
    slug = f"upload-course-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Upload Course",
            "slug": slug,
            "description": "Course for upload tests",
            "is_published": False,
        },
    )
    assert course_resp.status_code == 200, course_resp.text
    course_id = str(course_resp.json()["id"])

    lesson_resp = await async_client.post(
        "/studio/lessons",
        headers=headers,
        json={
            "course_id": course_id,
            "title": "Lesson",
            "content_markdown": "# Lesson",
            "position": 1,
            "is_intro": False,
        },
    )
    assert lesson_resp.status_code == 200, lesson_resp.text
    lesson_id = str(lesson_resp.json()["id"])
    return course_id, lesson_id


async def test_api_upload_course_media_legacy_route_is_disabled(async_client):
    headers, _ = await register_teacher(async_client)
    course_id, lesson_id = await create_lesson(async_client, headers)

    resp = await async_client.post(
        "/api/upload/course-media",
        headers=headers,
        data={"course_id": course_id, "lesson_id": lesson_id, "type": "video"},
        files={"file": ("demo.mp4", b"mp4-bytes", "video/mp4")},
    )
    assert resp.status_code == 410, resp.text
    assert resp.json()["detail"] == "Legacy lesson upload is disabled"


async def test_upload_course_media_legacy_alias_is_disabled(async_client):
    headers, _ = await register_teacher(async_client)
    course_id, lesson_id = await create_lesson(async_client, headers)

    resp = await async_client.post(
        "/upload/course-media",
        headers=headers,
        data={"course_id": course_id, "lesson_id": lesson_id, "type": "document"},
        files={"file": ("guide.pdf", b"%PDF-1.7 test", "application/pdf")},
    )
    assert resp.status_code == 410, resp.text
    assert resp.json()["detail"] == "Legacy lesson upload is disabled"


async def test_api_upload_lesson_image_legacy_route_is_disabled(async_client):
    headers, _ = await register_teacher(async_client)
    course_id, lesson_id = await create_lesson(async_client, headers)

    resp = await async_client.post(
        "/api/upload/lesson-image",
        headers=headers,
        data={"course_id": course_id, "lesson_id": lesson_id},
        files={"file": ("diagram.png", b"png-bytes", "image/png")},
    )
    assert resp.status_code == 410, resp.text
    assert resp.json()["detail"] == "Legacy lesson upload is disabled"


async def test_upload_lesson_image_legacy_alias_is_disabled(async_client):
    headers, _ = await register_teacher(async_client)
    course_id, lesson_id = await create_lesson(async_client, headers)

    resp = await async_client.post(
        "/upload/lesson-image",
        headers=headers,
        data={"course_id": course_id, "lesson_id": lesson_id},
        files={"file": ("diagram.png", b"png-bytes", "image/png")},
    )
    assert resp.status_code == 410, resp.text
    assert resp.json()["detail"] == "Legacy lesson upload is disabled"


async def test_upload_public_media_route_is_disabled(async_client):
    headers, _ = await register_teacher(async_client)

    resp = await async_client.post(
        "/upload/public-media",
        headers=headers,
        files={"file": ("demo.png", b"png-bytes", "image/png")},
    )
    assert resp.status_code == 410, resp.text
    assert resp.json()["detail"] == "Legacy lesson upload is disabled"


async def test_upload_profile_legacy_alias_is_disabled(async_client):
    headers, _ = await register_teacher(async_client)

    resp = await async_client.post(
        "/upload/profile",
        headers=headers,
        files={"file": ("avatar.png", b"png-bytes", "image/png")},
    )
    assert resp.status_code == 410, resp.text
    assert resp.json()["detail"] == "Legacy lesson upload is disabled"


async def test_upload_preflight_includes_cors_headers(async_client):
    resp = await async_client.options(
        "/upload/course-media",
        headers={
            "Origin": "https://app.aveli.app",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type,x-upsert",
        },
    )
    assert resp.status_code == 200
    assert resp.headers.get("access-control-allow-origin") == "https://app.aveli.app"
    assert "access-control-allow-headers" in resp.headers


async def test_persist_lesson_media_is_disabled():
    with pytest.raises(HTTPException) as exc_info:
        await upload_routes._persist_lesson_media(
            owner_id=str(uuid.uuid4()),
            lesson_id=str(uuid.uuid4()),
            storage_path="courses/demo/lessons/demo/video/demo.mp4",
            original_name="demo.mp4",
            content_type="video/mp4",
            size=1024,
            checksum=None,
            storage_bucket="course-media",
        )

    assert exc_info.value.status_code == 410
    assert exc_info.value.detail == "Legacy lesson upload is disabled"


async def test_add_lesson_media_entry_requires_media_asset_id(async_client):
    headers, _ = await register_teacher(async_client)
    _, lesson_id = await create_lesson(async_client, headers)

    with pytest.raises(ValueError, match="lesson_media writes require media_asset_id"):
        await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="image",
            storage_path=None,
            storage_bucket="public-media",
            position=1,
            media_id=None,
            media_asset_id=None,
        )

    with pytest.raises(ValueError, match="lesson_media writes require media_asset_id"):
        await models.add_lesson_media_entry_with_position_retry(
            lesson_id=lesson_id,
            kind="image",
            storage_path=None,
            storage_bucket="public-media",
            media_id=None,
            media_asset_id=None,
        )
