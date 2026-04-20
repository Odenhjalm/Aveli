from datetime import datetime, timedelta, timezone
import uuid

import pytest

from app import db, repositories
from app.routes import studio as studio_routes

pytestmark = pytest.mark.anyio("asyncio")


def _source_timestamp(*, minutes_ago: int = 0) -> datetime:
    return datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)


async def register_teacher(async_client):
    email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Secret123!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    profile_resp = await async_client.get("/profiles/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = profile_resp.json()["user_id"]
    onboarding_profile_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=headers,
        json={"display_name": "Teacher", "bio": None},
    )
    assert onboarding_profile_resp.status_code == 200, onboarding_profile_resp.text
    onboarding_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=headers,
    )
    assert onboarding_resp.status_code == 200, onboarding_resp.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )
    await promote_to_teacher(user_id)
    return headers, user_id


async def promote_to_teacher(user_id: str):
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


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.refresh_tokens WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


def _canonical_asset(
    *,
    media_asset_id: str,
    media_type: str = "audio",
    purpose: str = "home_player_audio",
    state: str = "uploaded",
) -> dict:
    return {
        "id": media_asset_id,
        "media_type": media_type,
        "purpose": purpose,
        "state": state,
    }


async def test_home_player_upload_create_uses_media_asset_identity_only(
    async_client,
    monkeypatch,
):
    headers, user_id = await register_teacher(async_client)
    try:
        media_asset_id = str(uuid.uuid4())

        async def fake_get_media_asset(candidate_media_asset_id: str):
            assert candidate_media_asset_id == media_asset_id
            return _canonical_asset(media_asset_id=media_asset_id)

        async def fake_create_upload(*, teacher_id: str, media_asset_id: str, title: str, active: bool):
            return {
                "id": str(uuid.uuid4()),
                "teacher_id": teacher_id,
                "media_asset_id": media_asset_id,
                "title": title,
                "kind": "audio",
                "active": active,
                "created_at": _source_timestamp(minutes_ago=2),
                "updated_at": _source_timestamp(minutes_ago=2),
                "media_state": "uploaded",
            }

        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "get_home_audio_media_asset",
            fake_get_media_asset,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "create_home_player_upload",
            fake_create_upload,
            raising=True,
        )

        create_resp = await async_client.post(
            "/studio/home-player/uploads",
            headers=headers,
            json={
                "title": "Demo audio",
                "active": True,
                "media_asset_id": media_asset_id,
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        created = create_resp.json()
        assert created["teacher_id"] == user_id
        assert created["media_asset_id"] == media_asset_id
        assert created["title"] == "Demo audio"
        assert created["kind"] == "audio"
        assert created["active"] is True
        assert created["media_state"] == "uploaded"
        for removed_field in (
            "media_id",
            "owner_id",
            "storage_bucket",
            "storage_path",
            "content_type",
            "byte_size",
            "original_name",
            "original_content_type",
            "original_filename",
            "original_size_bytes",
            "signed_url",
            "download_url",
            "upload_url",
        ):
            assert removed_field not in created
    finally:
        await cleanup_user(user_id)


async def test_home_player_upload_update_and_delete_use_canonical_source_rows(
    async_client,
    monkeypatch,
):
    headers, user_id = await register_teacher(async_client)
    try:
        media_asset_id = str(uuid.uuid4())
        upload_id = str(uuid.uuid4())
        stored = {
            "id": upload_id,
            "teacher_id": user_id,
            "media_asset_id": media_asset_id,
            "title": "Original title",
            "kind": "audio",
            "active": True,
            "created_at": _source_timestamp(minutes_ago=3),
            "updated_at": _source_timestamp(minutes_ago=3),
            "media_state": "uploaded",
        }
        lifecycle_requests: list[dict[str, object]] = []

        async def fake_get_media_asset(candidate_media_asset_id: str):
            assert candidate_media_asset_id == media_asset_id
            return _canonical_asset(media_asset_id=media_asset_id)

        async def fake_create_upload(*, teacher_id: str, media_asset_id: str, title: str, active: bool):
            stored.update(
                {
                    "teacher_id": teacher_id,
                    "media_asset_id": media_asset_id,
                    "title": title,
                    "active": active,
                }
            )
            return dict(stored)

        async def fake_update_upload(*, upload_id: str, teacher_id: str, fields: dict):
            if upload_id != stored["id"] or teacher_id != stored["teacher_id"]:
                return None
            stored.update(fields)
            stored["updated_at"] = _source_timestamp()
            return dict(stored)

        async def fake_delete_upload(*, upload_id: str, teacher_id: str):
            if upload_id != stored["id"] or teacher_id != stored["teacher_id"]:
                return None
            return dict(stored)

        async def fake_lifecycle_request(**kwargs):
            lifecycle_requests.append(dict(kwargs))
            return len(list(kwargs["media_asset_ids"]))

        async def fail_cleanup_media_asset_and_objects(*args, **kwargs):
            raise AssertionError("request path must not delete media_assets")

        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "get_home_audio_media_asset",
            fake_get_media_asset,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "create_home_player_upload",
            fake_create_upload,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "update_home_player_upload",
            fake_update_upload,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "delete_home_player_upload",
            fake_delete_upload,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.media_cleanup,
            "delete_media_asset_and_objects",
            fail_cleanup_media_asset_and_objects,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.media_cleanup,
            "request_lifecycle_evaluation",
            fake_lifecycle_request,
            raising=True,
        )

        create_resp = await async_client.post(
            "/studio/home-player/uploads",
            headers=headers,
            json={
                "title": "Original title",
                "active": True,
                "media_asset_id": media_asset_id,
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        assert str(create_resp.json()["id"]) == upload_id

        patch_resp = await async_client.patch(
            f"/studio/home-player/uploads/{upload_id}",
            headers=headers,
            json={"title": "Updated title", "active": False},
        )
        assert patch_resp.status_code == 200, patch_resp.text
        updated = patch_resp.json()
        assert updated["id"] == upload_id
        assert updated["title"] == "Updated title"
        assert updated["active"] is False
        assert updated["media_asset_id"] == media_asset_id

        delete_resp = await async_client.delete(
            f"/studio/home-player/uploads/{upload_id}",
            headers=headers,
        )
        assert delete_resp.status_code == 204, delete_resp.text
        assert lifecycle_requests == [
            {
                "media_asset_ids": [media_asset_id],
                "trigger_source": "home_player_upload_delete",
                "subject_type": "home_player_upload",
                "subject_id": upload_id,
            }
        ]

        async def missing_upload(*, upload_id: str, teacher_id: str, fields: dict):
            return None

        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "update_home_player_upload",
            missing_upload,
            raising=True,
        )
        missing_resp = await async_client.patch(
            f"/studio/home-player/uploads/{upload_id}",
            headers=headers,
            json={"active": True},
        )
        assert missing_resp.status_code == 404, missing_resp.text
    finally:
        await cleanup_user(user_id)


async def test_home_player_upload_rejects_non_home_audio_assets(
    async_client,
    monkeypatch,
):
    headers, user_id = await register_teacher(async_client)
    try:
        wrong_purpose_asset_id = str(uuid.uuid4())
        wrong_type_asset_id = str(uuid.uuid4())

        async def fake_get_media_asset(candidate_media_asset_id: str):
            if candidate_media_asset_id == wrong_purpose_asset_id:
                return _canonical_asset(
                    media_asset_id=wrong_purpose_asset_id,
                    purpose="lesson_audio",
                )
            if candidate_media_asset_id == wrong_type_asset_id:
                return _canonical_asset(
                    media_asset_id=wrong_type_asset_id,
                    media_type="video",
                )
            raise AssertionError(candidate_media_asset_id)

        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "get_home_audio_media_asset",
            fake_get_media_asset,
            raising=True,
        )

        purpose_resp = await async_client.post(
            "/studio/home-player/uploads",
            headers=headers,
            json={
                "title": "Wrong purpose",
                "active": True,
                "media_asset_id": wrong_purpose_asset_id,
            },
        )
        assert purpose_resp.status_code == 422, purpose_resp.text
        assert purpose_resp.json()["detail"] == "Invalid media purpose"

        type_resp = await async_client.post(
            "/studio/home-player/uploads",
            headers=headers,
            json={
                "title": "Wrong type",
                "active": True,
                "media_asset_id": wrong_type_asset_id,
            },
        )
        assert type_resp.status_code == 422, type_resp.text
        assert type_resp.json()["detail"] == "Invalid media type"
    finally:
        await cleanup_user(user_id)


async def test_home_player_upload_create_rejects_non_baseline_request_fields(
    async_client,
    monkeypatch,
):
    headers, user_id = await register_teacher(async_client)
    try:
        media_asset_id = str(uuid.uuid4())

        async def fail_get_media_asset(candidate_media_asset_id: str):
            raise AssertionError(candidate_media_asset_id)

        monkeypatch.setattr(
            studio_routes.home_audio_sources_repo,
            "get_home_audio_media_asset",
            fail_get_media_asset,
            raising=True,
        )

        response = await async_client.post(
            "/studio/home-player/uploads",
            headers=headers,
            json={
                "title": "Demo audio",
                "active": True,
                "media_asset_id": media_asset_id,
                "media_id": str(uuid.uuid4()),
                "kind": "audio",
                "original_filename": "demo.wav",
            },
        )

        assert response.status_code == 422, response.text
    finally:
        await cleanup_user(user_id)
