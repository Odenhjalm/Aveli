from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import httpx

from ..config import settings

_AUTH_TIMEOUT_SECONDS = 10.0


class SupabaseAuthError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        error_code: str | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.error_code = error_code


class SupabaseAuthConfigurationError(SupabaseAuthError):
    pass


class SupabaseAuthConflictError(SupabaseAuthError):
    pass


class SupabaseAuthInvalidCredentialsError(SupabaseAuthError):
    pass


class SupabaseAuthEmailNotConfirmedError(SupabaseAuthError):
    pass


@dataclass(frozen=True)
class SupabaseAuthIdentity:
    user_id: str
    email: str | None
    user: dict[str, Any]
    session: dict[str, Any] | None
    raw: dict[str, Any]


@dataclass(frozen=True)
class SupabaseAuthSession:
    user_id: str
    email: str | None
    access_token: str
    refresh_token: str
    token_type: str
    expires_in: int | None
    user: dict[str, Any]
    raw: dict[str, Any]


def _auth_base_url() -> str:
    if settings.supabase_url is None:
        raise SupabaseAuthConfigurationError("SUPABASE_URL is not configured")
    base = settings.supabase_url.unicode_string().rstrip("/")
    if base.endswith("/auth/v1"):
        return base
    return f"{base}/auth/v1"


def _public_api_key() -> str:
    key = settings.supabase_anon_key or settings.supabase_service_role_key
    if not key:
        raise SupabaseAuthConfigurationError("Supabase Auth API key is not configured")
    return key


def _admin_api_key() -> str:
    key = settings.supabase_service_role_key
    if not key:
        raise SupabaseAuthConfigurationError("SUPABASE_SERVICE_ROLE_KEY is not configured")
    return key


def _headers(api_key: str) -> dict[str, str]:
    return {
        "apikey": api_key,
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


def _message_from_payload(payload: object) -> str:
    if isinstance(payload, dict):
        for key in ("msg", "message", "error_description", "error"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return "Supabase Auth request failed"


def _error_code_from_payload(payload: object) -> str | None:
    if isinstance(payload, dict):
        for key in ("error_code", "code", "error"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return None


def _raise_auth_error(status_code: int, payload: object) -> None:
    message = _message_from_payload(payload)
    error_code = _error_code_from_payload(payload)
    normalized = f"{message} {error_code or ''}".lower()

    if status_code in {400, 409, 422} and (
        "already registered" in normalized
        or "already exists" in normalized
        or "user exists" in normalized
    ):
        raise SupabaseAuthConflictError(
            message,
            status_code=status_code,
            error_code=error_code,
        )

    if "email not confirmed" in normalized or "email_not_confirmed" in normalized:
        raise SupabaseAuthEmailNotConfirmedError(
            message,
            status_code=status_code,
            error_code=error_code,
        )

    if status_code in {400, 401, 403} and (
        "invalid login" in normalized
        or "invalid credentials" in normalized
        or "invalid_grant" in normalized
    ):
        raise SupabaseAuthInvalidCredentialsError(
            message,
            status_code=status_code,
            error_code=error_code,
        )

    raise SupabaseAuthError(message, status_code=status_code, error_code=error_code)


async def _request(
    method: str,
    path: str,
    *,
    json_body: dict[str, Any] | None = None,
    admin: bool = False,
) -> dict[str, Any]:
    api_key = _admin_api_key() if admin else _public_api_key()
    url = f"{_auth_base_url()}{path}"
    try:
        async with httpx.AsyncClient(timeout=_AUTH_TIMEOUT_SECONDS) as client:
            response = await client.request(
                method,
                url,
                headers=_headers(api_key),
                json=json_body,
            )
    except httpx.HTTPError as exc:
        raise SupabaseAuthError("Failed to reach Supabase Auth") from exc

    try:
        payload = response.json()
    except ValueError:
        payload = {}

    if response.status_code >= 400:
        _raise_auth_error(response.status_code, payload)

    if not isinstance(payload, dict):
        raise SupabaseAuthError("Supabase Auth returned an invalid response")
    return payload


def _extract_user(payload: dict[str, Any]) -> dict[str, Any]:
    user = payload.get("user")
    if isinstance(user, dict):
        return user
    if isinstance(payload.get("id"), str):
        return payload
    raise SupabaseAuthError("Supabase Auth response missing user")


def _extract_user_id(user: dict[str, Any]) -> str:
    user_id = user.get("id")
    if not isinstance(user_id, str) or not user_id.strip():
        raise SupabaseAuthError("Supabase Auth response missing user id")
    return user_id.strip()


async def signup(email: str, password: str) -> SupabaseAuthIdentity:
    normalized_email = email.strip().lower()
    payload = await _request(
        "POST",
        "/signup",
        json_body={"email": normalized_email, "password": password},
    )
    user = _extract_user(payload)
    session = payload.get("session") if isinstance(payload.get("session"), dict) else None
    return SupabaseAuthIdentity(
        user_id=_extract_user_id(user),
        email=str(user.get("email") or normalized_email),
        user=user,
        session=session,
        raw=payload,
    )


async def login_password(email: str, password: str) -> SupabaseAuthSession:
    normalized_email = email.strip().lower()
    payload = await _request(
        "POST",
        "/token?grant_type=password",
        json_body={"email": normalized_email, "password": password},
    )
    user = _extract_user(payload)
    access_token = payload.get("access_token")
    refresh_token = payload.get("refresh_token")
    token_type = str(payload.get("token_type") or "bearer")
    if not isinstance(access_token, str) or not access_token:
        raise SupabaseAuthError("Supabase Auth response missing access token")
    if not isinstance(refresh_token, str) or not refresh_token:
        raise SupabaseAuthError("Supabase Auth response missing refresh token")
    expires_in = payload.get("expires_in")
    return SupabaseAuthSession(
        user_id=_extract_user_id(user),
        email=str(user.get("email") or normalized_email),
        access_token=access_token,
        refresh_token=refresh_token,
        token_type=token_type,
        expires_in=expires_in if isinstance(expires_in, int) else None,
        user=user,
        raw=payload,
    )


async def refresh_session(refresh_token: str) -> SupabaseAuthSession:
    payload = await _request(
        "POST",
        "/token?grant_type=refresh_token",
        json_body={"refresh_token": refresh_token},
    )
    user = _extract_user(payload)
    access_token = payload.get("access_token")
    new_refresh_token = payload.get("refresh_token")
    token_type = str(payload.get("token_type") or "bearer")
    if not isinstance(access_token, str) or not access_token:
        raise SupabaseAuthError("Supabase Auth response missing access token")
    if not isinstance(new_refresh_token, str) or not new_refresh_token:
        raise SupabaseAuthError("Supabase Auth response missing refresh token")
    expires_in = payload.get("expires_in")
    return SupabaseAuthSession(
        user_id=_extract_user_id(user),
        email=str(user.get("email") or "") or None,
        access_token=access_token,
        refresh_token=new_refresh_token,
        token_type=token_type,
        expires_in=expires_in if isinstance(expires_in, int) else None,
        user=user,
        raw=payload,
    )


async def get_user(user_id: str) -> dict[str, Any]:
    payload = await _request("GET", f"/admin/users/{user_id}", admin=True)
    return _extract_user(payload)


async def update_user_password(user_id: str, password: str) -> dict[str, Any]:
    payload = await _request(
        "PUT",
        f"/admin/users/{user_id}",
        json_body={"password": password},
        admin=True,
    )
    return _extract_user(payload)


async def confirm_user_email(user_id: str) -> dict[str, Any]:
    payload = await _request(
        "PUT",
        f"/admin/users/{user_id}",
        json_body={"email_confirm": True},
        admin=True,
    )
    return _extract_user(payload)
