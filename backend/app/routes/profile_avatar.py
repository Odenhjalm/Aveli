from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, status

from .. import schemas
from ..auth import CurrentUser
from ..config import settings
from ..repositories import media_assets as media_assets_repo
from ..repositories import profiles as profiles_repo
from ..repositories import teacher_profile_media as profile_media_repo
from ..utils import media_paths
from ..utils.profile_media import profile_projection_with_avatar


router = APIRouter(prefix="/api", tags=["media"])

_AVATAR_MIME_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
_UPLOAD_SESSION_EXPIRES_SECONDS = 2 * 60 * 60


def _canonical_upload_endpoint(media_asset_id: str) -> str:
    return f"/api/media-assets/{media_asset_id}/upload-bytes"


def _require_avatar_mime_type(value: str) -> str:
    exact = str(value or "").strip().lower()
    if exact not in _AVATAR_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Endast JPEG-, PNG- eller WebP-bilder stöds.",
        )
    return exact


def _avatar_ingest_format(*, filename: str, mime_type: str) -> str:
    suffix = Path(filename).suffix.lower().lstrip(".")
    if mime_type == "image/jpeg":
        return "jpeg"
    if mime_type == "image/png":
        return "png"
    if mime_type == "image/webp":
        return "webp"
    return suffix or "image"


def _avatar_asset_id(value: UUID) -> str:
    return str(value).strip()


async def _require_ready_profile_avatar_asset(
    *,
    media_asset_id: str,
    user_id: str,
) -> dict:
    media_asset = await media_assets_repo.get_media_asset(media_asset_id)
    if not media_asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mediafilen hittades inte.",
        )

    if str(media_asset.get("purpose") or "").strip().lower() != "profile_media":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Mediafilen har fel användningsområde.",
        )
    if str(media_asset.get("media_type") or "").strip().lower() != "image":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Mediafilen måste vara en bild.",
        )
    if not profile_media_repo.profile_media_asset_belongs_to_subject(
        asset=media_asset,
        subject_user_id=user_id,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Du saknar åtkomst till mediafilen.",
        )
    if str(media_asset.get("state") or "").strip().lower() != "ready":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Mediafilen är inte klar.",
        )
    return media_asset


@router.post(
    "/media/profile-avatar/init",
    response_model=schemas.CanonicalProfileAvatarInitResponse,
)
async def canonical_issue_profile_avatar_init(
    payload: schemas.CanonicalProfileAvatarInitRequest,
    current: CurrentUser,
):
    if payload.size_bytes > max(1, int(settings.media_upload_max_image_bytes)):
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Filen är för stor.",
        )

    exact_mime_type = _require_avatar_mime_type(payload.mime_type)
    ingest_format = _avatar_ingest_format(
        filename=payload.filename,
        mime_type=exact_mime_type,
    )
    object_path = media_paths.build_profile_avatar_source_object_path(
        str(current["id"]),
        payload.filename,
    )
    try:
        object_path = media_paths.validate_new_upload_object_path(object_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ogiltig uppladdningssökväg.",
        ) from exc

    media_asset = await media_assets_repo.create_media_asset(
        media_asset_id=str(uuid4()),
        media_type="image",
        purpose="profile_media",
        original_object_path=object_path,
        ingest_format=ingest_format,
        state="pending_upload",
    )
    media_asset_id = UUID(str(media_asset["id"]))
    expires_at = datetime.now(timezone.utc) + timedelta(
        seconds=_UPLOAD_SESSION_EXPIRES_SECONDS
    )
    return schemas.CanonicalProfileAvatarInitResponse(
        media_asset_id=media_asset_id,
        asset_state="pending_upload",
        upload_session_id=media_asset_id,
        upload_endpoint=_canonical_upload_endpoint(str(media_asset_id)),
        expires_at=expires_at,
    )


@router.post(
    "/profile/avatar/attach",
    response_model=schemas.Profile,
)
async def canonical_attach_profile_avatar(
    payload: schemas.CanonicalProfileAvatarAttachRequest,
    current: CurrentUser,
):
    user_id = str(current["id"])
    media_asset_id = _avatar_asset_id(payload.media_asset_id)
    await _require_ready_profile_avatar_asset(
        media_asset_id=media_asset_id,
        user_id=user_id,
    )

    placement = await profile_media_repo.ensure_teacher_profile_media_placement(
        teacher_id=user_id,
        media_asset_id=media_asset_id,
        visibility="published",
    )
    if not placement:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Profilbilden kunde inte kopplas.",
        )

    profile = await profiles_repo.update_avatar_media_projection(
        user_id,
        avatar_media_id=media_asset_id,
    )
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="profile_not_found",
        )
    profile = await profile_projection_with_avatar(profile)
    return schemas.Profile(**profile)
