import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app import db, models
from app.main import app
from app.repositories import create_home_player_upload
from app.repositories import courses as courses_repo
from app.repositories import home_player_library as home_player_repo
from app.repositories import media_assets as media_assets_repo

from .utils import register_user


pytestmark = pytest.mark.anyio("asyncio")


async def _build_test_graph(user_id: str) -> dict[str, str]:
    course = await courses_repo.create_course(
        {
            "title": "Isolated Test Course",
            "slug": f"isolated-{uuid.uuid4().hex[:10]}",
            "description": "Course created inside a scoped test session",
            "created_by": user_id,
            "is_published": True,
            "price_amount_cents": 0,
            "currency": "sek",
        }
    )
    assert course is not None
    course_id = str(course["id"])

    lesson = await courses_repo.create_lesson(
        course_id,
        title="Isolated Lesson",
        content_markdown="# Lesson",
        position=1,
        is_intro=True,
    )
    assert lesson is not None
    lesson_id = str(lesson["id"])

    media_asset = await media_assets_repo.create_media_asset(
        owner_id=user_id,
        course_id=course_id,
        lesson_id=lesson_id,
        media_type="audio",
        purpose="lesson_audio",
        ingest_format="wav",
        original_object_path=(
            f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/isolated.wav"
        ),
        original_content_type="audio/wav",
        original_filename="isolated.wav",
        original_size_bytes=321,
        storage_bucket="course-media",
        state="processing",
    )
    assert media_asset is not None
    media_asset_id = str(media_asset["id"])

    lesson_media = await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind="audio",
        storage_path=None,
        storage_bucket="course-media",
        media_id=None,
        media_asset_id=media_asset_id,
        position=1,
        duration_seconds=None,
    )
    assert lesson_media is not None
    lesson_media_id = str(lesson_media["id"])

    return {
        "course_id": course_id,
        "lesson_id": lesson_id,
        "media_asset_id": media_asset_id,
        "lesson_media_id": lesson_media_id,
    }


async def test_production_queries_do_not_see_session_scoped_rows(async_client):
    headers, user_id, _ = await register_user(async_client)
    graph = await _build_test_graph(user_id)
    upload = await create_home_player_upload(
        teacher_id=user_id,
        media_id=None,
        media_asset_id=graph["media_asset_id"],
        title="Hidden Upload",
        kind="audio",
        active=True,
    )
    assert upload is not None

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.home_player_course_links (
                  teacher_id,
                  lesson_media_id,
                  title,
                  course_title_snapshot,
                  enabled
                )
                VALUES (%s, %s, %s, %s, true)
                """,
                (
                    user_id,
                    graph["lesson_media_id"],
                    "Hidden Link",
                    "Snapshot",
                ),
            )
            await conn.commit()

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://testserver",
    ) as prod_client:
        catalog_resp = await prod_client.get("/courses")
        assert catalog_resp.status_code == 200, catalog_resp.text
        catalog_ids = {str(item["id"]) for item in catalog_resp.json().get("items") or []}
        assert graph["course_id"] not in catalog_ids

        lesson_resp = await prod_client.get(
            f"/courses/lessons/{graph['lesson_id']}",
            headers=headers,
        )
        assert lesson_resp.status_code == 404, lesson_resp.text

        playback_resp = await prod_client.post(
            "/api/media/lesson-playback",
            json={"lesson_media_id": graph["lesson_media_id"]},
            headers=headers,
        )
        assert playback_resp.status_code == 404, playback_resp.text

    with db.use_test_session(None):
        public_courses = await courses_repo.list_public_courses(search="Isolated Test Course")
        assert not public_courses
        assert await courses_repo.get_lesson(graph["lesson_id"]) is None
        assert (
            await home_player_repo.get_active_home_upload_by_media_asset_id(
                graph["media_asset_id"]
            )
            is None
        )
        assert await home_player_repo.list_home_player_uploads(user_id) == []
        assert await home_player_repo.list_home_player_course_links(user_id) == []
        assert (
            await home_player_repo.resolve_lesson_media_course_owner(
                graph["lesson_media_id"]
            )
            is None
        )
