import hashlib
import logging
import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

import httpx
from fastapi import APIRouter, BackgroundTasks, File, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse, JSONResponse
from jose import JWTError
from psycopg.rows import dict_row
from pydantic import BaseModel

from .. import models, repositories, schemas
from ..auth import (
    CurrentUser,
    create_access_token,
    create_refresh_token,
    decode_jwt,
    hash_refresh_token,
    is_token_expired,
    verify_password,
)
from ..config import settings
from ..db import pool
from ..services.email_verification import (
    InvalidInviteTokenError,
    InvalidPasswordResetTokenError,
    reset_password_with_token,
    send_invite_email,
    send_password_reset_email,
    send_verification_email,
    validate_invite_token,
)
from ..services.onboarding_state import sync_onboarding_state
from ..utils.membership_status import is_membership_active

router = APIRouter(prefix="/auth", tags=["auth"])

logger = logging.getLogger(__name__)

_AVATAR_ALLOWED_PREFIXES = ("image/",)
_AVATAR_MAX_BYTES = 5 * 1024 * 1024
_AVATAR_BUCKET = "profile-avatars"
_AVATAR_ROOT = Path("avatars")
_RATE_LIMIT_WINDOW_SECONDS = 60 * 60
_PASSWORD_RESET_RATE_LIMIT = 5
_SEND_INVITE_RATE_LIMIT = 10
_password_reset_attempts: defaultdict[str, deque[float]] = defaultdict(deque)
_send_invite_attempts: defaultdict[str, deque[float]] = defaultdict(deque)


class RegisterTokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


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


async def _enqueue_verification_email(email: str) -> None:
    try:
        await send_verification_email(email)
    except Exception:
        logger.exception(
            "Failed to send verification email after signup email=%s",
            email,
        )


def _supabase_admin_base_url() -> str:
    if settings.supabase_url is None:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Registration unavailable",
        )
    return settings.supabase_url.unicode_string().rstrip("/")


def _supabase_admin_headers() -> dict[str, str]:
    service_key = settings.supabase_service_role_key
    if not service_key:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Registration unavailable",
        )
    return {
        "Authorization": f"Bearer {service_key}",
        "apikey": service_key,
        "Content-Type": "application/json",
    }


def _is_duplicate_signup_response(response: httpx.Response) -> bool:
    if response.status_code == status.HTTP_409_CONFLICT:
        return True
    if response.status_code not in {
        status.HTTP_400_BAD_REQUEST,
        status.HTTP_409_CONFLICT,
        status.HTTP_422_UNPROCESSABLE_ENTITY,
    }:
        return False
    body = response.text.lower()
    return any(
        marker in body
        for marker in (
            "already registered",
            "already exists",
            "user already",
            "duplicate",
            "email exists",
        )
    )


async def _create_supabase_auth_user(
    *,
    email: str,
    password: str,
    display_name: str | None,
) -> dict[str, Any]:
    payload = {
        "email": _normalized_email(email),
        "password": password,
        "email_confirm": True,
        "user_metadata": {"display_name": display_name or ""},
    }
    try:
        async with httpx.AsyncClient(
            base_url=_supabase_admin_base_url(),
            headers=_supabase_admin_headers(),
            timeout=20.0,
        ) as client:
            response = await client.post("/auth/v1/admin/users", json=payload)
    except HTTPException:
        logger.exception("Register failed: Supabase admin config missing email=%s", email)
        raise
    except httpx.HTTPError as exc:
        logger.exception("Register failed: Supabase admin request error email=%s", email)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Registration unavailable",
        ) from exc

    if _is_duplicate_signup_response(response):
        logger.warning(
            "Register conflict from Supabase admin email=%s status=%s",
            email,
            response.status_code,
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    if response.status_code not in {status.HTTP_200_OK, status.HTTP_201_CREATED}:
        logger.error(
            "Register failed: Supabase admin status=%s email=%s body=%s",
            response.status_code,
            email,
            response.text[:500],
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Registration unavailable",
        )

    data = response.json()
    if not isinstance(data, dict) or not data.get("id"):
        logger.error(
            "Register failed: Supabase admin returned invalid payload email=%s payload=%s",
            email,
            data,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Registration unavailable",
        )
    return data


async def _ensure_profile_row(
    *,
    user_id: str,
    email: str,
    display_name: str | None,
) -> dict[str, Any]:
    normalized_email = _normalized_email(email)
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.profiles (
                    user_id,
                    email,
                    display_name,
                    onboarding_state,
                    role,
                    role_v2,
                    is_admin,
                    created_at,
                    updated_at
                )
                VALUES (
                    %s,
                    %s,
                    %s,
                    'registered_unverified',
                    'student',
                    'user',
                    false,
                    now(),
                    now()
                )
                ON CONFLICT (user_id) DO UPDATE
                  SET email = excluded.email,
                      display_name = COALESCE(app.profiles.display_name, excluded.display_name),
                      updated_at = now()
                RETURNING user_id,
                          email,
                          display_name,
                          onboarding_state,
                          role_v2,
                          is_admin,
                          created_at,
                          updated_at
                """,
                (user_id, normalized_email, display_name),
            )
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else {}


async def _insert_auth_event_best_effort(
    *,
    user_id: str | None,
    email: str | None,
    event: str,
    request: Request,
    metadata: dict[str, Any] | None = None,
) -> None:
    try:
        await repositories.insert_auth_event(
            user_id=user_id,
            email=email,
            event=event,
            ip_address=await _client_ip(request),
            user_agent=request.headers.get("user-agent"),
            metadata=metadata,
        )
    except Exception:
        logger.warning(
            "Auth event logging skipped event=%s user_id=%s email=%s",
            event,
            user_id,
            email,
            exc_info=True,
        )


async def _profile_response(user_id: str) -> schemas.Profile:
    profile = await repositories.get_profile(user_id)
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile missing",
        )

    onboarding_state = await sync_onboarding_state(user_id)
    is_teacher = await models.is_teacher_user(user_id)
    user = await repositories.get_user_by_id(user_id) or {}
    membership = await repositories.get_membership(user_id)
    membership_active = is_membership_active(
        str((membership or {}).get("status") or ""),
        (membership or {}).get("end_date"),
    )

    payload = dict(profile)
    payload["onboarding_state"] = onboarding_state
    payload["is_teacher"] = bool(is_teacher)
    payload["email_verified"] = bool(
        user.get("email_confirmed_at") or user.get("confirmed_at")
    )
    payload["membership_active"] = bool(membership_active)
    return schemas.Profile(**payload)


def _consume_rate_limit(
    attempts: defaultdict[str, deque[float]],
    key: str,
    *,
    max_attempts: int,
) -> bool:
    bucket = attempts[key]
    now = time.monotonic()
    while bucket and now - bucket[0] > _RATE_LIMIT_WINDOW_SECONDS:
        bucket.popleft()
    if len(bucket) >= max_attempts:
        return False
    bucket.append(now)
    return True


def _rate_limited_response() -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        content={"error": "rate_limited"},
    )


def _normalized_email(email: str) -> str:
    return email.strip().lower()


def _require_valid_invite_token(email: str, invite_token: str | None) -> None:
    if not invite_token:
        return

    try:
        invited_email = validate_invite_token(invite_token)
    except InvalidInviteTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="invalid_or_expired_token",
        ) from exc

    if invited_email != _normalized_email(email):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="invalid_or_expired_token",
        )


@router.post("/oauth")
async def oauth_legacy_disabled():
    # Legacy backend OAuth endpoint is disabled in favor of Supabase client-side OAuth.
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Legacy OAuth endpoint disabled. Use Supabase OAuth.",
    )


@router.post(
    "/register",
    response_model=RegisterTokenResponse,
    status_code=status.HTTP_201_CREATED,
)
async def register(
    payload: schemas.AuthRegisterRequest,
    request: Request,
    background_tasks: BackgroundTasks,
):
    _require_valid_invite_token(payload.email, payload.invite_token)

    existing = await repositories.get_user_by_email(payload.email)
    if existing:
        logger.warning("Register conflict email=%s", payload.email)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Email already registered"
        )

    try:
        auth_user = await _create_supabase_auth_user(
            email=payload.email,
            password=payload.password,
            display_name=payload.display_name,
        )
        user_id = str(auth_user["id"])
        profile = await _ensure_profile_row(
            user_id=user_id,
            email=str(auth_user.get("email") or payload.email),
            display_name=payload.display_name,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Register failed unexpectedly email=%s", payload.email)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Registration unavailable",
        ) from exc

    claims = {
        "role": profile.get("role_v2", "user") or "user",
        "is_admin": bool(profile.get("is_admin")),
        "is_teacher": False,
    }
    access_token = create_access_token(user_id, claims=claims)
    await _insert_auth_event_best_effort(
        user_id=user_id,
        email=str(auth_user.get("email") or payload.email),
        event="register_success",
        request=request,
        metadata=None,
    )
    background_tasks.add_task(
        _enqueue_verification_email,
        str(auth_user.get("email") or payload.email),
    )
    return RegisterTokenResponse(access_token=access_token)


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


@router.post("/request-password-reset", status_code=status.HTTP_202_ACCEPTED)
@router.post(
    "/forgot-password",
    status_code=status.HTTP_202_ACCEPTED,
    include_in_schema=False,
)
async def request_password_reset(payload: schemas.AuthForgotPasswordRequest):
    normalized_email = _normalized_email(payload.email)
    if not _consume_rate_limit(
        _password_reset_attempts,
        normalized_email,
        max_attempts=_PASSWORD_RESET_RATE_LIMIT,
    ):
        return _rate_limited_response()

    user = await repositories.get_user_by_email(normalized_email)
    if user:
        try:
            await send_password_reset_email(user["email"])
        except Exception:
            logger.exception(
                "Failed to send password reset email email=%s",
                normalized_email,
            )
    return {"status": "ok"}


@router.post("/reset-password")
async def reset_password(payload: schemas.AuthResetPasswordRequest):
    try:
        result = await reset_password_with_token(payload.token, payload.new_password)
    except InvalidPasswordResetTokenError:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "invalid_or_expired_token"},
        )
    return {"status": result["status"]}


@router.post("/send-invite")
async def send_invite(payload: schemas.AuthForgotPasswordRequest, current: CurrentUser):
    sender_key = str(current["id"])
    recipient_email = _normalized_email(payload.email)
    if not _consume_rate_limit(
        _send_invite_attempts,
        sender_key,
        max_attempts=_SEND_INVITE_RATE_LIMIT,
    ):
        return _rate_limited_response()

    try:
        await send_invite_email(recipient_email, inviter_email=current.get("email"))
    except Exception as exc:
        logger.exception(
            "Failed to send invite email sender=%s recipient=%s",
            current.get("email"),
            recipient_email,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to send invite email",
        ) from exc

    return {"status": "ok"}


@router.get("/validate-invite")
async def validate_invite(token: str = Query(..., min_length=1)):
    try:
        email = validate_invite_token(token)
    except InvalidInviteTokenError:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "invalid_or_expired_token"},
        )

    return {"status": "valid", "email": email}


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
    return await _profile_response(str(current["id"]))


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
    await sync_onboarding_state(str(current["id"]))
    return await _profile_response(str(current["id"]))


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
        await models.cleanup_media_object(previous_media_id)

    return await _profile_response(str(current["id"]))


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
