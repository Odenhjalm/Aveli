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


async def _row_test_metadata(table_name: str, row_id: str) -> dict[str, str | bool] | None:
    query = f"""
        SELECT is_test, test_session_id::text AS test_session_id
        FROM app.{table_name}
        WHERE id = %s
        LIMIT 1
    """
    async with db.get_conn() as cur:
        await cur.execute(query, (row_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def _count_rows_for_session(table_name: str, test_session_id: str) -> int:
    query = f"""
        SELECT count(*) AS row_count
        FROM app.{table_name}
        WHERE is_test = true
          AND test_session_id = %s::uuid
    """
    async with db.get_conn() as cur:
        await cur.execute(query, (test_session_id,))
        row = await cur.fetchone()
    return int((row or {}).get("row_count") or 0)


async def _count_related_rows(query: str, row_id: str) -> int:
    async with db.get_conn() as cur:
        await cur.execute(query, (row_id,))
        row = await cur.fetchone()
    return int((row or {}).get("row_count") or 0)


async def _build_test_graph(user_id: str) -> dict[str, str]:
    course = await courses_repo.create_course(
        {
            "title": "Isolated Test Course",
            "slug": f"isolated-{uuid.uuid4().hex[:10]}",
            "description": "Course created inside a test session",
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

    async with db.get_conn() as cur:
        await cur.execute(
            """
            SELECT id::text
            FROM app.runtime_media
            WHERE lesson_media_id = %s
            LIMIT 1
            """,
            (lesson_media_id,),
        )
        runtime_row = await cur.fetchone()
    assert runtime_row is not None
    runtime_media_id = str(runtime_row["id"])

    return {
        "course_id": course_id,
        "lesson_id": lesson_id,
        "media_asset_id": media_asset_id,
        "lesson_media_id": lesson_media_id,
        "runtime_media_id": runtime_media_id,
    }


async def test_test_rows_are_auto_flagged(async_client, test_session_id: str):
    _, user_id, _ = await register_user(async_client)
    graph = await _build_test_graph(user_id)

    for table_name, row_id in (
        ("courses", graph["course_id"]),
        ("lessons", graph["lesson_id"]),
        ("media_assets", graph["media_asset_id"]),
        ("lesson_media", graph["lesson_media_id"]),
        ("runtime_media", graph["runtime_media_id"]),
    ):
        row = await _row_test_metadata(table_name, row_id)
        assert row is not None
        assert row["is_test"] is True
        assert row["test_session_id"] == test_session_id


async def test_cleanup_test_session_removes_flagged_and_related_rows(
    async_client,
    test_session_id: str,
):
    _, user_id, _ = await register_user(async_client)
    graph = await _build_test_graph(user_id)

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
                    "Session Link",
                    "Snapshot",
                ),
            )
            await conn.commit()

    upload = await create_home_player_upload(
        teacher_id=user_id,
        media_id=None,
        media_asset_id=graph["media_asset_id"],
        title="Session Upload",
        kind="audio",
        active=True,
    )
    assert upload is not None
    upload_id = str(upload["id"])

    assert await _count_rows_for_session("courses", test_session_id) == 1
    assert await _count_rows_for_session("lessons", test_session_id) == 1
    assert await _count_rows_for_session("media_assets", test_session_id) == 1
    assert await _count_rows_for_session("lesson_media", test_session_id) == 1
    assert await _count_rows_for_session("runtime_media", test_session_id) >= 1

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "SELECT app.cleanup_test_session(%s::uuid)",
                (test_session_id,),
            )
            await conn.commit()

    for table_name in (
        "courses",
        "lessons",
        "media_assets",
        "lesson_media",
        "runtime_media",
    ):
        assert await _count_rows_for_session(table_name, test_session_id) == 0

    assert (
        await _count_related_rows(
            """
            SELECT count(*) AS row_count
            FROM app.home_player_course_links
            WHERE lesson_media_id = %s::uuid
            """,
            graph["lesson_media_id"],
        )
        == 0
    )
    assert (
        await _count_related_rows(
            """
            SELECT count(*) AS row_count
            FROM app.home_player_uploads
            WHERE id = %s::uuid
            """,
            upload_id,
        )
        == 0
    )


async def test_production_queries_do_not_see_session_test_rows(
    async_client,
    test_session_id: str,
):
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

    # Sanity check: the active test session still sees its own rows until cleanup.
    assert await _count_rows_for_session("courses", test_session_id) == 1


async def test_runtime_media_for_direct_home_upload_inherits_test_session(
    async_client,
    test_session_id: str,
):
    _, user_id, _ = await register_user(async_client)
    media_object = await models.create_media_object(
        owner_id=user_id,
        storage_path=f"home-player/{user_id}/isolated-{uuid.uuid4().hex[:8]}.mp3",
        storage_bucket="course-media",
        content_type="audio/mpeg",
        byte_size=123,
        checksum=None,
        original_name="isolated.mp3",
    )
    assert media_object is not None

    upload = await create_home_player_upload(
        teacher_id=user_id,
        media_id=str(media_object["id"]),
        media_asset_id=None,
        title="Direct Upload",
        kind="audio",
        active=True,
    )
    assert upload is not None

    async with db.get_conn() as cur:
        await cur.execute(
            """
            SELECT id::text
            FROM app.runtime_media
            WHERE home_player_upload_id = %s::uuid
            LIMIT 1
            """,
            (str(upload["id"]),),
        )
        runtime_row = await cur.fetchone()
    assert runtime_row is not None

    row = await _row_test_metadata("runtime_media", str(runtime_row["id"]))
    assert row is not None
    assert row["is_test"] is True
    assert row["test_session_id"] == test_session_id
