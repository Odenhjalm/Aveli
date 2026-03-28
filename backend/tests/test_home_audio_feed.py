import uuid

import pytest

from psycopg import errors

from app import db, models
from app.media_control_plane.services.media_resolver_service import (
    media_resolver_service as canonical_media_resolver,
)
from app.repositories import create_home_player_upload
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo


async def _runtime_media_id_for_lesson_media(lesson_media_id: str) -> str:
    async with db.get_conn() as cur:
        await cur.execute(
            """
            SELECT id
            FROM app.runtime_media
            WHERE lesson_media_id = %s
            LIMIT 1
            """,
            (lesson_media_id,),
        )
        row = await cur.fetchone()
    assert row
    return str(row["id"])


async def _runtime_media_id_for_home_upload(upload_id: str) -> str:
    async with db.get_conn() as cur:
        await cur.execute(
            """
            SELECT id
            FROM app.runtime_media
            WHERE home_player_upload_id = %s
            LIMIT 1
            """,
            (upload_id,),
        )
        row = await cur.fetchone()
    assert row
    return str(row["id"])


@pytest.mark.anyio("asyncio")
async def test_home_audio_requires_auth(async_client):
    resp = await async_client.get("/home/audio")
    assert resp.status_code == 401


@pytest.mark.anyio("asyncio")
async def test_home_upload_direct_storage_route_is_absent(async_client):
    resp = await async_client.get(f"/home/uploads/{uuid.uuid4()}")
    assert resp.status_code == 404


@pytest.mark.anyio("asyncio")
async def test_home_audio_returns_list(async_client):
    email = f"home_audio_{uuid.uuid4().hex[:6]}@example.com"
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": "Home Audio User",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()

    resp = await async_client.get(
        "/home/audio",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        params={"limit": 3},
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert "items" in payload and isinstance(payload["items"], list)
    assert len(payload["items"]) <= 3
    for item in payload["items"]:
        assert item.get("kind") in {"audio", "video"}


@pytest.mark.anyio("asyncio")
async def test_home_audio_returns_runtime_media_ids_and_playability_metadata(
    async_client,
    monkeypatch,
):
    async def fake_storage_exists(*, storage_bucket: str, storage_path: str) -> bool:
        assert storage_bucket
        assert storage_path
        return True

    monkeypatch.setattr(
        canonical_media_resolver,
        "_storage_object_exists",
        fake_storage_exists,
        raising=True,
    )

    email = f"home_audio_owner_{uuid.uuid4().hex[:6]}@example.org"
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": "Home Audio Owner",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    me_resp = await async_client.get("/auth/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    owner_id = me_resp.json()["user_id"]

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (owner_id,),
            )
            await conn.commit()

    slug = f"home-audio-published-{uuid.uuid4().hex[:8]}"
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.courses (
                      slug,
                      title,
                      is_free_intro,
                      price_amount_cents,
                      currency,
                      is_published,
                      created_by
                    )
                    VALUES (%s, %s, false, 1000, 'sek', true, %s)
                    RETURNING id
                    """,
                    (slug, f"Course {slug}", owner_id),
                )
            except errors.UndefinedColumn:
                await conn.rollback()
                await cur.execute(
                    """
                    INSERT INTO app.courses (
                      slug,
                      title,
                      is_free_intro,
                      price_cents,
                      currency,
                      is_published,
                      created_by
                    )
                    VALUES (%s, %s, false, 1000, 'sek', true, %s)
                    RETURNING id
                    """,
                    (slug, f"Course {slug}", owner_id),
                )
            row = await cur.fetchone()
            await conn.commit()
    course_id = str(row[0])

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.lessons (course_id, title, position, is_intro)
                VALUES (%s, %s, 0, false)
                RETURNING id
                """,
                (course_id, "Lesson"),
            )
            row = await cur.fetchone()
            await conn.commit()
    lesson_id = str(row[0])

    media_asset = await media_assets_repo.create_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=lesson_id,
        media_type="audio",
        purpose="lesson_audio",
        ingest_format="wav",
        original_object_path="media/source/audio/courses/test.wav",
        original_content_type="audio/wav",
        original_filename="test.wav",
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
    runtime_media_id = await _runtime_media_id_for_lesson_media(lesson_media_id)

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
                ON CONFLICT (teacher_id, lesson_media_id) DO UPDATE
                  SET enabled = EXCLUDED.enabled,
                      title = EXCLUDED.title,
                      course_title_snapshot = EXCLUDED.course_title_snapshot
                """,
                (owner_id, lesson_media_id, "Home track", f"Course {slug}"),
            )
            await conn.commit()

    resp = await async_client.get(
        "/home/audio",
        headers=headers,
        params={"limit": 50},
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    items = payload.get("items") or []
    item = next((it for it in items if it.get("id") == runtime_media_id), None)
    assert item, payload
    assert item.get("runtime_media_id") == runtime_media_id
    assert item.get("source_type") == "course_link"
    assert item.get("lesson_id") == lesson_id
    assert item.get("course_id") == course_id
    assert item.get("lesson_title") == "Home track"
    assert item.get("title") == "Home track"
    assert item.get("is_playable") is False
    assert item.get("playback_state") == "processing"
    assert item.get("failure_reason") == "asset_not_ready"
    assert item.get("media_state") == "processing"
    assert item.get("content_type") == "audio/wav"
    for removed_field in (
        "media_asset_id",
        "media_id",
        "storage_bucket",
        "storage_path",
        "signed_url",
        "download_url",
    ):
        assert removed_field not in item

    await media_assets_repo.mark_media_asset_ready_from_worker(
        media_id=str(media_asset["id"]),
        streaming_object_path="media/derived/audio/courses/test.mp3",
        streaming_format="mp3",
        duration_seconds=12,
        codec="mp3",
        streaming_storage_bucket="course-media",
    )

    resp_ready = await async_client.get(
        "/home/audio",
        headers=headers,
        params={"limit": 50},
    )
    assert resp_ready.status_code == 200, resp_ready.text
    items_ready = resp_ready.json().get("items") or []
    item_ready = next((it for it in items_ready if it.get("id") == runtime_media_id), None)
    assert item_ready, resp_ready.json()
    assert item_ready.get("runtime_media_id") == runtime_media_id
    assert item_ready.get("course_id") == course_id
    assert item_ready.get("is_playable") is True
    assert item_ready.get("playback_state") == "ready"
    assert item_ready.get("failure_reason") == "ok_ready_asset"
    assert item_ready.get("media_state") == "ready"
    assert item_ready.get("content_type") == "audio/mpeg"
    for removed_field in (
        "media_asset_id",
        "media_id",
        "storage_bucket",
        "storage_path",
        "signed_url",
        "download_url",
    ):
        assert removed_field not in item_ready

    email2 = f"home_audio_other_{uuid.uuid4().hex[:6]}@example.com"
    register2 = await async_client.post(
        "/auth/register",
        json={
            "email": email2,
            "password": password,
            "display_name": "Home Audio Other",
        },
    )
    assert register2.status_code == 201, register2.text
    tokens2 = register2.json()
    resp2 = await async_client.get(
        "/home/audio",
        headers={"Authorization": f"Bearer {tokens2['access_token']}"},
        params={"limit": 50},
    )
    assert resp2.status_code == 200, resp2.text
    items2 = resp2.json().get("items") or []
    assert runtime_media_id not in {it.get("id") for it in items2}

    me2_resp = await async_client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {tokens2['access_token']}"},
    )
    assert me2_resp.status_code == 200, me2_resp.text
    other_user_id = me2_resp.json()["user_id"]
    await courses_repo.ensure_course_enrollment(other_user_id, course_id)
    resp2_enrolled = await async_client.get(
        "/home/audio",
        headers={"Authorization": f"Bearer {tokens2['access_token']}"},
        params={"limit": 50},
    )
    assert resp2_enrolled.status_code == 200, resp2_enrolled.text
    items2_enrolled = resp2_enrolled.json().get("items") or []
    assert runtime_media_id in {it.get("id") for it in items2_enrolled}


@pytest.mark.anyio("asyncio")
async def test_home_audio_direct_upload_uses_runtime_media_id(async_client, monkeypatch):
    async def fake_storage_exists(*, storage_bucket: str, storage_path: str) -> bool:
        assert storage_bucket
        assert storage_path
        return True

    monkeypatch.setattr(
        canonical_media_resolver,
        "_storage_object_exists",
        fake_storage_exists,
        raising=True,
    )

    email = f"home_audio_direct_{uuid.uuid4().hex[:6]}@example.org"
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": "Home Audio Direct",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    me_resp = await async_client.get("/auth/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    teacher_id = me_resp.json()["user_id"]

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (teacher_id,),
            )
            await conn.commit()

    media_object = await models.create_media_object(
        owner_id=teacher_id,
        storage_path=f"home-player/{teacher_id}/{uuid.uuid4().hex}.mp3",
        storage_bucket="course-media",
        content_type="audio/mpeg",
        byte_size=128,
        checksum=None,
        original_name="home-track.mp3",
    )
    assert media_object
    upload = await create_home_player_upload(
        teacher_id=teacher_id,
        media_id=str(media_object["id"]),
        media_asset_id=None,
        title="Direct track",
        kind="audio",
        active=True,
    )
    assert upload
    runtime_media_id = await _runtime_media_id_for_home_upload(str(upload["id"]))

    resp = await async_client.get(
        "/home/audio",
        headers=headers,
        params={"limit": 50},
    )
    assert resp.status_code == 200, resp.text
    items = resp.json().get("items") or []
    item = next((it for it in items if it.get("id") == runtime_media_id), None)
    assert item, resp.json()
    assert item.get("runtime_media_id") == runtime_media_id
    assert item.get("source_type") == "direct_upload"
    assert item.get("title") == "Direct track"
    assert item.get("lesson_title") == "Direct track"
    assert "lesson_id" not in item
    assert "course_id" not in item
    assert "course_title" not in item
    assert item.get("is_playable") is True
    assert item.get("playback_state") == "ready"
    assert item.get("failure_reason") == "ok_legacy_object"
    assert item.get("content_type") == "audio/mpeg"
    for removed_field in (
        "media_asset_id",
        "media_id",
        "storage_bucket",
        "storage_path",
        "signed_url",
        "download_url",
    ):
        assert removed_field not in item


@pytest.mark.anyio("asyncio")
async def test_home_audio_course_link_marks_missing_source_when_deleted(async_client):
    email = f"home_audio_source_missing_{uuid.uuid4().hex[:6]}@example.org"
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Home Audio Owner"},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    me_resp = await async_client.get("/auth/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    owner_id = me_resp.json()["user_id"]

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (owner_id,),
            )
            await conn.commit()

    slug = f"home-audio-missing-{uuid.uuid4().hex[:8]}"
    course_title = f"Course {slug}"
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.courses (
                      slug,
                      title,
                      is_free_intro,
                      price_amount_cents,
                      currency,
                      is_published,
                      created_by
                    )
                    VALUES (%s, %s, false, 1000, 'sek', true, %s)
                    RETURNING id
                    """,
                    (slug, course_title, owner_id),
                )
            except errors.UndefinedColumn:
                await conn.rollback()
                await cur.execute(
                    """
                    INSERT INTO app.courses (
                      slug,
                      title,
                      is_free_intro,
                      price_cents,
                      currency,
                      is_published,
                      created_by
                    )
                    VALUES (%s, %s, false, 1000, 'sek', true, %s)
                    RETURNING id
                    """,
                    (slug, course_title, owner_id),
                )
            row = await cur.fetchone()
            await conn.commit()
    course_id = str(row[0])

    lesson = await courses_repo.create_lesson(
        course_id,
        title="Lesson",
        position=0,
        is_intro=False,
    )
    assert lesson
    lesson_id = str(lesson["id"])

    media_object = await models.create_media_object(
        owner_id=owner_id,
        storage_path=f"{uuid.uuid4().hex}.mp3",
        storage_bucket="lesson-media",
        content_type="audio/mpeg",
        byte_size=3,
        checksum=None,
        original_name="demo.mp3",
    )
    assert media_object
    media_asset = await media_assets_repo.create_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=lesson_id,
        media_type="audio",
        purpose="lesson_audio",
        ingest_format="mp3",
        original_object_path=media_object["storage_path"],
        original_content_type="audio/mpeg",
        original_filename="demo.mp3",
        original_size_bytes=3,
        storage_bucket=media_object["storage_bucket"],
        state="processing",
    )
    assert media_asset
    lesson_media = await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind="audio",
        storage_path=media_object["storage_path"],
        storage_bucket=media_object["storage_bucket"],
        media_id=str(media_object["id"]),
        media_asset_id=str(media_asset["id"]),
        position=1,
    )
    assert lesson_media
    lesson_media_id = str(lesson_media["id"])
    runtime_media_id = await _runtime_media_id_for_lesson_media(lesson_media_id)

    create_link_resp = await async_client.post(
        "/studio/home-player/course-links",
        json={"lesson_media_id": lesson_media_id, "title": "Home track", "enabled": True},
        headers=headers,
    )
    assert create_link_resp.status_code == 201, create_link_resp.text
    link_id = create_link_resp.json()["id"]

    library_before = await async_client.get("/studio/home-player/library", headers=headers)
    assert library_before.status_code == 200, library_before.text
    link_before = next(
        (it for it in library_before.json().get("course_links") or [] if it.get("id") == link_id),
        None,
    )
    assert link_before, library_before.json()
    assert link_before.get("status") == "active"
    assert link_before.get("lesson_media_id") == lesson_media_id

    feed_before = await async_client.get("/home/audio", headers=headers, params={"limit": 50})
    assert feed_before.status_code == 200, feed_before.text
    assert runtime_media_id in {it.get("id") for it in feed_before.json().get("items") or []}

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.lesson_media WHERE id = %s", (lesson_media_id,))
            await conn.commit()

    library_after = await async_client.get("/studio/home-player/library", headers=headers)
    assert library_after.status_code == 200, library_after.text
    link_after = next(
        (it for it in library_after.json().get("course_links") or [] if it.get("id") == link_id),
        None,
    )
    assert link_after, library_after.json()
    assert link_after.get("status") == "source_missing"
    assert link_after.get("lesson_media_id") is None

    feed_after = await async_client.get("/home/audio", headers=headers, params={"limit": 50})
    assert feed_after.status_code == 200, feed_after.text
    assert runtime_media_id not in {it.get("id") for it in feed_after.json().get("items") or []}
