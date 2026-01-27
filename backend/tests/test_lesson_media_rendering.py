import uuid

import pytest

from app import models
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo


pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(async_client) -> tuple[str, str]:
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": f"lesson_media_{uuid.uuid4().hex[:8]}@example.com",
            "password": password,
            "display_name": "Owner",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    me_resp = await async_client.get("/auth/me", headers=auth_header(tokens["access_token"]))
    assert me_resp.status_code == 200, me_resp.text
    return tokens["access_token"], me_resp.json()["user_id"]


async def test_lesson_detail_includes_processing_pipeline_media(async_client):
    token, owner_id = await register_user(async_client)

    course = await courses_repo.create_course(
        {
            "title": "Published Course",
            "slug": f"published-{uuid.uuid4().hex[:8]}",
            "description": "Course for lesson media rendering tests",
            "created_by": owner_id,
            "is_published": True,
            "price_amount_cents": 1000,
            "currency": "sek",
        }
    )
    course_id = str(course["id"])
    module = await courses_repo.create_module(course_id, title="Module", position=0)
    lesson = await courses_repo.create_lesson(
        str(module["id"]),
        title="Lesson",
        content_markdown="# Lesson",
        position=0,
        is_intro=False,
    )
    assert lesson
    lesson_id = str(lesson["id"])

    media_asset = await media_assets_repo.create_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=lesson_id,
        media_type="audio",
        purpose="lesson_audio",
        ingest_format="wav",
        original_object_path=f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav",
        original_content_type="audio/wav",
        original_filename="demo.wav",
        original_size_bytes=123,
        storage_bucket="course-media",
        state="processing",
    )
    assert media_asset

    lesson_media = await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind="audio",
        storage_path=None,
        storage_bucket="course-media",
        media_id=None,
        media_asset_id=str(media_asset["id"]),
        position=1,
        duration_seconds=None,
    )
    assert lesson_media
    lesson_media_id = str(lesson_media["id"])

    resp = await async_client.get(
        f"/courses/lessons/{lesson_id}",
        headers=auth_header(token),
    )
    assert resp.status_code == 200, resp.text

    media_items = resp.json().get("media") or []
    assert lesson_media_id in {item.get("id") for item in media_items}
    item = next(it for it in media_items if it.get("id") == lesson_media_id)
    assert item.get("media_asset_id") == str(media_asset["id"])
    assert item.get("media_state") == "processing"

