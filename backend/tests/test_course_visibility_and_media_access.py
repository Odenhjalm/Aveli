from datetime import datetime, timedelta, timezone
import uuid

import pytest

from app import db, repositories
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
from app.services import home_audio_service
pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(client, email: str, password: str, display_name: str) -> tuple[str, str]:
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = auth_header(tokens["access_token"])
    me_resp = await client.get("/profiles/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    user_id = me_resp.json()["user_id"]
    profile_resp = await client.post(
        "/auth/onboarding/create-profile",
        headers=headers,
        json={"display_name": display_name, "bio": None},
    )
    assert profile_resp.status_code == 200, profile_resp.text
    onboarding_resp = await client.post(
        "/auth/onboarding/complete",
        headers=headers,
    )
    assert onboarding_resp.status_code == 200, onboarding_resp.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )
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
    course_id = str(uuid.uuid4())
    required_enrollment_source = "intro_enrollment" if is_free_intro else "purchase"
    price_amount_cents = None if is_free_intro else 1000
    sellable = bool(is_published and not is_free_intro)
    stripe_product_id = f"prod_{uuid.uuid4().hex[:12]}" if sellable else None
    active_stripe_price_id = f"price_{uuid.uuid4().hex[:12]}" if sellable else None
    visibility = "public" if is_published else "draft"
    content_ready = is_published
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.courses (
                  id,
                  teacher_id,
                  title,
                  slug,
                  course_group_id,
                  group_position,
                  visibility,
                  content_ready,
                  required_enrollment_source,
                  price_amount_cents,
                  stripe_product_id,
                  active_stripe_price_id,
                  sellable,
                  drip_enabled,
                  drip_interval_days
                )
                VALUES (
                  %s::uuid,
                  %s::uuid,
                  %s,
                  %s,
                  %s::uuid,
                  0,
                  %s::app.course_visibility,
                  %s,
                  %s::app.course_enrollment_source,
                  %s,
                  %s,
                  %s,
                  %s,
                  false,
                  null
                )
                RETURNING id
                """,
                (
                    course_id,
                    owner_id,
                    title,
                    slug,
                    str(uuid.uuid4()),
                    visibility,
                    content_ready,
                    required_enrollment_source,
                    price_amount_cents,
                    stripe_product_id,
                    active_stripe_price_id,
                    sellable,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
    assert row
    return str(row[0])


async def insert_lesson(*, course_id: str, title: str, position: int) -> dict:
    return await courses_repo.create_lesson(
        lesson_id=None,
        course_id=course_id,
        lesson_title=title,
        content_markdown="# Lesson",
        position=max(1, position),
    )


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
    playback_object_path: str | None = None,
    playback_format: str | None = None,
) -> dict:
    del owner_id, course_id, lesson_id, original_content_type, original_filename, storage_bucket
    media_asset_id = str(uuid.uuid4())
    content_hash = f"{uuid.uuid4().hex}{uuid.uuid4().hex}"
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.media_assets (
                  id,
                  media_type,
                  purpose,
                  original_object_path,
                  ingest_format,
                  playback_object_path,
                  playback_format,
                  state,
                  file_size,
                  content_hash_algorithm,
                  content_hash
                )
                VALUES (
                  %s::uuid,
                  %s::app.media_type,
                  %s::app.media_purpose,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s::app.media_state,
                  %s,
                  'sha256',
                  %s
                )
                """,
                (
                    media_asset_id,
                    media_type,
                    purpose,
                    original_object_path,
                    ingest_format,
                    playback_object_path,
                    playback_format,
                    state,
                    original_size_bytes,
                    content_hash,
                ),
            )
            await conn.commit()
    asset = await media_assets_repo.get_media_asset_access(media_asset_id)
    assert asset is not None
    return asset


async def insert_lesson_media(*, lesson_id: str, media_asset_id: str) -> dict:
    row = await courses_repo.create_lesson_media(
        lesson_id=lesson_id,
        media_asset_id=media_asset_id,
    )
    if "id" not in row and row.get("lesson_media_id") is not None:
        row["id"] = row["lesson_media_id"]
    return row


async def upsert_membership(user_id: str, status: str) -> None:
    kwargs = {"status": status, "source": "coupon"}
    if status == "canceled":
        kwargs["expires_at"] = datetime.now(timezone.utc) - timedelta(days=1)
        kwargs["canceled_at"] = datetime.now(timezone.utc) - timedelta(days=2)
    await repositories.upsert_membership_record(user_id, **kwargs)


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

    # Canonical public detail route must stay fail-closed for unpublished courses.
    detail = await async_client.get(f"/courses/{unpublished_id}", headers=auth_header(owner_token))
    assert detail.status_code == 404


async def test_published_course_visible_even_with_processing_media(async_client):
    password = "Passw0rd!"
    owner_token, owner_id = await register_user(
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

    lesson = await insert_lesson(course_id=course_id, title="Lesson", position=0)
    assert lesson

    media_asset = await insert_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=str(lesson["id"]),
        media_type="audio",
        purpose="lesson_media",
        state="processing",
        original_object_path=f"media/source/audio/courses/{course_id}/lessons/{lesson['id']}/test.wav",
        ingest_format="wav",
        original_content_type="audio/wav",
        original_filename="test.wav",
        original_size_bytes=123,
        storage_bucket="course-media",
    )
    assert media_asset
    lesson_media = await insert_lesson_media(
        lesson_id=str(lesson["id"]),
        media_asset_id=str(media_asset["id"]),
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


async def test_active_app_membership_does_not_grant_non_intro_course_access(async_client):
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

    await upsert_membership(student_id, "active")

    access_resp = await async_client.get(
        f"/courses/{course_id}/access",
        headers=auth_header(student_token),
    )
    assert access_resp.status_code == 200, access_resp.text
    access_payload = access_resp.json()
    assert access_payload["can_access"] is False
    assert access_payload["required_enrollment_source"] == "purchase"
    assert access_payload["enrollment"] is None


async def test_active_app_membership_does_not_grant_non_intro_media_playback(
    async_client,
):
    """Regression: app-entry membership must not bypass enrollment for paid media."""
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
        is_published=True,
        is_free_intro=False,
    )
    lesson = await insert_lesson(course_id=course_id, title="Lesson", position=0)
    assert lesson

    media_asset = await insert_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=str(lesson["id"]),
        media_type="image",
        purpose="lesson_media",
        state="ready",
        original_object_path=f"media/source/lessons/{lesson['id']}/image.png",
        ingest_format="png",
        original_content_type="image/png",
        original_filename="image.png",
        original_size_bytes=3,
        storage_bucket="course-media",
        playback_object_path=f"lessons/{lesson['id']}/image.png",
        playback_format="png",
    )
    assert media_asset
    lesson_media = await insert_lesson_media(
        lesson_id=str(lesson["id"]),
        media_asset_id=str(media_asset["id"]),
    )
    assert lesson_media

    await upsert_membership(student_id, "active")

    access_resp = await async_client.get(
        f"/courses/{course_id}/access",
        headers=auth_header(student_token),
    )
    assert access_resp.status_code == 200, access_resp.text
    access_payload = access_resp.json()
    assert access_payload["can_access"] is False
    assert access_payload["required_enrollment_source"] == "purchase"
    assert access_payload["enrollment"] is None

    lesson_detail_resp = await async_client.get(
        f"/courses/lessons/{lesson['id']}",
        headers=auth_header(student_token),
    )
    assert lesson_detail_resp.status_code == 403, lesson_detail_resp.text

    legacy_media_resp = await async_client.get(
        f"/studio/media/{lesson_media['id']}",
        headers=auth_header(owner_token),
    )
    assert legacy_media_resp.status_code == 410, legacy_media_resp.text


@pytest.mark.parametrize("membership_status", ["canceled", "inactive", "past_due", "expired"])
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
    lesson = await insert_lesson(course_id=course_id, title="Lesson", position=0)
    assert lesson

    await upsert_membership(student_id, membership_status)

    access_resp = await async_client.get(
        f"/courses/{course_id}/access",
        headers=auth_header(student_token),
    )
    assert access_resp.status_code == 403, access_resp.text
    assert access_resp.json()["detail"] == "canonical_app_entry_required"

    lesson_detail_resp = await async_client.get(
        f"/courses/lessons/{lesson['id']}",
        headers=auth_header(student_token),
    )
    assert lesson_detail_resp.status_code == 403, lesson_detail_resp.text

async def test_lesson_detail_returns_unresolved_canonical_media_after_intro_enrollment(
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
    lesson = await insert_lesson(
        course_id=course_id,
        title="Broken Intro Lesson",
        position=0,
    )
    assert lesson

    media_asset = await insert_media_asset(
        owner_id=teacher_id,
        course_id=course_id,
        lesson_id=str(lesson["id"]),
        media_type="image",
        purpose="lesson_media",
        state="processing",
        original_object_path=f"media/source/lessons/{lesson['id']}/broken.png",
        ingest_format="png",
        original_content_type="image/png",
        original_filename="broken.png",
        original_size_bytes=3,
        storage_bucket="course-media",
    )
    assert media_asset
    lesson_media = await insert_lesson_media(
        lesson_id=str(lesson["id"]),
        media_asset_id=str(media_asset["id"]),
    )
    assert lesson_media

    await upsert_membership(student_id, "active")
    assert await courses_repo.is_enrolled(student_id, course_id) is False
    enroll_resp = await async_client.post(
        f"/courses/{course_id}/enroll",
        headers=auth_header(student_token),
    )
    assert enroll_resp.status_code == 200, enroll_resp.text
    assert enroll_resp.json()["can_access"] is True

    lesson_detail_resp = await async_client.get(
        f"/courses/lessons/{lesson['id']}",
        headers=auth_header(student_token),
    )
    assert lesson_detail_resp.status_code == 200, lesson_detail_resp.text

    payload = lesson_detail_resp.json()
    assert payload["lesson"]["id"] == str(lesson["id"])
    item = next(
        (
            media_item
            for media_item in (payload.get("media") or [])
            if media_item.get("id") == str(lesson_media["id"])
        ),
        None,
    )
    assert item is None
    for media_item in payload.get("media") or []:
        assert "preferredUrl" not in media_item
        assert "download_url" not in media_item
        assert "signed_url" not in media_item
        assert "signed_url_expires_at" not in media_item
    assert await courses_repo.is_enrolled(student_id, course_id) is True


async def test_lesson_detail_blocks_intro_media_without_canonical_enrollment(
    async_client,
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
    lesson = await insert_lesson(
        course_id=course_id,
        title="Broken Intro Lesson",
        position=0,
    )
    assert lesson

    media_asset = await insert_media_asset(
        owner_id=teacher_id,
        course_id=course_id,
        lesson_id=str(lesson["id"]),
        media_type="image",
        purpose="lesson_media",
        state="ready",
        original_object_path=f"media/source/lessons/{lesson['id']}/blocked.png",
        ingest_format="png",
        original_content_type="image/png",
        original_filename="blocked.png",
        original_size_bytes=3,
        storage_bucket="course-media",
        playback_object_path=f"lessons/{lesson['id']}/blocked.png",
        playback_format="png",
    )
    assert media_asset
    lesson_media = await insert_lesson_media(
        lesson_id=str(lesson["id"]),
        media_asset_id=str(media_asset["id"]),
    )
    assert lesson_media

    await upsert_membership(student_id, "active")

    lesson_detail_resp = await async_client.get(
        f"/courses/lessons/{lesson['id']}",
        headers=auth_header(student_token),
    )
    assert lesson_detail_resp.status_code == 403, lesson_detail_resp.text
