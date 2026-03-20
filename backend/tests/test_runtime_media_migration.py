import uuid

import pytest

from app import db, models
from app.repositories import create_home_player_upload
from app.repositories import runtime_media as runtime_media_repo
from .test_media_api import cleanup_user, create_lesson, register_teacher


pytestmark = pytest.mark.anyio("asyncio")


async def _ensure_pool_open() -> None:
    if db.pool.closed:  # type: ignore[attr-defined]
        await db.pool.open(wait=True)  # type: ignore[attr-defined]


async def test_runtime_media_backfill_counts_match_lesson_media():
    await _ensure_pool_open()
    async with db.get_conn() as cur:
        await cur.execute(
            "SELECT count(*) AS lesson_count FROM app.lesson_media"
        )
        lesson_count_row = await cur.fetchone()
        await cur.execute(
            """
            SELECT count(*) AS runtime_count
            FROM app.runtime_media
            WHERE lesson_media_id IS NOT NULL
              AND active = true
            """
        )
        runtime_count_row = await cur.fetchone()
        await cur.execute(
            """
            SELECT count(*) AS duplicate_count
            FROM (
              SELECT lesson_media_id
              FROM app.runtime_media
              WHERE lesson_media_id IS NOT NULL
                AND active = true
              GROUP BY lesson_media_id
              HAVING count(*) > 1
            ) duplicates
            """
        )
        duplicate_count_row = await cur.fetchone()

    assert int(lesson_count_row["lesson_count"]) == int(runtime_count_row["runtime_count"])
    assert int(duplicate_count_row["duplicate_count"]) == 0


async def test_runtime_media_maps_new_lesson_media_rows(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)
        storage_path = f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        media_object = await models.create_media_object(
            owner_id=user_id,
            storage_path=storage_path,
            storage_bucket="course-media",
            content_type="audio/mpeg",
            byte_size=1024,
            checksum=None,
            original_name="demo.mp3",
        )
        assert media_object

        lesson_media = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="audio",
            storage_path=storage_path,
            storage_bucket="course-media",
            media_id=str(media_object["id"]),
            position=1,
            duration_seconds=95,
        )
        assert lesson_media

        async with db.get_conn() as cur:
            await cur.execute(
                """
                SELECT
                  id,
                  reference_type,
                  auth_scope,
                  fallback_policy,
                  lesson_media_id,
                  home_player_upload_id,
                  teacher_id,
                  course_id,
                  lesson_id,
                  media_object_id,
                  legacy_storage_bucket,
                  legacy_storage_path,
                  kind,
                  active
                FROM app.runtime_media
                WHERE lesson_media_id = %s
                """,
                (str(lesson_media["id"]),),
            )
            rows = await cur.fetchall()

        assert len(rows) == 1
        row = rows[0]
        assert str(row["lesson_media_id"]) == str(lesson_media["id"])
        assert row["home_player_upload_id"] is None
        assert row["reference_type"] == "lesson_media"
        assert row["auth_scope"] == "lesson_course"
        assert row["fallback_policy"] == "legacy_only"
        assert str(row["teacher_id"]) == user_id
        assert str(row["course_id"]) == course_id
        assert str(row["lesson_id"]) == lesson_id
        assert str(row["media_object_id"]) == str(media_object["id"])
        assert row["legacy_storage_bucket"] == "course-media"
        assert row["legacy_storage_path"] == storage_path
        assert row["kind"] == "audio"
        assert row["active"] is True
    finally:
        await cleanup_user(user_id)


async def test_runtime_media_backfill_counts_match_home_player_uploads():
    await _ensure_pool_open()
    await runtime_media_repo.sync_home_player_upload_runtime_media()

    async with db.get_conn() as cur:
        await cur.execute(
            "SELECT count(*) AS upload_count FROM app.home_player_uploads"
        )
        upload_count_row = await cur.fetchone()
        await cur.execute(
            """
            SELECT count(*) AS runtime_count
            FROM app.runtime_media
            WHERE home_player_upload_id IS NOT NULL
            """
        )
        runtime_count_row = await cur.fetchone()
        await cur.execute(
            """
            SELECT count(*) AS duplicate_count
            FROM (
              SELECT home_player_upload_id
              FROM app.runtime_media
              WHERE home_player_upload_id IS NOT NULL
              GROUP BY home_player_upload_id
              HAVING count(*) > 1
            ) duplicates
            """
        )
        duplicate_count_row = await cur.fetchone()

    assert int(upload_count_row["upload_count"]) == int(runtime_count_row["runtime_count"])
    assert int(duplicate_count_row["duplicate_count"]) == 0


async def test_runtime_media_maps_new_home_player_upload_rows(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        media_object = await models.create_media_object(
            owner_id=user_id,
            storage_path=f"home-player/{user_id}/demo-{uuid.uuid4().hex}.mp3",
            storage_bucket="course-media",
            content_type="audio/mpeg",
            byte_size=1024,
            checksum=None,
            original_name="demo.mp3",
        )
        assert media_object

        upload = await create_home_player_upload(
            teacher_id=user_id,
            media_id=str(media_object["id"]),
            media_asset_id=None,
            title="Home upload",
            kind="audio",
            active=True,
        )
        assert upload

        async with db.get_conn() as cur:
            await cur.execute(
                """
                SELECT
                  id,
                  reference_type,
                  auth_scope,
                  fallback_policy,
                  lesson_media_id,
                  home_player_upload_id,
                  teacher_id,
                  course_id,
                  lesson_id,
                  media_asset_id,
                  media_object_id,
                  legacy_storage_bucket,
                  legacy_storage_path,
                  kind,
                  active
                FROM app.runtime_media
                WHERE home_player_upload_id = %s
                """,
                (str(upload["id"]),),
            )
            rows = await cur.fetchall()

        assert len(rows) == 1
        row = rows[0]
        assert row["lesson_media_id"] is None
        assert str(row["home_player_upload_id"]) == str(upload["id"])
        assert row["reference_type"] == "home_player_upload"
        assert row["auth_scope"] == "home_teacher_library"
        assert row["fallback_policy"] == "if_no_ready_asset"
        assert str(row["teacher_id"]) == user_id
        assert row["course_id"] is None
        assert row["lesson_id"] is None
        assert row["media_asset_id"] is None
        assert str(row["media_object_id"]) == str(media_object["id"])
        assert row["legacy_storage_bucket"] == "course-media"
        assert row["legacy_storage_path"] == str(media_object["storage_path"])
        assert row["kind"] == "audio"
        assert row["active"] is True
    finally:
        await cleanup_user(user_id)
