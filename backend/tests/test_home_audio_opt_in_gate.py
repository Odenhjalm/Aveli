from datetime import datetime, timedelta, timezone
import uuid

import pytest

from app import db, repositories
from app.routes import studio as studio_routes
from app.services import courses_service, home_audio_service

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _source_timestamp(*, minutes_ago: int = 0) -> datetime:
    return datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)


async def register_user(
    client,
    email: str,
    password: str,
    display_name: str,
) -> tuple[str, str]:
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    token = tokens["access_token"]
    headers = auth_header(token)

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
    return token, user_id


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


def _find_item_by_media_id(items: list[dict], media_asset_id: str) -> dict | None:
    return next(
        (
            item
            for item in items
            if str((item.get("media") or {}).get("media_id") or "") == media_asset_id
        ),
        None,
    )


async def test_home_audio_requires_teacher_opt_in_before_entitlements(
    async_client,
    monkeypatch,
):
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client,
        f"home_gate_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    student_token, student_id = await register_user(
        async_client,
        f"home_gate_student_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    course_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    lesson_media_id = str(uuid.uuid4())
    media_asset_id = str(uuid.uuid4())
    lesson_id_value = lesson_id
    media_asset_id_value = media_asset_id
    link_rows: dict[str, dict] = {}
    allowed_users = {teacher_id}

    async def fake_resolve_owner(candidate_lesson_media_id: str):
        assert candidate_lesson_media_id == lesson_media_id
        return {
            "teacher_id": teacher_id,
            "course_title": "Course home-gate",
            "course_is_published": True,
            "media_type": "audio",
        }

    async def fake_upsert_link(
        *,
        teacher_id: str,
        lesson_media_id: str,
        title: str,
        course_title_snapshot: str,
        enabled: bool,
    ):
        row = {
            "id": str(uuid.uuid4()),
            "teacher_id": teacher_id,
            "lesson_media_id": lesson_media_id,
            "title": title,
            "course_title": course_title_snapshot,
            "enabled": enabled,
            "status": "active",
            "kind": "audio",
            "created_at": _source_timestamp(minutes_ago=2),
            "updated_at": _source_timestamp(minutes_ago=2),
        }
        link_rows[row["id"]] = row
        return row

    async def fake_update_link(*, link_id: str, teacher_id: str, fields: dict):
        row = link_rows.get(link_id)
        if row is None or row["teacher_id"] != teacher_id:
            return None
        row.update(fields)
        row["updated_at"] = _source_timestamp()
        return row

    async def fake_list_direct_uploads(*, limit: int = 100):
        return []

    async def fake_list_course_links(*, limit: int = 100):
        if not link_rows:
            return []
        row = next(iter(link_rows.values()))
        if not row.get("enabled"):
            return []
        return [
            {
                "teacher_id": teacher_id,
                "title": row["title"],
                "created_at": row["created_at"],
                "teacher_name": "Teacher",
                "lesson_id": lesson_id,
                "course_id": course_id,
                "lesson_title": "Lesson",
                "course_title": row["course_title"],
                "course_slug": "home-gate-course",
                "media_asset_id": media_asset_id,
                "media_state": "uploaded",
            }
        ]

    async def fake_read_access(user_id: str, candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return {"lesson": {"id": lesson_id}, "can_access": user_id in allowed_users}

    async def fake_get_lesson_runtime_media(
        *,
        lesson_id: str,
        media_asset_id: str,
    ):
        assert lesson_id == lesson_id_value
        assert media_asset_id == media_asset_id_value
        return {
            "media_type": "audio",
            "playback_object_path": None,
            "playback_format": None,
            "state": "uploaded",
        }

    monkeypatch.setattr(
        studio_routes.home_audio_sources_repo,
        "resolve_lesson_media_course_owner",
        fake_resolve_owner,
        raising=True,
    )
    monkeypatch.setattr(
        studio_routes.home_audio_sources_repo,
        "upsert_home_player_course_link",
        fake_upsert_link,
        raising=True,
    )
    monkeypatch.setattr(
        studio_routes.home_audio_sources_repo,
        "update_home_player_course_link",
        fake_update_link,
        raising=True,
    )
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
        courses_service,
        "read_canonical_lesson_access",
        fake_read_access,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_lesson_runtime_media",
        fake_get_lesson_runtime_media,
        raising=True,
    )

    resp_off = await async_client.get("/home/audio", headers=auth_header(teacher_token))
    assert resp_off.status_code == 200, resp_off.text
    assert _find_item_by_media_id(resp_off.json().get("items") or [], media_asset_id) is None

    create_link = await async_client.post(
        "/studio/home-player/course-links",
        headers=auth_header(teacher_token),
        json={
            "lesson_media_id": lesson_media_id,
            "title": "Home track",
            "enabled": True,
        },
    )
    assert create_link.status_code == 201, create_link.text
    link_id = str(create_link.json()["id"])

    resp_on = await async_client.get("/home/audio", headers=auth_header(teacher_token))
    assert resp_on.status_code == 200, resp_on.text
    teacher_item = _find_item_by_media_id(resp_on.json().get("items") or [], media_asset_id)
    assert teacher_item
    assert teacher_item["source_type"] == "course_link"
    assert teacher_item["media"]["media_id"] == media_asset_id
    assert teacher_item["media"]["state"] == "uploaded"

    resp_student = await async_client.get("/home/audio", headers=auth_header(student_token))
    assert resp_student.status_code == 200, resp_student.text
    assert _find_item_by_media_id(resp_student.json().get("items") or [], media_asset_id) is None

    allowed_users.add(student_id)
    resp_student_enrolled = await async_client.get(
        "/home/audio",
        headers=auth_header(student_token),
    )
    assert resp_student_enrolled.status_code == 200, resp_student_enrolled.text
    student_item = _find_item_by_media_id(
        resp_student_enrolled.json().get("items") or [],
        media_asset_id,
    )
    assert student_item
    assert student_item["media"]["media_id"] == media_asset_id

    patch_resp = await async_client.patch(
        f"/studio/home-player/course-links/{link_id}",
        headers=auth_header(teacher_token),
        json={"enabled": False},
    )
    assert patch_resp.status_code == 200, patch_resp.text
    assert patch_resp.json()["enabled"] is False

    resp_disabled = await async_client.get("/home/audio", headers=auth_header(teacher_token))
    assert resp_disabled.status_code == 200, resp_disabled.text
    assert _find_item_by_media_id(resp_disabled.json().get("items") or [], media_asset_id) is None


async def test_home_audio_course_links_reject_non_audio_lesson_media(
    async_client,
    monkeypatch,
):
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client,
        f"home_video_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    lesson_media_id = str(uuid.uuid4())

    async def fake_resolve_owner(candidate_lesson_media_id: str):
        assert candidate_lesson_media_id == lesson_media_id
        return {
            "teacher_id": teacher_id,
            "course_title": "Course",
            "course_is_published": True,
            "media_type": "video",
        }

    monkeypatch.setattr(
        studio_routes.home_audio_sources_repo,
        "resolve_lesson_media_course_owner",
        fake_resolve_owner,
        raising=True,
    )

    create_link = await async_client.post(
        "/studio/home-player/course-links",
        headers=auth_header(teacher_token),
        json={
            "lesson_media_id": lesson_media_id,
            "title": "Home video",
            "enabled": True,
        },
    )
    assert create_link.status_code == 422, create_link.text
    assert create_link.json()["detail"] == "Only audio can be linked"
