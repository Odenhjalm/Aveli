import uuid

import pytest

from app import db


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


async def test_upload_course_media_legacy_route_accepts_audio(async_client, tmp_path, monkeypatch):
    headers, _ = await register_teacher(async_client)
    course_id, lesson_id = await create_lesson(async_client, headers)

    from app.routes import upload as upload_routes

    upload_root = tmp_path / "uploads"
    upload_root.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(upload_routes, "UPLOADS_ROOT", upload_root, raising=True)

    resp = await async_client.post(
        "/upload/course-media",
        headers=headers,
        data={"course_id": course_id, "lesson_id": lesson_id, "type": "audio"},
        files={"file": ("demo.mp3", b"mp3-bytes", "audio/mpeg")},
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    media = payload.get("media") or {}
    assert isinstance(media, dict)
    assert (media.get("download_url") or "").startswith("/studio/media/")


async def test_upload_public_media_returns_public_url(async_client, tmp_path, monkeypatch):
    headers, _ = await register_teacher(async_client)

    from app.routes import upload as upload_routes

    upload_root = tmp_path / "uploads"
    upload_root.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(upload_routes, "UPLOADS_ROOT", upload_root, raising=True)

    resp = await async_client.post(
        "/upload/public-media",
        headers=headers,
        files={"file": ("demo.png", b"png-bytes", "image/png")},
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    url = payload.get("url") or ""
    assert "/api/files/public-media/" in url


async def test_upload_preflight_includes_cors_headers(async_client):
    resp = await async_client.options(
        "/upload/course-media",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type,x-upsert",
        },
    )
    assert resp.status_code == 200
    assert resp.headers.get("access-control-allow-origin") == "http://localhost:3000"
    assert "access-control-allow-headers" in resp.headers
