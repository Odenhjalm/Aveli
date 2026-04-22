from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app import schemas
from app.main import app
from app.routes import profile_avatar, profiles, studio
from app.utils import profile_media as profile_media_utils


pytestmark = pytest.mark.anyio("asyncio")


def _uuid() -> str:
    return str(uuid4())


def _profile_payload(user_id: str, *, avatar_media_id: str | None = None) -> dict:
    return {
        "user_id": user_id,
        "email": "avatar@example.com",
        "display_name": "Avatar User",
        "bio": None,
        "avatar_media_id": avatar_media_id,
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
    }


def _profile_media_asset(
    *,
    user_id: str,
    media_asset_id: str,
    purpose: str = "profile_media",
    media_type: str = "image",
    state: str = "ready",
    object_user_id: str | None = None,
) -> dict:
    scoped_user_id = object_user_id or user_id
    return {
        "id": media_asset_id,
        "purpose": purpose,
        "media_type": media_type,
        "state": state,
        "owner_user_id": scoped_user_id,
        "original_object_path": (
            f"media/source/profile-avatar/{scoped_user_id}/avatar.png"
        ),
    }


def _route_inventory() -> set[tuple[str, str]]:
    return {
        (route.path, method)
        for route in app.routes
        for method in getattr(route, "methods", set())
        if method not in {"HEAD", "OPTIONS"}
    }


async def test_profile_avatar_routes_are_mounted() -> None:
    inventory = _route_inventory()

    assert ("/api/media/profile-avatar/init", "POST") in inventory
    assert ("/api/profile/avatar/attach", "POST") in inventory
    assert ("/api/media-assets/{media_asset_id}/upload-bytes", "PUT") in inventory
    assert (
        "/api/media-assets/{media_asset_id}/upload-completion",
        "POST",
    ) in inventory


async def test_profile_avatar_init_creates_profile_media_asset(monkeypatch) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()
    created: dict[str, object] = {}

    async def fake_create_media_asset(**kwargs):
        created.update(kwargs)
        return {"id": media_asset_id, "state": "pending_upload"}

    monkeypatch.setattr(
        profile_avatar.media_assets_repo,
        "create_media_asset",
        fake_create_media_asset,
    )

    response = await profile_avatar.canonical_issue_profile_avatar_init(
        schemas.CanonicalProfileAvatarInitRequest(
            filename="avatar.png",
            mime_type="image/png",
            size_bytes=1024,
        ),
        current={"id": user_id},
    )

    assert response.media_asset_id == UUID(media_asset_id)
    assert response.asset_state == "pending_upload"
    assert response.upload_session_id == UUID(media_asset_id)
    assert (
        response.upload_endpoint == f"/api/media-assets/{media_asset_id}/upload-bytes"
    )
    assert created["media_type"] == "image"
    assert created["purpose"] == "profile_media"
    assert created["state"] == "pending_upload"
    assert created["original_filename"] == "avatar.png"
    assert created["owner_user_id"] == user_id
    assert str(created["original_object_path"]).startswith(
        f"media/source/profile-avatar/{user_id}/"
    )
    assert "storage" not in response.model_dump()


async def test_existing_upload_authorization_admits_scoped_profile_media(
    monkeypatch,
) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()
    asset = _profile_media_asset(
        user_id=user_id,
        media_asset_id=media_asset_id,
        state="pending_upload",
    )
    asset["original_object_path"] = "invalid/profile/path.png"

    async def fake_lesson_authorization(**kwargs):
        raise HTTPException(status_code=422, detail="not lesson media")

    async def fake_get_media_asset(candidate_media_asset_id: str):
        assert candidate_media_asset_id == media_asset_id
        return asset

    monkeypatch.setattr(
        studio,
        "_authorize_canonical_lesson_media_asset",
        fake_lesson_authorization,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
    )

    authorized = await studio._authorize_canonical_media_upload_asset(
        media_asset_id=media_asset_id,
        current={"id": user_id},
    )

    assert authorized == asset
    assert (
        studio._canonical_upload_storage_bucket(authorized)
        == studio.settings.media_profile_bucket
    )


async def test_existing_upload_authorization_admits_legacy_profile_media_scope_fallback(
    monkeypatch,
) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()
    asset = _profile_media_asset(
        user_id=user_id,
        media_asset_id=media_asset_id,
        state="pending_upload",
    )
    asset.pop("owner_user_id", None)

    async def fake_lesson_authorization(**kwargs):
        raise HTTPException(status_code=422, detail="not lesson media")

    async def fake_get_media_asset(candidate_media_asset_id: str):
        assert candidate_media_asset_id == media_asset_id
        return asset

    monkeypatch.setattr(
        studio,
        "_authorize_canonical_lesson_media_asset",
        fake_lesson_authorization,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
    )

    authorized = await studio._authorize_canonical_media_upload_asset(
        media_asset_id=media_asset_id,
        current={"id": user_id},
    )

    assert authorized == asset


async def test_profile_avatar_upload_completion_uses_canonical_uploaded_transition(
    monkeypatch,
) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()
    calls: dict[str, object] = {}

    async def fake_authorize_media_asset(**kwargs):
        return _profile_media_asset(
            user_id=user_id,
            media_asset_id=media_asset_id,
            state="pending_upload",
        )

    async def fake_assert_storage_write(media_asset):
        calls["storage_checked"] = media_asset["id"]

    async def fake_mark_media_asset_uploaded(*, media_id: str):
        calls["uploaded_media_id"] = media_id
        return {"id": media_id, "state": "uploaded"}

    async def fail_lesson_mark_uploaded(*, media_id: str):
        raise AssertionError("profile_media must not use lesson upload transition")

    monkeypatch.setattr(
        studio,
        "_authorize_canonical_media_upload_asset",
        fake_authorize_media_asset,
    )
    monkeypatch.setattr(
        studio,
        "_assert_canonical_media_storage_write",
        fake_assert_storage_write,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "mark_media_asset_uploaded",
        fake_mark_media_asset_uploaded,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "mark_lesson_media_pipeline_asset_uploaded",
        fail_lesson_mark_uploaded,
    )

    response = await studio.canonical_complete_lesson_media_upload(
        media_asset_id=UUID(media_asset_id),
        payload=schemas.CanonicalMediaAssetUploadCompletionRequest(),
        current={"id": user_id},
    )

    assert response.asset_state == "uploaded"
    assert calls == {
        "storage_checked": media_asset_id,
        "uploaded_media_id": media_asset_id,
    }


@pytest.mark.parametrize(
    ("overrides", "expected_status"),
    [
        ({"purpose": "lesson_media"}, 422),
        ({"media_type": "audio"}, 422),
        ({"state": "uploaded"}, 409),
        ({"object_user_id": "foreign-user"}, 403),
    ],
)
async def test_profile_avatar_attach_rejects_invalid_assets(
    monkeypatch,
    overrides,
    expected_status,
) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()

    async def fake_get_media_asset(candidate_media_asset_id: str):
        assert candidate_media_asset_id == media_asset_id
        return _profile_media_asset(
            user_id=user_id,
            media_asset_id=media_asset_id,
            **overrides,
        )

    monkeypatch.setattr(
        profile_avatar.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
    )

    with pytest.raises(HTTPException) as exc_info:
        await profile_avatar._require_ready_profile_avatar_asset(
            media_asset_id=media_asset_id,
            user_id=user_id,
        )

    assert exc_info.value.status_code == expected_status


async def test_profile_avatar_attach_binds_placement_and_projection(
    monkeypatch,
) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()
    calls: dict[str, object] = {}

    async def fake_get_media_asset(candidate_media_asset_id: str):
        return _profile_media_asset(
            user_id=user_id,
            media_asset_id=candidate_media_asset_id,
        )

    async def fake_ensure_teacher_profile_media_placement(**kwargs):
        calls["placement"] = kwargs
        return {
            "id": _uuid(),
            "subject_user_id": kwargs["teacher_id"],
            "media_asset_id": kwargs["media_asset_id"],
            "visibility": kwargs["visibility"],
        }

    async def fake_update_avatar_media_projection(user_id_arg, *, avatar_media_id):
        calls["projection"] = {
            "user_id": user_id_arg,
            "avatar_media_id": avatar_media_id,
        }
        return _profile_payload(user_id_arg, avatar_media_id=avatar_media_id)

    async def fake_profile_projection_with_avatar(profile):
        payload = dict(profile)
        payload["photo_url"] = "https://cdn.example/avatar.jpg"
        return payload

    monkeypatch.setattr(
        profile_avatar.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
    )
    monkeypatch.setattr(
        profile_avatar.profile_media_repo,
        "ensure_teacher_profile_media_placement",
        fake_ensure_teacher_profile_media_placement,
    )
    monkeypatch.setattr(
        profile_avatar.profiles_repo,
        "update_avatar_media_projection",
        fake_update_avatar_media_projection,
    )
    monkeypatch.setattr(
        profile_avatar,
        "profile_projection_with_avatar",
        fake_profile_projection_with_avatar,
    )

    response = await profile_avatar.canonical_attach_profile_avatar(
        schemas.CanonicalProfileAvatarAttachRequest(
            media_asset_id=UUID(media_asset_id),
        ),
        current={"id": user_id},
    )

    assert response.avatar_media_id == UUID(media_asset_id)
    assert response.photo_url == "https://cdn.example/avatar.jpg"
    assert calls["placement"] == {
        "teacher_id": user_id,
        "media_asset_id": media_asset_id,
        "visibility": "published",
    }
    assert calls["projection"] == {
        "user_id": user_id,
        "avatar_media_id": media_asset_id,
    }


async def test_profiles_me_uses_avatar_read_composition(monkeypatch) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()
    calls: dict[str, object] = {}

    async def fake_get_profile(user_id_arg):
        calls["get_profile"] = user_id_arg
        return _profile_payload(user_id_arg, avatar_media_id=media_asset_id)

    async def fake_profile_projection_with_avatar(profile):
        calls["projection_profile"] = profile
        payload = dict(profile)
        payload["photo_url"] = "https://cdn.example/avatar.jpg"
        return payload

    monkeypatch.setattr(profiles.models, "get_profile", fake_get_profile)
    monkeypatch.setattr(
        profiles,
        "profile_projection_with_avatar",
        fake_profile_projection_with_avatar,
    )

    response = await profiles.get_me(current_user={"id": user_id})

    assert response.avatar_media_id == UUID(media_asset_id)
    assert response.photo_url == "https://cdn.example/avatar.jpg"
    assert calls["get_profile"] == user_id


async def test_profiles_me_returns_canonical_jpg_avatar(monkeypatch) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()
    expected_media_asset_id = media_asset_id

    async def fake_get_profile(user_id_arg):
        return _profile_payload(user_id_arg, avatar_media_id=media_asset_id)

    async def fake_runtime_row(media_asset_id: str):
        assert media_asset_id == expected_media_asset_id
        return {
            "media_type": "image",
            "purpose": "profile_media",
            "playback_object_path": "profiles/avatar.jpg",
            "playback_format": "jpg",
            "state": "ready",
        }

    monkeypatch.setattr(profiles.models, "get_profile", fake_get_profile)
    monkeypatch.setattr(
        profile_media_utils.runtime_media_repo,
        "get_profile_runtime_media",
        fake_runtime_row,
    )
    monkeypatch.setattr(
        profile_media_utils.storage_service,
        "get_storage_service",
        lambda bucket: SimpleNamespace(
            public_url=lambda path: f"https://cdn.example/{bucket}/{path}"
        ),
    )

    response = await profiles.get_me(current_user={"id": user_id})

    assert response.avatar_media_id == UUID(media_asset_id)
    assert response.photo_url.endswith("/profiles/avatar.jpg")
    dumped = response.model_dump(mode="json")
    assert "storage_path" not in dumped
    assert "storage_bucket" not in dumped
    assert "original_object_path" not in dumped
    assert "playback_object_path" not in dumped


@pytest.mark.parametrize(
    ("runtime_row", "public_url"),
    [
        (
            {
                "media_type": "image",
                "purpose": "profile_media",
                "playback_object_path": "profiles/avatar.jpeg",
                "playback_format": "jpeg",
                "state": "ready",
            },
            "https://cdn.example/profiles/avatar.jpeg",
        ),
        (
            {
                "media_type": "image",
                "purpose": "profile_media",
                "playback_object_path": "profiles/avatar.png",
                "playback_format": "png",
                "state": "ready",
            },
            "https://cdn.example/profiles/avatar.png",
        ),
        (
            {
                "media_type": "image",
                "purpose": "profile_media",
                "playback_object_path": "profiles/avatar.jpg",
                "playback_format": "jpg",
                "state": "uploaded",
            },
            "https://cdn.example/profiles/avatar.jpg",
        ),
        (
            {
                "media_type": "image",
                "purpose": "profile_media",
                "playback_object_path": "",
                "playback_format": "jpg",
                "state": "ready",
            },
            "https://cdn.example/profiles/avatar.jpg",
        ),
        (
            {
                "media_type": "image",
                "purpose": "profile_media",
                "playback_object_path": "profiles/avatar.jpg",
                "playback_format": "jpg",
                "state": "ready",
            },
            "   ",
        ),
    ],
)
async def test_profiles_me_filters_noncanonical_avatar_media(
    monkeypatch,
    runtime_row: dict[str, str],
    public_url: str,
) -> None:
    user_id = _uuid()
    media_asset_id = _uuid()
    expected_media_asset_id = media_asset_id

    async def fake_get_profile(user_id_arg):
        return _profile_payload(user_id_arg, avatar_media_id=media_asset_id)

    async def fake_runtime_row(media_asset_id: str):
        assert media_asset_id == expected_media_asset_id
        return dict(runtime_row)

    monkeypatch.setattr(profiles.models, "get_profile", fake_get_profile)
    monkeypatch.setattr(
        profile_media_utils.runtime_media_repo,
        "get_profile_runtime_media",
        fake_runtime_row,
    )
    monkeypatch.setattr(
        profile_media_utils.storage_service,
        "get_storage_service",
        lambda bucket: SimpleNamespace(public_url=lambda path: public_url),
    )

    response = await profiles.get_me(current_user={"id": user_id})

    assert response.avatar_media_id == UUID(media_asset_id)
    assert response.photo_url is None


def test_onboarding_and_profile_patch_still_forbid_avatar_fields() -> None:
    with pytest.raises(ValidationError):
        schemas.OnboardingCreateProfileRequest(
            display_name="Avatar User",
            avatar_media_id=_uuid(),
        )
    with pytest.raises(ValidationError):
        schemas.ProfileUpdate(avatar_media_id=_uuid())
    with pytest.raises(ValidationError):
        schemas.ProfileUpdate(photo_url="https://example.invalid/avatar.jpg")
