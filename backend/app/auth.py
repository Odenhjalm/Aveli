from datetime import datetime, timedelta, timezone
import hashlib
import uuid
from typing import Annotated, Any

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
from passlib.context import CryptContext

from .config import settings
from .utils.supabase_jwt import SupabaseJwtError, verify_supabase_access_token
pwd_context = CryptContext(
    schemes=["bcrypt_sha256", "bcrypt"],
    deprecated="auto",
)
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")
oauth2_optional_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)


def _configure_password_backends() -> None:
    # Prefer os_crypt when available so long passwords remain safe even if the
    # pyca/bcrypt backend rejects >72-byte secrets.
    for scheme in ("bcrypt_sha256", "bcrypt"):
        handler = pwd_context.handler(scheme)
        if handler.has_backend("os_crypt"):
            handler.set_backend("os_crypt")


_configure_password_backends()


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    return pwd_context.verify(password, hashed)


def decode_jwt(token: str) -> dict[str, Any]:
    """Decode JWT without triggering python-jose exp verification."""
    return jwt.decode(
        token,
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
        options={"verify_signature": True, "verify_exp": False},
    )


def _supabase_jwks_url() -> str | None:
    if settings.supabase_jwks_url:
        return str(settings.supabase_jwks_url)
    if settings.supabase_url is None:
        return None
    base = settings.supabase_url.unicode_string().rstrip("/")
    return f"{base}/auth/v1/.well-known/jwks.json"


def _supabase_jwt_issuer() -> str | None:
    if settings.supabase_jwt_issuer:
        return settings.supabase_jwt_issuer
    if settings.supabase_url is None:
        return None
    base = settings.supabase_url.unicode_string().rstrip("/")
    return f"{base}/auth/v1"


def _decode_access_token(token: str) -> tuple[dict[str, Any], str]:
    try:
        return decode_jwt(token), "local"
    except JWTError as exc:
        jwks_url = _supabase_jwks_url()
        jwt_secrets = settings.supabase_jwt_secrets
        if not jwks_url and not jwt_secrets:
            raise exc
        if not jwks_url:
            jwks_url = None
        issuer = _supabase_jwt_issuer()
        try:
            payload = verify_supabase_access_token(
                token,
                jwks_url=jwks_url,
                issuer=issuer,
                jwt_secrets=jwt_secrets,
            )
        except SupabaseJwtError as sup_exc:
            raise JWTError("Supabase JWT verification failed") from sup_exc
        return payload, "supabase"


def is_token_expired(payload: dict[str, Any], *, now: datetime | None = None) -> bool:
    exp = payload.get("exp")
    if exp is None:
        return False

    if isinstance(exp, (int, float)):
        exp_dt = datetime.fromtimestamp(exp, tz=timezone.utc)
    elif isinstance(exp, datetime):
        exp_dt = exp if exp.tzinfo else exp.replace(tzinfo=timezone.utc)
    elif isinstance(exp, str):
        try:
            exp_dt = datetime.fromisoformat(exp)
        except ValueError:
            return False
        if exp_dt.tzinfo is None:
            exp_dt = exp_dt.replace(tzinfo=timezone.utc)
    else:
        return False

    now = now or datetime.now(timezone.utc)
    return exp_dt <= now


def create_access_token(
    sub: str,
    expires_minutes: int | None = None,
    *,
    claims: dict[str, Any] | None = None,
) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=expires_minutes or settings.jwt_expires_minutes
    )
    to_encode: dict[str, Any] = {"sub": sub, "exp": expire, "token_type": "access"}
    if claims:
        to_encode.update(claims)
    return jwt.encode(to_encode, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_refresh_token(
    sub: str, expires_minutes: int | None = None
) -> tuple[str, str, datetime]:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=expires_minutes or settings.jwt_refresh_expires_minutes
    )
    jti = str(uuid.uuid4())
    to_encode: dict[str, Any] = {
        "sub": sub,
        "exp": expire,
        "token_type": "refresh",
        "jti": jti,
    }
    token = jwt.encode(to_encode, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, jti, expire


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _bool_claim(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _mapping_claim(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _build_current_user(user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    app_metadata = _mapping_claim(payload.get("app_metadata"))
    user_metadata = _mapping_claim(payload.get("user_metadata"))
    role_value = (
        payload.get("role_v2")
        or payload.get("role")
        or app_metadata.get("role_v2")
        or app_metadata.get("role")
        or user_metadata.get("role_v2")
        or user_metadata.get("role")
        or "user"
    )
    normalized_role = str(role_value or "user").strip().lower() or "user"
    is_admin = _bool_claim(payload.get("is_admin")) or _bool_claim(
        app_metadata.get("is_admin")
    )
    if normalized_role == "admin":
        is_admin = True

    display_name = (
        payload.get("display_name")
        or user_metadata.get("display_name")
        or user_metadata.get("full_name")
        or payload.get("name")
    )
    photo_url = (
        payload.get("photo_url")
        or payload.get("avatar_url")
        or user_metadata.get("photo_url")
        or user_metadata.get("avatar_url")
    )

    return {
        "id": user_id,
        "email": payload.get("email"),
        "role_v2": normalized_role,
        "is_admin": is_admin,
        "display_name": display_name,
        "bio": user_metadata.get("bio"),
        "photo_url": photo_url,
    }


async def get_current_user(token: Annotated[str, Depends(oauth2_scheme)]):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload, source = _decode_access_token(token)
        if is_token_expired(payload):
            raise credentials_exception
        user_id: str | None = payload.get("sub")
        token_type = payload.get("token_type", "access")
        if user_id is None:
            raise credentials_exception
        if source == "local" and token_type != "access":
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover
        raise credentials_exception from exc

    return _build_current_user(user_id, payload)


async def get_optional_user(
    token: Annotated[str | None, Depends(oauth2_optional_scheme)],
):
    if not token:
        return None
    try:
        payload, source = _decode_access_token(token)
        if is_token_expired(payload):
            return None
        user_id: str | None = payload.get("sub")
        token_type = payload.get("token_type", "access")
        if user_id is None:
            return None
        if source == "local" and token_type != "access":
            return None
    except JWTError:
        return None
    except Exception:  # pragma: no cover
        return None

    return _build_current_user(user_id, payload)


CurrentUser = Annotated[dict, Depends(get_current_user)]
OptionalCurrentUser = Annotated[dict | None, Depends(get_optional_user)]
