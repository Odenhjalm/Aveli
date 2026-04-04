from datetime import datetime, timedelta, timezone
import uuid

import pytest
from fastapi import HTTPException

from app import db, models
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
from app.services import home_audio_service
from app.services import lesson_playback_service
from app.services import storage_service as storage_module


def _auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


class _FakePlaybackStorageClient:
    def __init__(self, url: str):
        self._url = url

    async def get_presigned_url(
        self,
        path,
        ttl,
        filename=None,
        *,
        download=False,
    ):
        assert path
        assert ttl > 0
        assert filename
        assert download is False
        return storage_module.PresignedUrl(
            url=self._url,
            expires_in=300,
            headers={},
        )


async def _register_user(
    async_client,
    *,
    email: str,
    password: str,
    display_name: str,
) -> tuple[dict[str, str], str]:
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = _auth_header(tokens["access_token"])

    me_resp = await async_client.get("/profiles/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    return headers, me_resp.json()["user_id"]


async def _promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def _insert_published_course(*, owner_id: str, slug: str, title: str) -> str:
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
                    (slug, title, owner_id),
                )
            except Exception:
                await conn.rollback()
                await cur.execute(
                    """
                    INSERT INTO app.courses (
                      slug,
                      title,
                      price_amount_cents,
                      currency,
                      is_published,
                      created_by
                    )
                    VALUES (%s, %s, 1000, 'sek', true, %s)
                    RETURNING id
                    """,
                    (slug, title, owner_id),
                )
            row = await cur.fetchone()
            await conn.commit()
    return str(row[0])


async def _insert_media_asset(
    *,
    owner_id: str,
    media_type: str,
    purpose: str,
    state: str,
    original_object_path: str,
    ingest_format: str,
    course_id: str | None = None,
    lesson_id: str | None = None,
    original_content_type: str | None = None,
    original_filename: str | None = None,
    original_size_bytes: int | None = None,
    storage_bucket: str = "course-media",
) -> dict:
    media_asset_id = str(uuid.uuid4())
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.media_assets (
                  id,
                  owner_id,
                  course_id,
                  lesson_id,
                  media_type,
                  ingest_format,
                  original_object_path,
                  original_content_type,
                  original_filename,
                  original_size_bytes,
                  storage_bucket,
                  state,
                  purpose
                )
                VALUES (
                  %s::uuid,
                  %s::uuid,
                  %s::uuid,
                  %s::uuid,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s
                )
                """,
                (
                    media_asset_id,
                    owner_id,
                    course_id,
                    lesson_id,
                    media_type,
                    ingest_format,
                    original_object_path,
                    original_content_type,
                    original_filename,
                    original_size_bytes,
                    storage_bucket,
                    state,
                    purpose,
                ),
            )
            await conn.commit()
    asset = await media_assets_repo.get_media_asset_access(media_asset_id)
    assert asset is not None
    return asset


async def _create_lesson_audio_source(
    *,
    owner_id: str,
    course_id: str,
    lesson_title: str,
    media_state: str,
    broken_ready: bool = False,
) -> tuple[str, dict, dict]:
    lesson = await courses_repo.create_lesson(
        course_id,
        title=lesson_title,
        position=0,
        is_intro=False,
    )
    assert lesson
    lesson_id = str(lesson["id"])

    initial_state = "uploaded" if media_state == "ready" else media_state
    asset = await _insert_media_asset(
        owner_id=owner_id,
        media_type="audio",
        purpose="lesson_audio",
        state=initial_state,
        original_object_path=f"media/source/audio/courses/{course_id}/{uuid.uuid4().hex}.wav",
        ingest_format="wav",
        course_id=course_id,
        lesson_id=lesson_id,
        original_content_type="audio/wav",
        original_filename="lesson.wav",
        original_size_bytes=128,
    )
    assert asset

    if media_state == "ready":
        if broken_ready:
            async with db.pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        """
                        UPDATE app.media_assets
                           SET state = 'ready',
                               updated_at = now()
                         WHERE id = %s::uuid
                        """,
                        (str(asset["id"]),),
                    )
                    await conn.commit()
        else:
            await media_assets_repo.mark_media_asset_ready_from_worker(
                media_id=str(asset["id"]),
                streaming_object_path=(
                    f"media/derived/audio/courses/{course_id}/{uuid.uuid4().hex}.mp3"
                ),
                streaming_format="mp3",
                duration_seconds=12,
                codec="mp3",
                streaming_storage_bucket="course-media",
            )

    lesson_media = await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind="audio",
        storage_path=None,
        storage_bucket="course-media",
        media_id=None,
        media_asset_id=str(asset["id"]),
        position=1,
        duration_seconds=None,
    )
    assert lesson_media
    return lesson_id, asset, lesson_media


async def _create_home_audio_asset(
    *,
    owner_id: str,
    media_state: str,
    broken_ready: bool = False,
) -> dict:
    initial_state = "uploaded" if media_state == "ready" else media_state
    asset = await _insert_media_asset(
        owner_id=owner_id,
        media_type="audio",
        purpose="home_player_audio",
        state=initial_state,
        original_object_path=f"media/source/audio/home/{uuid.uuid4().hex}.wav",
        ingest_format="wav",
        original_content_type="audio/wav",
        original_filename="home.wav",
        original_size_bytes=256,
    )
    assert asset

    if media_state == "ready":
        if broken_ready:
            async with db.pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        """
                        UPDATE app.media_assets
                           SET state = 'ready',
                               updated_at = now()
                         WHERE id = %s::uuid
                        """,
                        (str(asset["id"]),),
                    )
                    await conn.commit()
        else:
            await media_assets_repo.mark_media_asset_ready_from_worker(
                media_id=str(asset["id"]),
                streaming_object_path=f"media/derived/audio/home/{uuid.uuid4().hex}.mp3",
                streaming_format="mp3",
                duration_seconds=91,
                codec="mp3",
                streaming_storage_bucket="course-media",
            )

    return asset


def _find_item_by_media_id(items: list[dict], media_asset_id: str) -> dict | None:
    return next(
        (
            item
            for item in items
            if str((item.get("media") or {}).get("media_id") or "") == media_asset_id
        ),
        None,
    )


def _assert_no_legacy_home_audio_fields(item: dict) -> None:
    for field in (
        "id",
        "runtime_media_id",
        "playback_state",
        "failure_reason",
        "media_state",
        "content_type",
        "is_playable",
        "media_asset_id",
        "media_id",
        "storage_bucket",
        "storage_path",
        "signed_url",
        "download_url",
        ):
            assert field not in item


def _source_timestamp(*, minutes_ago: int = 0) -> datetime:
    return datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)


@pytest.mark.anyio("asyncio")
async def test_home_audio_requires_auth(async_client):
    resp = await async_client.get("/home/audio")
    assert resp.status_code == 401


@pytest.mark.anyio("asyncio")
async def test_home_upload_direct_storage_route_is_absent(async_client):
    resp = await async_client.get(f"/home/uploads/{uuid.uuid4()}")
    assert resp.status_code == 404


@pytest.mark.anyio("asyncio")
async def test_home_audio_returns_items_with_canonical_nested_media(async_client, monkeypatch):
    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_owner_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Home Audio Owner",
    )
    await _promote_to_teacher(teacher_id)

    slug = f"home-audio-{uuid.uuid4().hex[:8]}"
    course_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    media_asset_id = str(uuid.uuid4())
    accessible_users = {teacher_id}
    course_link_rows = [
        {
            "teacher_id": teacher_id,
            "title": "Home track",
            "created_at": _source_timestamp(minutes_ago=5),
            "teacher_name": "Home Audio Owner",
            "lesson_id": lesson_id,
            "course_id": course_id,
            "lesson_title": "Lesson",
            "course_title": "Home Audio Course",
            "course_slug": slug,
            "media_asset_id": media_asset_id,
            "media_state": "processing",
        }
    ]

    async def fake_list_direct_uploads(*, limit: int = 100):
        return []

    async def fake_list_course_links(*, limit: int = 100):
        return list(course_link_rows[:limit])

    async def fake_read_access(user_id: str, candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return {
            "lesson": {"id": lesson_id},
            "can_access": user_id in accessible_users,
        }

    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_direct_upload_sources",
        fake_list_direct_uploads,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_course_link_sources",
        fake_list_course_links,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.courses_service,
        "read_canonical_lesson_access",
        fake_read_access,
        raising=True,
    )

    teacher_resp = await async_client.get(
        "/home/audio",
        headers=teacher_headers,
        params={"limit": 50},
    )
    assert teacher_resp.status_code == 200, teacher_resp.text
    payload = teacher_resp.json()
    item = _find_item_by_media_id(payload.get("items") or [], media_asset_id)
    assert item, payload
    assert item["source_type"] == "course_link"
    assert item["title"] == "Home track"
    assert item["lesson_title"] == "Lesson"
    assert item["course_id"] == course_id
    assert item["course_title"] == "Home Audio Course"
    assert item["course_slug"] == slug
    assert item["teacher_id"] == teacher_id
    assert item["media"]["media_id"] == media_asset_id
    assert item["media"]["state"] == "processing"
    _assert_no_legacy_home_audio_fields(item)

    other_headers, other_user_id = await _register_user(
        async_client,
        email=f"home_audio_other_{uuid.uuid4().hex[:6]}@example.com",
        password="Passw0rd!",
        display_name="Home Audio Other",
    )
    other_resp = await async_client.get(
        "/home/audio",
        headers=other_headers,
        params={"limit": 50},
    )
    assert other_resp.status_code == 200, other_resp.text
    assert _find_item_by_media_id(other_resp.json().get("items") or [], media_asset_id) is None

    accessible_users.add(other_user_id)
    enrolled_resp = await async_client.get(
        "/home/audio",
        headers=other_headers,
        params={"limit": 50},
    )
    assert enrolled_resp.status_code == 200, enrolled_resp.text
    enrolled_item = _find_item_by_media_id(
        enrolled_resp.json().get("items") or [],
        media_asset_id,
    )
    assert enrolled_item
    assert enrolled_item["media"]["media_id"] == media_asset_id

    async def fake_resolve_media_asset_playback(*, media_asset_id: str):
        assert media_asset_id
        return {"resolved_url": "https://stream.local/home-track.mp3"}

    monkeypatch.setattr(
        home_audio_service.lesson_playback_service,
        "resolve_media_asset_playback",
        fake_resolve_media_asset_playback,
        raising=True,
    )
    course_link_rows[0]["media_state"] = "ready"

    ready_resp = await async_client.get(
        "/home/audio",
        headers=teacher_headers,
        params={"limit": 50},
    )
    assert ready_resp.status_code == 200, ready_resp.text
    ready_item = _find_item_by_media_id(
        ready_resp.json().get("items") or [],
        media_asset_id,
    )
    assert ready_item
    assert ready_item["media"]["state"] == "ready"
    assert ready_item["media"]["resolved_url"] == "https://stream.local/home-track.mp3"
    assert lesson_id


@pytest.mark.anyio("asyncio")
async def test_home_audio_direct_upload_uses_media_asset_identity_only(async_client, monkeypatch):
    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_direct_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Home Audio Direct",
    )
    await _promote_to_teacher(teacher_id)

    media_asset_id = str(uuid.uuid4())
    direct_rows = [
        {
            "teacher_id": teacher_id,
            "title": "Direct track",
            "created_at": _source_timestamp(minutes_ago=1),
            "teacher_name": "Home Audio Direct",
            "media_asset_id": media_asset_id,
            "media_state": "ready",
        }
    ]

    async def fake_list_direct_uploads(*, limit: int = 100):
        return list(direct_rows[:limit])

    async def fake_list_course_links(*, limit: int = 100):
        return []

    async def fake_resolve_media_asset_playback(*, media_asset_id: str):
        assert media_asset_id == direct_rows[0]["media_asset_id"]
        return {"resolved_url": "https://stream.local/direct-track.mp3"}

    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_direct_upload_sources",
        fake_list_direct_uploads,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_course_link_sources",
        fake_list_course_links,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.lesson_playback_service,
        "resolve_media_asset_playback",
        fake_resolve_media_asset_playback,
        raising=True,
    )

    feed_resp = await async_client.get(
        "/home/audio",
        headers=teacher_headers,
        params={"limit": 50},
    )
    assert feed_resp.status_code == 200, feed_resp.text
    item = _find_item_by_media_id(feed_resp.json().get("items") or [], media_asset_id)
    assert item, feed_resp.json()
    assert item["source_type"] == "direct_upload"
    assert item["title"] == "Direct track"
    assert item["teacher_id"] == teacher_id
    assert item["lesson_title"] is None
    assert item["course_id"] is None
    assert item["course_title"] is None
    assert item["course_slug"] is None
    assert item["media"]["media_id"] == media_asset_id
    assert item["media"]["state"] == "ready"
    assert item["media"]["resolved_url"] == "https://stream.local/direct-track.mp3"
    _assert_no_legacy_home_audio_fields(item)

    other_headers, _ = await _register_user(
        async_client,
        email=f"home_audio_hidden_{uuid.uuid4().hex[:6]}@example.com",
        password="Passw0rd!",
        display_name="Home Audio Hidden",
    )
    hidden_resp = await async_client.get(
        "/home/audio",
        headers=other_headers,
        params={"limit": 50},
    )
    assert hidden_resp.status_code == 200, hidden_resp.text
    assert _find_item_by_media_id(hidden_resp.json().get("items") or [], media_asset_id) is None


@pytest.mark.anyio("asyncio")
async def test_home_audio_course_link_disappears_when_source_deleted(async_client, monkeypatch):
    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_missing_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Home Audio Owner",
    )
    await _promote_to_teacher(teacher_id)

    media_asset_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    rows = [
        {
            "teacher_id": teacher_id,
            "title": "Home track",
            "created_at": _source_timestamp(minutes_ago=3),
            "teacher_name": "Home Audio Owner",
            "lesson_id": lesson_id,
            "course_id": str(uuid.uuid4()),
            "lesson_title": "Lesson",
            "course_title": "Course",
            "course_slug": "course",
            "media_asset_id": media_asset_id,
            "media_state": "processing",
        }
    ]

    async def fake_list_direct_uploads(*, limit: int = 100):
        return []

    async def fake_list_course_links(*, limit: int = 100):
        return list(rows[:limit])

    async def fake_read_access(user_id: str, candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return {"lesson": {"id": lesson_id}, "can_access": user_id == teacher_id}

    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_direct_upload_sources",
        fake_list_direct_uploads,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_course_link_sources",
        fake_list_course_links,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.courses_service,
        "read_canonical_lesson_access",
        fake_read_access,
        raising=True,
    )

    feed_before = await async_client.get(
        "/home/audio",
        headers=teacher_headers,
        params={"limit": 50},
    )
    assert feed_before.status_code == 200, feed_before.text
    assert _find_item_by_media_id(feed_before.json().get("items") or [], media_asset_id)

    rows.clear()

    feed_after = await async_client.get(
        "/home/audio",
        headers=teacher_headers,
        params={"limit": 50},
    )
    assert feed_after.status_code == 200, feed_after.text
    assert _find_item_by_media_id(feed_after.json().get("items") or [], media_asset_id) is None


@pytest.mark.anyio("asyncio")
async def test_home_audio_non_ready_items_return_resolved_url_null(async_client, monkeypatch):
    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_non_ready_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Home Audio Non Ready",
    )
    await _promote_to_teacher(teacher_id)

    media_asset_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())

    async def fake_list_direct_uploads(*, limit: int = 100):
        return []

    async def fake_list_course_links(*, limit: int = 100):
        return [
            {
                "teacher_id": teacher_id,
                "title": "Not ready track",
                "created_at": _source_timestamp(minutes_ago=2),
                "teacher_name": "Home Audio Non Ready",
                "lesson_id": lesson_id,
                "course_id": str(uuid.uuid4()),
                "lesson_title": "Lesson",
                "course_title": "Home Audio Non Ready Course",
                "course_slug": f"home-audio-non-ready-{uuid.uuid4().hex[:8]}",
                "media_asset_id": media_asset_id,
                "media_state": "uploaded",
            }
        ]

    async def fake_read_access(user_id: str, candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return {"lesson": {"id": lesson_id}, "can_access": user_id == teacher_id}

    async def should_not_resolve(*, media_asset_id: str):
        raise AssertionError(f"non-ready media should not resolve: {media_asset_id}")

    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_direct_upload_sources",
        fake_list_direct_uploads,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_course_link_sources",
        fake_list_course_links,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.courses_service,
        "read_canonical_lesson_access",
        fake_read_access,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.lesson_playback_service,
        "resolve_media_asset_playback",
        should_not_resolve,
        raising=True,
    )

    feed_resp = await async_client.get(
        "/home/audio",
        headers=teacher_headers,
        params={"limit": 50},
    )
    assert feed_resp.status_code == 200, feed_resp.text
    item = _find_item_by_media_id(feed_resp.json().get("items") or [], media_asset_id)
    assert item, feed_resp.json()
    assert item["media"]["media_id"] == media_asset_id
    assert item["media"]["state"] == "uploaded"
    assert "resolved_url" in item["media"]
    assert item["media"]["resolved_url"] is None


@pytest.mark.anyio("asyncio")
async def test_home_audio_invalid_ready_items_are_excluded(async_client, monkeypatch):
    teacher_headers, teacher_id = await _register_user(
        async_client,
        email=f"home_audio_invalid_ready_{uuid.uuid4().hex[:6]}@example.org",
        password="Passw0rd!",
        display_name="Home Audio Invalid Ready",
    )
    await _promote_to_teacher(teacher_id)

    good_media_asset_id = str(uuid.uuid4())
    bad_media_asset_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())

    async def fake_list_direct_uploads(*, limit: int = 100):
        return []

    async def fake_list_course_links(*, limit: int = 100):
        return [
            {
                "teacher_id": teacher_id,
                "title": "Good track",
                "created_at": _source_timestamp(minutes_ago=2),
                "teacher_name": "Home Audio Invalid Ready",
                "lesson_id": lesson_id,
                "course_id": str(uuid.uuid4()),
                "lesson_title": "Good Lesson",
                "course_title": "Home Audio Invalid Ready Course",
                "course_slug": f"home-audio-invalid-{uuid.uuid4().hex[:8]}",
                "media_asset_id": good_media_asset_id,
                "media_state": "ready",
            },
            {
                "teacher_id": teacher_id,
                "title": "Bad track",
                "created_at": _source_timestamp(minutes_ago=1),
                "teacher_name": "Home Audio Invalid Ready",
                "lesson_id": lesson_id,
                "course_id": str(uuid.uuid4()),
                "lesson_title": "Bad Lesson",
                "course_title": "Home Audio Invalid Ready Course",
                "course_slug": f"home-audio-invalid-{uuid.uuid4().hex[:8]}",
                "media_asset_id": bad_media_asset_id,
                "media_state": "ready",
            },
        ]

    async def fake_read_access(user_id: str, candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return {"lesson": {"id": lesson_id}, "can_access": user_id == teacher_id}

    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_direct_upload_sources",
        fake_list_direct_uploads,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.home_audio_runtime_repo,
        "list_home_audio_course_link_sources",
        fake_list_course_links,
        raising=True,
    )
    monkeypatch.setattr(
        home_audio_service.courses_service,
        "read_canonical_lesson_access",
        fake_read_access,
        raising=True,
    )

    async def fake_resolve_media_asset_playback(*, media_asset_id: str):
        if media_asset_id == good_media_asset_id:
            return {"resolved_url": "https://stream.local/good-track.mp3"}
        raise HTTPException(status_code=503, detail="Streaming asset unavailable")

    monkeypatch.setattr(
        home_audio_service.lesson_playback_service,
        "resolve_media_asset_playback",
        fake_resolve_media_asset_playback,
        raising=True,
    )

    feed_resp = await async_client.get(
        "/home/audio",
        headers=teacher_headers,
        params={"limit": 50},
    )
    assert feed_resp.status_code == 200, feed_resp.text
    items = feed_resp.json().get("items") or []
    assert _find_item_by_media_id(items, good_media_asset_id)
    assert _find_item_by_media_id(items, bad_media_asset_id) is None
