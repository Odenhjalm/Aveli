import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
from jose import JWTError
from psycopg.rows import dict_row

from ..auth import (
    CurrentUser,
    _normalized_subject_role,
    _validated_onboarding_state,
    create_access_token,
    create_refresh_token,
    decode_jwt,
    is_token_expired,
)
from ..db import pool
from ..repositories import auth_subjects as auth_subjects_repo
from .. import models, schemas
from ..services.email_verification import (
    InvalidPasswordResetTokenError,
    reset_password_with_token,
)
from ..services import supabase_auth

_ONBOARDING_CONFLICT_PATHS = frozenset(
    {
        "/auth/onboarding/create-profile",
        "/auth/onboarding/complete",
    }
)
_ONBOARDING_CONFLICT_FALLBACK_DETAIL = "Onboarding kunde inte fortsätta."


class _OnboardingConflictDetailRoute(APIRoute):
    def get_route_handler(self):
        original_route_handler = super().get_route_handler()

        async def route_handler(request: Request):
            try:
                return await original_route_handler(request)
            except HTTPException as exc:
                if (
                    exc.status_code == status.HTTP_409_CONFLICT
                    and request.url.path in _ONBOARDING_CONFLICT_PATHS
                ):
                    detail = (
                        exc.detail
                        if isinstance(exc.detail, str) and exc.detail.strip()
                        else _ONBOARDING_CONFLICT_FALLBACK_DETAIL
                    )
                    return JSONResponse(
                        status_code=exc.status_code,
                        content={"detail": detail},
                        headers=exc.headers,
                    )
                raise

        return route_handler


router = APIRouter(
    prefix="/auth",
    tags=["auth"],
    route_class=_OnboardingConflictDetailRoute,
)

_RATE_LIMIT_WINDOW_SECONDS = 60
_RATE_LIMIT_MAX_ATTEMPTS = 5
_login_attempts: defaultdict[str, deque[float]] = defaultdict(deque)
_CANONICAL_AUTH_EVENT_TYPES = frozenset(
    {
        "admin_bootstrap_consumed",
        "onboarding_completed",
        "teacher_role_granted",
        "teacher_role_revoked",
    }
)

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


def _normalized_email(email: str) -> str:
    return email.strip().lower()


async def _record_auth_event(
    *,
    user_id: str | None,
    email: str | None,
    event: str,
    request: Request,
    metadata: dict[str, Any] | None = None,
) -> None:
    del email, request
    if event not in _CANONICAL_AUTH_EVENT_TYPES or not user_id:
        return
    await models.record_auth_event(
        actor_user_id=user_id,
        subject_user_id=user_id,
        event_type=event,
        metadata=metadata,
    )


async def _token_claims(user_id: str) -> dict[str, Any]:
    """Return non-authoritative convenience claims for the issued token."""
    auth_subject = await auth_subjects_repo.get_auth_subject(user_id)
    if not auth_subject:
        raise HTTPException(status_code=404, detail="subject_not_found")
    role = _normalized_subject_role(auth_subject.get("role"))
    if role is None:
        raise HTTPException(status_code=500, detail="internal_error")
    onboarding_state = _validated_onboarding_state(
        auth_subject.get("onboarding_state")
    )
    if onboarding_state is None:
        raise HTTPException(status_code=500, detail="internal_error")
    return {
        "role": role,
    }


async def _complete_onboarding_at_canonical_route(user_id: str) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET onboarding_state = 'completed'
                 WHERE user_id = %s
                   AND onboarding_state = 'welcome_pending'
                 RETURNING user_id, email, onboarding_state, role::text as role
                """,
                (user_id,),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


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
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="rate_limited",
        )

    try:
        user_id = await models.create_user(payload.email, payload.password)
    except supabase_auth.SupabaseAuthConflictError as exc:
        await _record_auth_event(
            user_id=None,
            email=payload.email,
            event="register_conflict",
            request=request,
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="email_already_registered",
        ) from exc
    except supabase_auth.SupabaseAuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="auth_provider_unavailable",
        ) from exc

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
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="rate_limited",
        )

    try:
        user_id = await models.authenticate_user(payload.email, payload.password)
    except (
        supabase_auth.SupabaseAuthInvalidCredentialsError,
        supabase_auth.SupabaseAuthEmailNotConfirmedError,
    ) as exc:
        await _record_auth_event(
            user_id=None,
            email=payload.email,
            event="login_invalid_credentials",
            request=request,
        )
        raise HTTPException(status_code=401, detail="invalid_credentials") from exc
    except supabase_auth.SupabaseAuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="auth_provider_unavailable",
        ) from exc

    auth_subject = await auth_subjects_repo.get_auth_subject(user_id)
    if not auth_subject:
        await _record_auth_event(
            user_id=str(user_id),
            email=payload.email,
            event="login_missing_auth_subject",
            request=request,
        )
        raise HTTPException(status_code=401, detail="invalid_credentials")

    user_id = str(user_id)
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
    try:
        result = await reset_password_with_token(payload.token, payload.new_password)
    except InvalidPasswordResetTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="invalid_or_expired_token",
        ) from exc
    return {"status": result["status"]}


@router.post("/refresh", response_model=schemas.Token)
async def refresh_token(payload: schemas.TokenRefreshRequest, request: Request):
    try:
        decoded = decode_jwt(payload.refresh_token)
        if is_token_expired(decoded):
            raise HTTPException(status_code=401, detail="refresh_token_invalid")
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="refresh_token_invalid") from exc

    if decoded.get("token_type") != "refresh":
        raise HTTPException(status_code=401, detail="refresh_token_invalid")

    user_id: str | None = decoded.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="refresh_token_invalid")

    jti: str | None = decoded.get("jti")
    if not jti:
        raise HTTPException(status_code=401, detail="refresh_token_invalid")

    token_row = await models.validate_refresh_token(jti, payload.refresh_token)
    if not token_row:
        await _record_auth_event(
            user_id=user_id,
            email=None,
            event="refresh_invalid",
            request=request,
            metadata={"jti": jti},
        )
        raise HTTPException(status_code=401, detail="refresh_token_invalid")

    db_user_id = str(token_row.get("user_id")) if token_row.get("user_id") else None
    if db_user_id and db_user_id != user_id:
        await _record_auth_event(
            user_id=user_id,
            email=None,
            event="refresh_user_mismatch",
            request=request,
            metadata={"expected": user_id, "actual": db_user_id},
        )
        raise HTTPException(status_code=401, detail="refresh_token_invalid")

    user_row = await models.get_user_by_id(user_id)
    email = user_row.get("email") if user_row else None

    claims = await _token_claims(user_id)
    access_token = create_access_token(user_id, claims=claims)
    new_refresh_token, new_jti, new_exp = create_refresh_token(user_id)
    await models.register_refresh_token(
        user_id,
        new_refresh_token,
        new_jti,
        new_exp,
        rotated_from_jti=jti,
    )
    await _record_auth_event(
        user_id=user_id,
        email=email,
        event="refresh_success",
        request=request,
        metadata={"old_jti": jti, "new_jti": new_jti},
    )
    return schemas.Token(access_token=access_token, refresh_token=new_refresh_token)


@router.post("/onboarding/create-profile", response_model=schemas.Profile)
async def create_onboarding_profile(
    payload: schemas.OnboardingCreateProfileRequest,
    current_user: CurrentUser,
):
    user_id = str(current_user["id"])
    auth_subject = await auth_subjects_repo.get_auth_subject(user_id)
    if not auth_subject:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="subject_not_found",
        )
    previous_state = _validated_onboarding_state(auth_subject.get("onboarding_state"))
    if previous_state != "incomplete":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Profilsteget kan bara slutföras från ofullständig onboarding.",
        )

    profile = await models.update_profile(
        user_id,
        display_name=payload.display_name,
        bio=payload.bio,
    )
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="profile_not_found",
        )
    updated_subject = await auth_subjects_repo.mark_create_profile_step_complete(
        user_id
    )
    if not updated_subject:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Profilsteget kan bara slutföras från ofullständig onboarding.",
        )
    return schemas.Profile(**profile)


@router.post(
    "/onboarding/complete",
    response_model=schemas.OnboardingCompletionResponse,
)
async def complete_onboarding(request: Request, current_user: CurrentUser):
    user_id = str(current_user["id"])
    auth_subject = await auth_subjects_repo.get_auth_subject(user_id)
    if not auth_subject:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="subject_not_found",
        )

    previous_state = _validated_onboarding_state(auth_subject.get("onboarding_state"))
    if previous_state is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="internal_error",
        )
    if previous_state != "welcome_pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Välkomststeget måste bekräftas först.",
        )

    updated_subject = await _complete_onboarding_at_canonical_route(user_id)
    if not updated_subject:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="subject_not_found",
        )

    await _record_auth_event(
        user_id=user_id,
        email=current_user.get("email"),
        event="onboarding_completed",
        request=request,
        metadata={
            "previous_onboarding_state": previous_state,
            "current_onboarding_state": updated_subject.get("onboarding_state"),
        },
    )

    return schemas.OnboardingCompletionResponse(
        status="completed",
        onboarding_state="completed",
        token_refresh_required=True,
    )
