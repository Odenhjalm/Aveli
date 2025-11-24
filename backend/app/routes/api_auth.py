import hashlib
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, HTTPException, Request, UploadFile, status
from fastapi.responses import FileResponse
from jose import JWTError

from .. import models, repositories, schemas
from ..auth import (
    CurrentUser,
    create_access_token,
    create_refresh_token,
    decode_jwt,
    hash_password,
    hash_refresh_token,
    is_token_expired,
    verify_password,
)
from ..config import settings

router = APIRouter(prefix="/auth", tags=["auth"])

_AVATAR_ALLOWED_PREFIXES = ("image/",)
_AVATAR_MAX_BYTES = 5 * 1024 * 1024
_AVATAR_BUCKET = "profile-avatars"
_AVATAR_ROOT = Path("avatars")


async def _client_ip(request: Request) -> str | None:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client:
        return request.client.host
    return None


async def _claims_for_user(user_id: str, profile: dict | None = None) -> dict:
    profile = profile or await repositories.get_profile(user_id) or {}
    is_admin = bool(profile.get("is_admin"))
    role = profile.get("role_v2", "user") or "user"
    is_teacher = await models.is_teacher_user(user_id)
    return {
        "role": role,
        "is_admin": is_admin,
        "is_teacher": bool(is_teacher),
    }


@router.post(
    "/register", response_model=schemas.Token, status_code=status.HTTP_201_CREATED
)
async def register(payload: schemas.AuthRegisterRequest, request: Request):
    existing = await repositories.get_user_by_email(payload.email)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Email already registered"
        )

    hashed = hash_password(payload.password)
    try:
        result = await repositories.create_user(
            email=payload.email,
            hashed_password=hashed,
            display_name=payload.display_name,
        )
    except repositories.UniqueViolationError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Email already registered"
        ) from exc

    user = result["user"]
    profile = result["profile"] or {}
    user_id = str(user["id"])
    claims = await _claims_for_user(user_id, profile)
    access_token = create_access_token(user_id, claims=claims)
    refresh_token, refresh_jti, refresh_exp = create_refresh_token(user_id)
    await repositories.upsert_refresh_token(
        user_id=user_id,
        jti=refresh_jti,
        token_hash=hash_refresh_token(refresh_token),
        expires_at=refresh_exp,
    )

    await repositories.insert_auth_event(
        user_id=user_id,
        email=payload.email,
        event="register_success",
        ip_address=await _client_ip(request),
        user_agent=request.headers.get("user-agent"),
        metadata={"refresh_jti": refresh_jti},
    )
    return schemas.Token(access_token=access_token, refresh_token=refresh_token)


@router.post("/login", response_model=schemas.Token)
async def login(payload: schemas.AuthLoginRequest, request: Request):
    user = await repositories.get_user_by_email(payload.email)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials"
        )

    hashed = user.get("encrypted_password")
    if not hashed or not verify_password(payload.password, hashed):
        await repositories.insert_auth_event(
            user_id=str(user["id"]),
            email=payload.email,
            event="login_invalid_password",
            ip_address=await _client_ip(request),
            user_agent=request.headers.get("user-agent"),
            metadata=None,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials"
        )

    profile = await repositories.get_profile(user["id"]) or {}
    user_id = str(user["id"])
    claims = await _claims_for_user(user_id, profile)
    user_id = str(user["id"])
    access_token = create_access_token(user_id, claims=claims)
    refresh_token, refresh_jti, refresh_exp = create_refresh_token(user_id)
    await repositories.upsert_refresh_token(
        user_id=user_id,
        jti=refresh_jti,
        token_hash=hash_refresh_token(refresh_token),
        expires_at=refresh_exp,
    )

    await repositories.insert_auth_event(
        user_id=user_id,
        email=payload.email,
        event="login_success",
        ip_address=await _client_ip(request),
        user_agent=request.headers.get("user-agent"),
        metadata={"refresh_jti": refresh_jti},
    )
    return schemas.Token(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh", response_model=schemas.Token)
async def refresh(payload: schemas.TokenRefreshRequest, request: Request):
    try:
        decoded = decode_jwt(payload.refresh_token)
        if is_token_expired(decoded):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired"
            )
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token"
        ) from exc

    if decoded.get("token_type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid token type"
        )

    jti = decoded.get("jti")
    sub = decoded.get("sub")
    if not jti or not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token"
        )

    stored = await repositories.get_refresh_token(jti)
    if not stored:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token revoked"
        )

    if stored.get("revoked_at") or stored.get("rotated_at"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token rotated"
        )

    expires_at = stored.get("expires_at")
    if isinstance(expires_at, datetime) and expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at and expires_at < datetime.now(timezone.utc):
        await repositories.revoke_refresh_token(jti)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired"
        )

    if stored.get("token_hash") != hash_refresh_token(payload.refresh_token):
        await repositories.revoke_refresh_token(jti)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token mismatch"
        )

    await repositories.touch_refresh_token_as_rotated(jti)

    profile = await repositories.get_profile(sub) or {}
    claims = await _claims_for_user(sub, profile)
    access_token = create_access_token(sub, claims=claims)
    new_refresh_token, new_jti, new_exp = create_refresh_token(sub)
    await repositories.upsert_refresh_token(
        user_id=sub,
        jti=new_jti,
        token_hash=hash_refresh_token(new_refresh_token),
        expires_at=new_exp,
    )

    await repositories.insert_auth_event(
        user_id=sub,
        email=None,
        event="refresh_success",
        ip_address=await _client_ip(request),
        user_agent=request.headers.get("user-agent"),
        metadata={"refresh_jti": new_jti, "rotated_from": jti},
    )
    return schemas.Token(access_token=access_token, refresh_token=new_refresh_token)


@router.get("/me", response_model=schemas.Profile)
async def me(current: CurrentUser):
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
    photo_url = f"/auth/avatar/{media_id}"
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
async def get_avatar(media_id: str):
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

    candidates = []
    bucket = media.get("storage_bucket")
    base = Path(settings.media_root)
    if bucket:
        candidates.append(base / bucket / storage_path)
    candidates.append(base / storage_path)

    for candidate in candidates:
        if candidate.exists():
            return FileResponse(
                candidate, media_type=media.get("content_type") or "image/jpeg"
            )

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND, detail="Avatar file missing"
    )
