import uuid

import pytest

from psycopg import errors

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
        f"media_owner_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Owner",
    )
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
    module = await courses_repo.create_module(course_id, title="Module", position=0)
    assert module
    lesson = await courses_repo.create_lesson(
        str(module["id"]),
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
