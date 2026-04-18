from uuid import uuid4

import pytest
from pydantic import ValidationError

from app import schemas
from app.repositories import teacher_profile_media as profile_media_repo


def _uuid() -> str:
    return str(uuid4())


def _profile_media_asset(
    *,
    teacher_id: str,
    media_asset_id: str | None = None,
    purpose: str = "profile_media",
    media_type: str = "image",
    state: str = "uploaded",
    original_object_path: str | None = None,
    owner_id: str | None = None,
) -> dict[str, str | None]:
    return {
        "id": media_asset_id or _uuid(),
        "purpose": purpose,
        "media_type": media_type,
        "state": state,
        "original_object_path": original_object_path
        or f"media/source/profile-avatar/{teacher_id}/avatar.png",
        "owner_id": owner_id,
    }


def test_profile_media_create_requires_explicit_visibility() -> None:
    with pytest.raises(ValidationError):
        schemas.TeacherProfileMediaCreate(media_asset_id=_uuid())


def test_profile_media_create_accepts_canonical_asset_identity() -> None:
    payload = schemas.TeacherProfileMediaCreate(
        media_asset_id=_uuid(),
        visibility=schemas.ProfileMediaVisibility.published,
    )

    assert payload.media_asset_id is not None
    assert payload.visibility == schemas.ProfileMediaVisibility.published


def test_profile_media_create_rejects_legacy_fields() -> None:
    with pytest.raises(
        ValidationError,
    ):
        schemas.TeacherProfileMediaCreate(
            media_asset_id=_uuid(),
            visibility=schemas.ProfileMediaVisibility.draft,
            lesson_media_id=_uuid(),
        )


def test_profile_media_item_has_only_canonical_profile_media_fields() -> None:
    item = schemas.TeacherProfileMediaItem(
        id=_uuid(),
        subject_user_id=_uuid(),
        media_asset_id=_uuid(),
        visibility=schemas.ProfileMediaVisibility.published,
        media=None,
    )

    dumped = item.model_dump()

    assert "subject_user_id" in dumped
    assert "media_asset_id" in dumped
    assert "visibility" in dumped
    assert "media" in dumped
    assert "teacher_id" not in dumped
    assert "media_kind" not in dumped
    assert "lesson_media_id" not in dumped
    assert "external_url" not in dumped
    assert "cover_image_url" not in dumped
    assert "is_published" not in dumped
    assert "enabled_for_home_player" not in dumped


def test_profile_media_response_contains_only_items() -> None:
    response = schemas.TeacherProfileMediaListResponse(
        items=[],
    )

    dumped = response.model_dump()

    assert dumped == {"items": []}


@pytest.mark.anyio("asyncio")
async def test_profile_media_validation_accepts_subject_scoped_profile_image(
    monkeypatch,
) -> None:
    teacher_id = _uuid()
    media_asset_id = _uuid()

    async def fake_get_media_asset(candidate_media_asset_id: str):
        assert candidate_media_asset_id == media_asset_id
        return _profile_media_asset(
            teacher_id=teacher_id,
            media_asset_id=media_asset_id,
        )

    monkeypatch.setattr(
        profile_media_repo.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
    )

    asset = await profile_media_repo.validate_profile_media_asset_for_subject(
        teacher_id=teacher_id,
        media_asset_id=media_asset_id,
    )

    assert asset is not None
    assert asset["id"] == media_asset_id


@pytest.mark.anyio("asyncio")
@pytest.mark.parametrize(
    "overrides",
    [
        {"purpose": "lesson_media"},
        {"media_type": "audio"},
        {"state": "pending_upload"},
        {"state": "failed"},
    ],
)
async def test_profile_media_validation_rejects_invalid_asset_contract(
    monkeypatch,
    overrides,
) -> None:
    teacher_id = _uuid()
    media_asset_id = _uuid()

    async def fake_get_media_asset(candidate_media_asset_id: str):
        assert candidate_media_asset_id == media_asset_id
        return _profile_media_asset(
            teacher_id=teacher_id,
            media_asset_id=media_asset_id,
            **overrides,
        )

    monkeypatch.setattr(
        profile_media_repo.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
    )

    asset = await profile_media_repo.validate_profile_media_asset_for_subject(
        teacher_id=teacher_id,
        media_asset_id=media_asset_id,
    )

    assert asset is None


@pytest.mark.anyio("asyncio")
async def test_profile_media_validation_rejects_foreign_profile_image(
    monkeypatch,
) -> None:
    teacher_id = _uuid()
    other_teacher_id = _uuid()
    media_asset_id = _uuid()

    async def fake_get_media_asset(candidate_media_asset_id: str):
        assert candidate_media_asset_id == media_asset_id
        return _profile_media_asset(
            teacher_id=other_teacher_id,
            media_asset_id=media_asset_id,
        )

    monkeypatch.setattr(
        profile_media_repo.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
    )

    asset = await profile_media_repo.validate_profile_media_asset_for_subject(
        teacher_id=teacher_id,
        media_asset_id=media_asset_id,
    )

    assert asset is None


@pytest.mark.anyio("asyncio")
async def test_profile_media_create_fails_closed_when_asset_validation_fails(
    monkeypatch,
) -> None:
    async def fake_validate_profile_media_asset_for_subject(**kwargs):
        return None

    monkeypatch.setattr(
        profile_media_repo,
        "validate_profile_media_asset_for_subject",
        fake_validate_profile_media_asset_for_subject,
    )

    row = await profile_media_repo.create_teacher_profile_media(
        teacher_id=_uuid(),
        media_asset_id=_uuid(),
        visibility="published",
    )

    assert row is None


@pytest.mark.anyio("asyncio")
async def test_profile_media_update_revalidates_existing_asset_before_publish(
    monkeypatch,
) -> None:
    teacher_id = _uuid()
    media_asset_id = _uuid()
    calls: dict[str, str] = {}

    async def fake_get_teacher_profile_media(*, item_id: str, teacher_id: str):
        calls["item_id"] = item_id
        calls["teacher_id"] = teacher_id
        return {
            "id": item_id,
            "subject_user_id": teacher_id,
            "media_asset_id": media_asset_id,
            "visibility": "draft",
        }

    async def fake_validate_profile_media_asset_for_subject(
        *,
        teacher_id: str,
        media_asset_id: str,
    ):
        calls["validated_teacher_id"] = teacher_id
        calls["validated_media_asset_id"] = media_asset_id
        return None

    monkeypatch.setattr(
        profile_media_repo,
        "get_teacher_profile_media",
        fake_get_teacher_profile_media,
    )
    monkeypatch.setattr(
        profile_media_repo,
        "validate_profile_media_asset_for_subject",
        fake_validate_profile_media_asset_for_subject,
    )

    row = await profile_media_repo.update_teacher_profile_media(
        item_id=_uuid(),
        teacher_id=teacher_id,
        fields={"visibility": "published"},
    )

    assert row is None
    assert calls["validated_teacher_id"] == teacher_id
    assert calls["validated_media_asset_id"] == media_asset_id
