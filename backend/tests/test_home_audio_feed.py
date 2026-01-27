import uuid

import pytest

from psycopg import errors

from app import db, models
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo


@pytest.mark.anyio("asyncio")
async def test_home_audio_requires_auth(async_client):
    resp = await async_client.get("/home/audio")
    assert resp.status_code == 401


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
        assert item.get("kind") == "audio"


@pytest.mark.anyio("asyncio")
async def test_home_audio_excludes_processing_pipeline_audio_until_ready(async_client):
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

    module = await courses_repo.create_module(course_id, title="Module", position=0)
    assert module
    lesson = await courses_repo.create_lesson(
        str(module["id"]),
        title="Lesson",
        position=0,
        is_intro=False,
    )
    assert lesson

    media_asset = await media_assets_repo.create_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=str(lesson["id"]),
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
        lesson_id=str(lesson["id"]),
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
    media_asset_id = str(media_asset["id"])

    resp = await async_client.get(
        "/home/audio",
        headers=headers,
        params={"limit": 50},
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    items = payload.get("items") or []
    item = next((it for it in items if it.get("id") == lesson_media_id), None)
    assert item is None, payload

    await media_assets_repo.mark_media_asset_ready(
        media_id=media_asset_id,
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
    item_ready = next((it for it in items_ready if it.get("id") == lesson_media_id), None)
    assert item_ready, resp_ready.json()
    assert item_ready.get("course_id") == course_id
    assert item_ready.get("media_asset_id") == media_asset_id
    assert item_ready.get("media_state") == "ready"
    assert item_ready.get("storage_path") == "media/derived/audio/courses/test.mp3"

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
    assert lesson_media_id not in {it.get("id") for it in items2}
