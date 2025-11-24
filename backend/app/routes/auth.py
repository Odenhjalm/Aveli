import time
from collections import defaultdict, deque
from typing import Any

from fastapi import APIRouter, HTTPException, Request, status
from jose import JWTError

from ..auth import (
    create_access_token,
    create_refresh_token,
    decode_jwt,
    is_token_expired,
    verify_password,
)
from .. import models, schemas

router = APIRouter(prefix="/auth", tags=["auth"])

_RATE_LIMIT_WINDOW_SECONDS = 60
_RATE_LIMIT_MAX_ATTEMPTS = 5
_login_attempts: defaultdict[str, deque[float]] = defaultdict(deque)


_RATE_LIMIT_MESSAGE = "För många försök. Försök igen om en liten stund."


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client:
        return request.client.host
    return "unknown"


def _rate_limit_key(ip: str, email: str | None) -> str:
    if email:
        return f"{ip}:{email.lower()}"
    return ip


def _enforce_login_rate_limit(request: Request, email: str | None) -> bool:
    ip = _client_ip(request)
    key = _rate_limit_key(ip, email)
    bucket = _login_attempts[key]
    now = time.monotonic()
    while bucket and now - bucket[0] > _RATE_LIMIT_WINDOW_SECONDS:
        bucket.popleft()
    if len(bucket) >= _RATE_LIMIT_MAX_ATTEMPTS:
        return False
    bucket.append(now)
    return True


def _reset_login_rate_limit(request: Request, email: str | None) -> None:
    ip = _client_ip(request)
    key = _rate_limit_key(ip, email)
    if key in _login_attempts:
        _login_attempts[key].clear()


async def _record_auth_event(
    *,
    user_id: str | None,
    email: str | None,
    event: str,
    request: Request,
    metadata: dict[str, Any] | None = None,
) -> None:
    ip = _client_ip(request)
    user_agent = request.headers.get("user-agent")
    await models.record_auth_event(
        user_id=user_id,
        email=email,
        event=event,
        ip_address=ip,
        user_agent=user_agent,
        metadata=metadata,
    )


async def _token_claims(user_id: str) -> dict[str, Any]:
    user = await models.get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    profile = await models.get_profile_row(user_id)
    is_teacher = await models.is_teacher_user(user_id)
    role = (profile.get("role_v2") if profile else "user") or "user"
    is_admin = bool(profile.get("is_admin")) if profile else False
    return {
        "role": role,
        "is_admin": is_admin,
        "is_teacher": bool(is_teacher),
    }


@router.post(
    "/register", response_model=schemas.Token, status_code=status.HTTP_201_CREATED
)
async def register(payload: schemas.AuthRegisterRequest, request: Request):
    if not _enforce_login_rate_limit(request, payload.email):
        await _record_auth_event(
            user_id=None,
            email=payload.email,
            event="register_rate_limited",
            request=request,
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=_RATE_LIMIT_MESSAGE
        )

    existing = await models.get_user_by_email(payload.email)
    if existing:
        await _record_auth_event(
            user_id=str(existing["id"]),
            email=payload.email,
            event="register_conflict",
            request=request,
        )
        raise HTTPException(status_code=400, detail="Email already registered")

    user_id = await models.create_user(
        payload.email, payload.password, payload.display_name
    )
    user_id_str = str(user_id)
    claims = await _token_claims(user_id_str)
    access_token = create_access_token(user_id_str, claims=claims)
    refresh_token, refresh_jti, refresh_exp = create_refresh_token(user_id_str)
    await models.register_refresh_token(
        user_id_str, refresh_token, refresh_jti, refresh_exp
    )
    await _record_auth_event(
        user_id=user_id_str,
        email=payload.email,
        event="register_success",
        request=request,
        metadata={"refresh_jti": refresh_jti},
    )
    _reset_login_rate_limit(request, payload.email)
    return schemas.Token(access_token=access_token, refresh_token=refresh_token)


@router.post("/login", response_model=schemas.Token)
async def login(payload: schemas.AuthLoginRequest, request: Request):
    if not _enforce_login_rate_limit(request, payload.email):
        await _record_auth_event(
            user_id=None,
            email=payload.email,
            event="login_rate_limited",
            request=request,
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=_RATE_LIMIT_MESSAGE
        )

    user = await models.get_user_by_email(payload.email)
    if not user:
        await _record_auth_event(
            user_id=None,
            email=payload.email,
            event="login_invalid_user",
            request=request,
        )
        raise HTTPException(status_code=401, detail="Invalid credentials")

    hashed = user.get("encrypted_password")
    if not hashed or not verify_password(payload.password, hashed):
        await _record_auth_event(
            user_id=str(user["id"]),
            email=payload.email,
            event="login_invalid_password",
            request=request,
        )
        raise HTTPException(status_code=401, detail="Invalid credentials")

    user_id = str(user["id"])
    claims = await _token_claims(user_id)
    access_token = create_access_token(user_id, claims=claims)
    refresh_token, refresh_jti, refresh_exp = create_refresh_token(user_id)
    await models.register_refresh_token(
        user_id, refresh_token, refresh_jti, refresh_exp
    )
    await _record_auth_event(
        user_id=user_id,
        email=payload.email,
        event="login_success",
        request=request,
        metadata={"refresh_jti": refresh_jti},
    )
    _reset_login_rate_limit(request, payload.email)
    return schemas.Token(access_token=access_token, refresh_token=refresh_token)


@router.post("/forgot-password", status_code=status.HTTP_202_ACCEPTED)
async def forgot_password(payload: schemas.AuthForgotPasswordRequest):
    # Vi returnerar alltid 202 för att undvika att avslöja om e-posten finns
    user = await models.get_user_by_email(payload.email)
    if user:
        # TODO: Integrera med e-post/återställningstoken när det behövs
        pass
    return {"status": "ok"}


@router.post("/reset-password")
async def reset_password(payload: schemas.AuthResetPasswordRequest):
    user = await models.get_user_by_email(payload.email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    await models.update_user_password(user["id"], payload.new_password)
    return {"status": "ok"}


@router.post("/refresh", response_model=schemas.Token)
async def refresh_token(payload: schemas.TokenRefreshRequest, request: Request):
    try:
        decoded = decode_jwt(payload.refresh_token)
        if is_token_expired(decoded):
            raise HTTPException(status_code=401, detail="Refresh token expired")
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid refresh token") from exc

    if decoded.get("token_type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    user_id: str | None = decoded.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    jti: str | None = decoded.get("jti")
    if not jti:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    token_row = await models.validate_refresh_token(jti, payload.refresh_token)
    if not token_row:
        await _record_auth_event(
            user_id=user_id,
            email=None,
            event="refresh_invalid",
            request=request,
            metadata={"jti": jti},
        )
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    db_user_id = str(token_row.get("user_id")) if token_row.get("user_id") else None
    if db_user_id and db_user_id != user_id:
        await _record_auth_event(
            user_id=user_id,
            email=None,
            event="refresh_user_mismatch",
            request=request,
            metadata={"expected": user_id, "actual": db_user_id},
        )
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    user_row = await models.get_user_by_id(user_id)
    email = user_row.get("email") if user_row else None

    claims = await _token_claims(user_id)
    access_token = create_access_token(user_id, claims=claims)
    new_refresh_token, new_jti, new_exp = create_refresh_token(user_id)
    await models.register_refresh_token(user_id, new_refresh_token, new_jti, new_exp)
    await _record_auth_event(
        user_id=user_id,
        email=email,
        event="refresh_success",
        request=request,
        metadata={"old_jti": jti, "new_jti": new_jti},
    )
    return schemas.Token(access_token=access_token, refresh_token=new_refresh_token)
