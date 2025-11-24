import hashlib
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from .. import models, repositories, schemas
from ..auth import CurrentUser
from ..config import settings

router = APIRouter(prefix="/profiles", tags=["profiles"])

_AVATAR_ALLOWED_PREFIXES = ("image/",)
_AVATAR_MAX_BYTES = 5 * 1024 * 1024
_AVATAR_BUCKET = "profile-avatars"
_AVATAR_ROOT = Path("avatars")


@router.get("/me", response_model=schemas.Profile)
async def get_me(current: CurrentUser):
    profile = await repositories.get_profile(current["id"])
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Profile missing"
        )
    return schemas.Profile(**profile)


@router.patch("/me", response_model=schemas.Profile)
async def update_me(payload: schemas.ProfileUpdate, current: CurrentUser):
    updated = await repositories.update_profile(
        current["id"],
        display_name=payload.display_name,
        bio=payload.bio,
        photo_url=payload.photo_url,
    )
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Profile missing"
        )
    return schemas.Profile(**updated)


@router.post("/me/avatar", response_model=schemas.Profile)
async def upload_avatar(current: CurrentUser, file: UploadFile = File(...)):
    profile = await repositories.get_profile(current["id"])
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Profile missing"
        )

    content_type = (file.content_type or "").lower()
    if not any(content_type.startswith(prefix) for prefix in _AVATAR_ALLOWED_PREFIXES):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )

    blob = await file.read()
    if not blob:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="File payload is empty"
        )
    if len(blob) > _AVATAR_MAX_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large",
        )

    avatar_dir = Path(settings.media_root) / _AVATAR_ROOT / str(profile["user_id"])
    avatar_dir.mkdir(parents=True, exist_ok=True)
    safe_name = f"{uuid4().hex}_{file.filename or 'avatar'}"
    relative_path = str(_AVATAR_ROOT / str(profile["user_id"]) / safe_name)
    dest_path = avatar_dir / safe_name
    dest_path.write_bytes(blob)

    checksum = hashlib.sha256(blob).hexdigest()
    media_object = await models.create_media_object(
        owner_id=profile["user_id"],
        storage_path=relative_path,
        storage_bucket=_AVATAR_BUCKET,
        content_type=content_type,
        byte_size=len(blob),
        checksum=checksum,
        original_name=file.filename,
    )
    if not media_object or not media_object.get("id"):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to persist avatar",
        )

    media_id = media_object["id"]
    photo_url = f"/profiles/avatar/{media_id}"
    updated = await repositories.update_profile(
        profile["user_id"],
        photo_url=photo_url,
        avatar_media_id=media_id,
    )
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update profile",
        )

    previous_media_id = profile.get("avatar_media_id")
    if previous_media_id and previous_media_id != media_id:
        previous_media = await models.get_media_object(previous_media_id)
        if previous_media:
            previous_path = previous_media.get("storage_path")
            bucket = previous_media.get("storage_bucket")
            if previous_path:
                candidates = []
                if bucket:
                    candidates.append(
                        Path(settings.media_root) / bucket / previous_path
                    )
                candidates.append(Path(settings.media_root) / previous_path)
                for candidate in candidates:
                    if candidate.exists() and candidate != dest_path:
                        candidate.unlink()
        await models.cleanup_media_object(previous_media_id)

    return schemas.Profile(**updated)


@router.get("/avatar/{media_id}")
async def avatar_file(media_id: str):
    media = await models.get_media_object(media_id)
    if not media:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Avatar not found"
        )

    storage_path = media.get("storage_path")
    if not storage_path:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Avatar not found"
        )

    base_dir = Path(settings.media_root)
    candidates = []
    bucket = media.get("storage_bucket")
    if bucket:
        candidates.append(base_dir / bucket / storage_path)
    candidates.append(base_dir / storage_path)

    for path in candidates:
        if path.exists():
            return FileResponse(
                path, media_type=media.get("content_type") or "image/jpeg"
            )

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND, detail="Avatar file missing"
    )


@router.get("/{user_id}/certificates")
async def certificates(user_id: str, current: CurrentUser, verified_only: bool = False):
    viewer_id = str(current["id"])
    if user_id != viewer_id and not bool(current.get("is_admin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed to access certificates",
        )
    rows = await models.certificates_of(user_id, verified_only)
    return {"items": rows}
