import uuid

import pytest

from psycopg import errors

from app.config import settings
from app import db, models
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(client, email: str, password: str, display_name: str) -> tuple[str, str]:
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    me_resp = await client.get("/auth/me", headers=auth_header(tokens["access_token"]))
    assert me_resp.status_code == 200, me_resp.text
    return tokens["access_token"], me_resp.json()["user_id"]


async def promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def insert_course(
    *,
    slug: str,
    title: str,
    owner_id: str,
    is_published: bool,
    is_free_intro: bool = False,
) -> str:
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
                    VALUES (%s, %s, %s, 1000, 'sek', %s, %s)
                    RETURNING id
                    """,
                    (slug, title, is_free_intro, is_published, owner_id),
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
                    VALUES (%s, %s, %s, 1000, 'sek', %s, %s)
                    RETURNING id
                    """,
                    (slug, title, is_free_intro, is_published, owner_id),
                )
            row = await cur.fetchone()
            await conn.commit()
    assert row
    return str(row[0])


async def test_public_course_list_only_shows_published(async_client):
    password = "Passw0rd!"
    owner_token, owner_id = await register_user(
        async_client,
        f"course_owner_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Owner",
    )

    published_id = await insert_course(
        slug=f"published-{uuid.uuid4().hex[:8]}",
        title="Published Course",
        owner_id=owner_id,
        is_published=True,
    )
    unpublished_id = await insert_course(
        slug=f"draft-{uuid.uuid4().hex[:8]}",
        title="Draft Course",
        owner_id=owner_id,
        is_published=False,
    )

    resp = await async_client.get("/courses")
    assert resp.status_code == 200, resp.text
    ids = {str(item["id"]) for item in resp.json()["items"]}
    assert published_id in ids
    assert unpublished_id not in ids

    # Public endpoint must not allow listing unpublished even if query param is provided.
    resp2 = await async_client.get("/courses", params={"published_only": False})
    assert resp2.status_code == 200, resp2.text
    ids2 = {str(item["id"]) for item in resp2.json()["items"]}
    assert published_id in ids2
    assert unpublished_id not in ids2

    # Unpublished course details must not be publicly accessible.
    detail = await async_client.get(f"/courses/{unpublished_id}", headers=auth_header(owner_token))
    assert detail.status_code == 404


async def test_published_course_visible_even_with_processing_media(async_client):
    password = "Passw0rd!"
    _, owner_id = await register_user(
        async_client,
        f"processing_owner_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Owner",
    )

    course_id = await insert_course(
        slug=f"processing-media-{uuid.uuid4().hex[:8]}",
        title="Published With Processing Media",
        owner_id=owner_id,
        is_published=True,
    )

    lesson = await courses_repo.create_lesson(
        course_id,
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
        original_object_path=f"media/source/audio/courses/{course_id}/lessons/{lesson['id']}/test.wav",
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

    resp = await async_client.get("/courses")
    assert resp.status_code == 200, resp.text
    ids = {str(item["id"]) for item in resp.json()["items"]}
    assert course_id in ids


async def test_home_audio_and_media_sign_require_enrollment(async_client):
    password = "Passw0rd!"
    owner_token, owner_id = await register_user(
        async_client,
        f"media_owner_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Owner",
    )
    await promote_to_teacher(owner_id)
    student_token, student_id = await register_user(
        async_client,
        f"media_student_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    course_id = await insert_course(
        slug=f"premium-{uuid.uuid4().hex[:8]}",
        title="Premium Course",
        owner_id=owner_id,
        is_published=True,
        is_free_intro=False,
    )
    lesson = await courses_repo.create_lesson(
        course_id,
        title="Premium Lesson",
        position=0,
        is_intro=False,
    )
    assert lesson

    # Create pipeline (WAV->MP3) audio and mark it ready.
    media_asset = await media_assets_repo.create_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=str(lesson["id"]),
        media_type="audio",
        purpose="lesson_audio",
        ingest_format="wav",
        original_object_path=f"media/source/audio/courses/{course_id}/lessons/{lesson['id']}/demo.wav",
        original_content_type="audio/wav",
        original_filename="demo.wav",
        original_size_bytes=123,
        storage_bucket="course-media",
        state="ready",
    )
    assert media_asset
    await media_assets_repo.mark_media_asset_ready(
        media_id=str(media_asset["id"]),
        streaming_object_path=f"media/derived/audio/courses/{course_id}/lessons/{lesson['id']}/demo.mp3",
        streaming_format="mp3",
        duration_seconds=12,
        codec="mp3",
        streaming_storage_bucket="course-media",
    )
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
                  SET enabled = EXCLUDED.enabled
                """,
                (owner_id, lesson_media_id, "Home audio", "Premium Course"),
            )
            await conn.commit()

    # Not enrolled => not visible in home audio feed.
    resp = await async_client.get("/home/audio", headers=auth_header(student_token))
    assert resp.status_code == 200, resp.text
    assert lesson_media_id not in {it.get("id") for it in resp.json().get("items") or []}

    # Owner can always see their own media in published courses.
    resp_owner = await async_client.get("/home/audio", headers=auth_header(owner_token))
    assert resp_owner.status_code == 200, resp_owner.text
    assert lesson_media_id in {it.get("id") for it in resp_owner.json().get("items") or []}

    # Enroll => visible in home audio feed.
    # Legacy media signing must also enforce access (403 before enrollment, 200 after).
    media_object = await models.create_media_object(
        owner_id=owner_id,
        storage_path=f"lesson-media/{uuid.uuid4().hex}.mp3",
        storage_bucket="lesson-media",
        content_type="audio/mpeg",
        byte_size=3,
        checksum=None,
        original_name="legacy.mp3",
    )
    assert media_object
    legacy_media = await models.add_lesson_media_entry(
        lesson_id=str(lesson["id"]),
        kind="audio",
        storage_path=media_object["storage_path"],
        storage_bucket=media_object["storage_bucket"],
        media_id=str(media_object["id"]),
        position=2,
    )
    assert legacy_media

    sign_denied = await async_client.post(
        "/media/sign",
        json={"media_id": str(legacy_media["id"])},
        headers=auth_header(student_token),
    )
    assert sign_denied.status_code == 403, sign_denied.text

    await courses_repo.ensure_course_enrollment(student_id, course_id)
    resp_enrolled = await async_client.get("/home/audio", headers=auth_header(student_token))
    assert resp_enrolled.status_code == 200, resp_enrolled.text
    assert lesson_media_id in {it.get("id") for it in resp_enrolled.json().get("items") or []}

    sign_ok = await async_client.post(
        "/media/sign",
        json={"media_id": str(legacy_media["id"])},
        headers=auth_header(student_token),
    )
    assert sign_ok.status_code == 200, sign_ok.text


async def test_media_sign_allows_subscription_only_access(async_client, tmp_path, monkeypatch):
    """Regression: users with active subscription can access lesson media in published courses."""
    password = "Passw0rd!"
    owner_token, owner_id = await register_user(
        async_client,
        f"sub_media_owner_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Owner",
    )
    await promote_to_teacher(owner_id)
    student_token, student_id = await register_user(
        async_client,
        f"sub_media_student_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    course_id = await insert_course(
        slug=f"subscription-media-{uuid.uuid4().hex[:8]}",
        title="Subscription Media Course",
        owner_id=owner_id,
        is_published=False,
        is_free_intro=False,
    )
    lesson = await courses_repo.create_lesson(
        course_id,
        title="Lesson",
        position=0,
        is_intro=False,
    )
    assert lesson

    # Create an image media row for the lesson.
    media_object = await models.create_media_object(
        owner_id=owner_id,
        storage_path=f"unit-tests/{uuid.uuid4().hex}.png",
        storage_bucket="lesson-media",
        content_type="image/png",
        byte_size=3,
        checksum=None,
        original_name="legacy.png",
    )
    assert media_object
    legacy_media = await models.add_lesson_media_entry(
        lesson_id=str(lesson["id"]),
        kind="image",
        storage_path=media_object["storage_path"],
        storage_bucket=media_object["storage_bucket"],
        media_id=str(media_object["id"]),
        position=1,
    )
    assert legacy_media

    monkeypatch.setattr(settings, "media_root", tmp_path.as_posix())
    local_path = tmp_path / media_object["storage_bucket"] / media_object["storage_path"]
    local_path.parent.mkdir(parents=True, exist_ok=True)
    local_path.write_bytes(b"png")

    # Grant the student an active subscription (without enrollment).
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.subscriptions (user_id, subscription_id, status)
                VALUES (%s, %s, %s)
                """,
                (student_id, f"sub_{uuid.uuid4().hex[:10]}", "active"),
            )
            await conn.commit()

    access_resp = await async_client.get(
        f"/courses/{course_id}/access",
        headers=auth_header(student_token),
    )
    assert access_resp.status_code == 200, access_resp.text
    access_payload = access_resp.json()
    print("course_access_snapshot", access_payload)
    assert access_payload["has_active_subscription"] is True
    assert access_payload["has_access"] is True
    assert access_payload["enrolled"] is False

    # Owner can sign.
    sign_owner = await async_client.post(
        "/media/sign",
        json={"media_id": str(legacy_media["id"])},
        headers=auth_header(owner_token),
    )
    assert sign_owner.status_code == 200, sign_owner.text

    # Unpublished courses must remain inaccessible even for subscription users.
    sign_unpublished = await async_client.post(
        "/media/sign",
        json={"media_id": str(legacy_media["id"])},
        headers=auth_header(student_token),
    )
    assert sign_unpublished.status_code == 403, sign_unpublished.text

    studio_get_unpublished = await async_client.get(
        f"/studio/media/{legacy_media['id']}",
        headers=auth_header(student_token),
    )
    assert studio_get_unpublished.status_code == 403, studio_get_unpublished.text

    publish_resp = await async_client.patch(
        f"/studio/courses/{course_id}",
        headers=auth_header(owner_token),
        json={"is_published": True},
    )
    assert publish_resp.status_code == 200, publish_resp.text

    # Student has access via subscription and can sign/fetch once the course is published.
    sign_ok = await async_client.post(
        "/media/sign",
        json={"media_id": str(legacy_media["id"])},
        headers=auth_header(student_token),
    )
    assert sign_ok.status_code == 200, sign_ok.text

    studio_get_ok = await async_client.get(
        f"/studio/media/{legacy_media['id']}",
        headers=auth_header(student_token),
    )
    assert studio_get_ok.status_code == 200, studio_get_ok.text
    assert studio_get_ok.content == b"png"


async def test_incomplete_subscription_does_not_grant_course_or_media_access(async_client):
    password = "Passw0rd!"
    _, owner_id = await register_user(
        async_client,
        f"incomplete_owner_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Owner",
    )
    student_token, student_id = await register_user(
        async_client,
        f"incomplete_student_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    course_id = await insert_course(
        slug=f"incomplete-subscription-{uuid.uuid4().hex[:8]}",
        title="Incomplete Subscription Course",
        owner_id=owner_id,
        is_published=True,
        is_free_intro=False,
    )
    lesson = await courses_repo.create_lesson(
        course_id,
        title="Lesson",
        position=0,
        is_intro=False,
    )
    assert lesson

    media_object = await models.create_media_object(
        owner_id=owner_id,
        storage_path=f"unit-tests/{uuid.uuid4().hex}.png",
        storage_bucket="lesson-media",
        content_type="image/png",
        byte_size=3,
        checksum=None,
        original_name="incomplete.png",
    )
    assert media_object
    legacy_media = await models.add_lesson_media_entry(
        lesson_id=str(lesson["id"]),
        kind="image",
        storage_path=media_object["storage_path"],
        storage_bucket=media_object["storage_bucket"],
        media_id=str(media_object["id"]),
        position=1,
    )
    assert legacy_media

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.subscriptions (user_id, subscription_id, status)
                VALUES (%s, %s, %s)
                """,
                (student_id, f"sub_{uuid.uuid4().hex[:10]}", "incomplete"),
            )
            await conn.commit()

    access_resp = await async_client.get(
        f"/courses/{course_id}/access",
        headers=auth_header(student_token),
    )
    assert access_resp.status_code == 200, access_resp.text
    access_payload = access_resp.json()
    assert access_payload["has_active_subscription"] is False
    assert access_payload["has_access"] is False
    assert access_payload["can_access"] is False
    assert access_payload["access_reason"] == "none"
    assert access_payload["enrolled"] is False

    lesson_detail_resp = await async_client.get(
        f"/courses/lessons/{lesson['id']}",
        headers=auth_header(student_token),
    )
    assert lesson_detail_resp.status_code == 200, lesson_detail_resp.text
    assert lesson_detail_resp.json()["media"] == []

    sign_resp = await async_client.post(
        "/media/sign",
        json={"media_id": str(legacy_media["id"])},
        headers=auth_header(student_token),
    )
    assert sign_resp.status_code == 403, sign_resp.text
