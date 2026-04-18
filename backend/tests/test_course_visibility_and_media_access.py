from datetime import datetime, timezone
import uuid

import pytest

from psycopg import errors

from app.config import settings
from app import db, models, repositories
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
from app.services import courses_service, home_audio_service
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
    me_resp = await client.get("/profiles/me", headers=auth_header(tokens["access_token"]))
    assert me_resp.status_code == 200, me_resp.text
    return tokens["access_token"], me_resp.json()["user_id"]


async def promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET role = 'teacher'
                 WHERE user_id = %s
                """,
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
                      price_amount_cents,
                      currency,
                      is_published,
                      created_by
                    )
                    VALUES (%s, %s, 1000, 'sek', %s, %s)
                    RETURNING id
                    """,
                    (slug, title, is_published, owner_id),
                )
            row = await cur.fetchone()
            await conn.commit()
    assert row
    return str(row[0])


async def insert_media_asset(
    *,
    owner_id: str,
    course_id: str,
    lesson_id: str,
    media_type: str,
    purpose: str,
    state: str,
    original_object_path: str,
    ingest_format: str,
    original_content_type: str,
    original_filename: str,
    original_size_bytes: int,
    storage_bucket: str,
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


async def upsert_membership(user_id: str, status: str) -> None:
    await repositories.upsert_membership_record(
        user_id,
        plan_interval="month",
        price_id=f"price_{status}_{uuid.uuid4().hex[:8]}",
        status=status,
        stripe_customer_id=f"cus_{uuid.uuid4().hex[:8]}",
        stripe_subscription_id=f"sub_{uuid.uuid4().hex[:8]}",
    )


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

    # Owner must keep access to their own unpublished course.
    detail = await async_client.get(f"/courses/{unpublished_id}", headers=auth_header(owner_token))
    assert detail.status_code == 200


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

    media_asset = await insert_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=str(lesson["id"]),
        media_type="audio",
        purpose="lesson_audio",
        state="processing",
        original_object_path=f"media/source/audio/courses/{course_id}/lessons/{lesson['id']}/test.wav",
        ingest_format="wav",
        original_content_type="audio/wav",
        original_filename="test.wav",
        original_size_bytes=123,
        storage_bucket="course-media",
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


def _find_home_audio_item(items: list[dict], media_asset_id: str) -> dict | None:
    return next(
        (
            item
            for item in items
            if str((item.get("media") or {}).get("media_id") or "") == media_asset_id
        ),
        None,
    )


async def test_home_audio_requires_enrollment_for_course_links(async_client, monkeypatch):
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

    course_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    media_asset_id = str(uuid.uuid4())
    expected_media_asset_id = media_asset_id
    allowed_users = {owner_id}

    async def fake_list_direct_uploads(*, limit: int = 100):
        return []

    async def fake_list_course_links(*, limit: int = 100):
        return [
            {
                "teacher_id": owner_id,
                "title": "Home audio",
                "created_at": datetime.now(timezone.utc),
                "teacher_name": "Owner",
                "lesson_id": lesson_id,
                "course_id": course_id,
                "lesson_title": "Premium Lesson",
                "course_title": "Premium Course",
                "course_slug": f"premium-{uuid.uuid4().hex[:8]}",
                "media_asset_id": media_asset_id,
                "media_state": "ready",
            }
        ]

    async def fake_read_access(user_id: str, candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return {"lesson": {"id": lesson_id}, "can_access": user_id in allowed_users}

    async def fake_resolve_media_asset_playback(*, media_asset_id: str):
        assert media_asset_id == expected_media_asset_id
        return {"resolved_url": "https://stream.local/premium.mp3"}

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
        fake_resolve_media_asset_playback,
        raising=True,
    )

    # Not enrolled => not visible in home audio feed.
    resp = await async_client.get("/home/audio", headers=auth_header(student_token))
    assert resp.status_code == 200, resp.text
    assert _find_home_audio_item(resp.json().get("items") or [], media_asset_id) is None

    # Owner can always see their own media in published courses.
    resp_owner = await async_client.get("/home/audio", headers=auth_header(owner_token))
    assert resp_owner.status_code == 200, resp_owner.text
    owner_item = _find_home_audio_item(
        resp_owner.json().get("items") or [],
        media_asset_id,
    )
    assert owner_item
    assert owner_item["source_type"] == "course_link"
    assert owner_item["media"]["media_id"] == media_asset_id
    assert owner_item["media"]["state"] == "ready"

    allowed_users.add(student_id)
    resp_enrolled = await async_client.get("/home/audio", headers=auth_header(student_token))
    assert resp_enrolled.status_code == 200, resp_enrolled.text
    enrolled_item = _find_home_audio_item(
        resp_enrolled.json().get("items") or [],
        media_asset_id,
    )
    assert enrolled_item
    assert enrolled_item["media"]["media_id"] == media_asset_id


async def test_trialing_membership_does_not_grant_non_intro_course_access(async_client):
    password = "Passw0rd!"
    _, owner_id = await register_user(
        async_client,
        f"trialing_owner_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Owner",
    )
    student_token, student_id = await register_user(
        async_client,
        f"trialing_student_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    course_id = await insert_course(
        slug=f"trialing-course-{uuid.uuid4().hex[:8]}",
        title="Trialing Course",
        owner_id=owner_id,
        is_published=True,
        is_free_intro=False,
    )

    await upsert_membership(student_id, "trialing")

    access_resp = await async_client.get(
        f"/courses/{course_id}/access",
        headers=auth_header(student_token),
    )
    assert access_resp.status_code == 200, access_resp.text
    access_payload = access_resp.json()
    assert access_payload["has_active_subscription"] is True
    assert access_payload["has_access"] is False
    assert access_payload["can_access"] is False
    assert access_payload["access_reason"] == "none"
    assert access_payload["enrolled"] is False


async def test_trialing_membership_does_not_grant_non_intro_media_playback(
    async_client, tmp_path, monkeypatch
):
    """Regression: membership metadata must not bypass enrollment for paid media."""
    password = "Passw0rd!"
    owner_token, owner_id = await register_user(
        async_client,
        f"trialing_media_owner_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Owner",
    )
    await promote_to_teacher(owner_id)
    student_token, student_id = await register_user(
        async_client,
        f"trialing_media_student_{uuid.uuid4().hex[:6]}@example.com",
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

    await upsert_membership(student_id, "trialing")

    access_resp = await async_client.get(
        f"/courses/{course_id}/access",
        headers=auth_header(student_token),
    )
    assert access_resp.status_code == 200, access_resp.text
    access_payload = access_resp.json()
    assert access_payload["has_active_subscription"] is True
    assert access_payload["has_access"] is False
    assert access_payload["enrolled"] is False

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

    studio_get_ok = await async_client.get(
        f"/studio/media/{legacy_media['id']}",
        headers=auth_header(student_token),
    )
    assert studio_get_ok.status_code == 403, studio_get_ok.text


@pytest.mark.parametrize("membership_status", ["canceled", "incomplete"])
async def test_non_active_membership_statuses_do_not_grant_course_or_media_access(
    async_client, membership_status: str
):
    password = "Passw0rd!"
    _, owner_id = await register_user(
        async_client,
        f"{membership_status}_owner_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Owner",
    )
    student_token, student_id = await register_user(
        async_client,
        f"{membership_status}_student_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    course_id = await insert_course(
        slug=f"{membership_status}-subscription-{uuid.uuid4().hex[:8]}",
        title=f"{membership_status.title()} Subscription Course",
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
        original_name=f"{membership_status}.png",
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

    await upsert_membership(student_id, membership_status)

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
    assert lesson_detail_resp.status_code == 403, lesson_detail_resp.text

async def test_lesson_detail_returns_unresolved_media_without_intro_enrollment_side_effect(
    async_client,
):
    password = "Passw0rd!"
    _, teacher_id = await register_user(
        async_client,
        f"intro_teacher_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)
    student_token, student_id = await register_user(
        async_client,
        f"intro_student_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    course_id = await insert_course(
        slug=f"intro-read-{uuid.uuid4().hex[:8]}",
        title="Intro Read Contract",
        owner_id=teacher_id,
        is_published=True,
        is_free_intro=True,
    )
    lesson = await courses_repo.create_lesson(
        course_id,
        title="Broken Intro Lesson",
        position=0,
        is_intro=True,
    )
    assert lesson

    media_object = await models.create_media_object(
        owner_id=teacher_id,
        storage_path=f"missing/{uuid.uuid4().hex}.png",
        storage_bucket="lesson-media",
        content_type="image/png",
        byte_size=3,
        checksum=None,
        original_name="broken.png",
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

    await upsert_membership(student_id, "active")
    assert await courses_repo.is_enrolled(student_id, course_id) is False

    lesson_detail_resp = await async_client.get(
        f"/courses/lessons/{lesson['id']}",
        headers=auth_header(student_token),
    )
    assert lesson_detail_resp.status_code == 200, lesson_detail_resp.text

    payload = lesson_detail_resp.json()
    assert payload["lesson"]["id"] == str(lesson["id"])
    item = next(
        media_item
        for media_item in (payload.get("media") or [])
        if media_item.get("id") == str(legacy_media["id"])
    )
    assert item["resolvable_for_student"] is False
    assert item["resolvable_for_editor"] is False
    assert "preferredUrl" not in item
    assert "download_url" not in item
    assert "signed_url" not in item
    assert "signed_url_expires_at" not in item
    assert await courses_repo.is_enrolled(student_id, course_id) is False


async def test_lesson_detail_access_check_does_not_depend_on_full_course_fetch(
    async_client,
    monkeypatch,
):
    password = "Passw0rd!"
    _, teacher_id = await register_user(
        async_client,
        f"intro_teacher_access_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)
    student_token, student_id = await register_user(
        async_client,
        f"intro_student_access_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    course_id = await insert_course(
        slug=f"intro-access-{uuid.uuid4().hex[:8]}",
        title="Intro Access Isolation",
        owner_id=teacher_id,
        is_published=True,
        is_free_intro=True,
    )
    lesson = await courses_repo.create_lesson(
        course_id,
        title="Broken Intro Lesson",
        position=0,
        is_intro=True,
    )
    assert lesson

    media_object = await models.create_media_object(
        owner_id=teacher_id,
        storage_path=f"missing/{uuid.uuid4().hex}.png",
        storage_bucket="lesson-media",
        content_type="image/png",
        byte_size=3,
        checksum=None,
        original_name="broken.png",
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

    await upsert_membership(student_id, "active")

    async def fail_fetch_course(*args, **kwargs):
        raise RuntimeError("full course read path must not be used for lesson access")

    monkeypatch.setattr(
        courses_service,
        "fetch_course",
        fail_fetch_course,
    )

    lesson_detail_resp = await async_client.get(
        f"/courses/lessons/{lesson['id']}",
        headers=auth_header(student_token),
    )
    assert lesson_detail_resp.status_code == 200, lesson_detail_resp.text

    payload = lesson_detail_resp.json()
    item = next(
        media_item
        for media_item in (payload.get("media") or [])
        if media_item.get("id") == str(legacy_media["id"])
    )
    assert item["resolvable_for_student"] is False
    assert item["resolvable_for_editor"] is False
    assert "preferredUrl" not in item
    assert "download_url" not in item
