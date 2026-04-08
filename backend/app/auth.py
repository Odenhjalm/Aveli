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


def _normalized_subject_role(role_v2: object, role: object) -> str | None:
    for candidate in (role_v2, role):
        normalized = str(candidate or "").strip().lower()
        if normalized in {"learner", "teacher"}:
            return normalized
    return None


def _validated_onboarding_state(value: object) -> str | None:
    normalized = str(value or "").strip().lower()
    if normalized in {"incomplete", "completed"}:
        return normalized
    return None


async def _build_current_user(user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    from .repositories.auth_subjects import get_auth_subject
    from .repositories.profiles import get_profile

    auth_subject = await get_auth_subject(user_id)
    if auth_subject is None:
        raise ValueError("Canonical auth subject missing")

    normalized_role = _normalized_subject_role(
        auth_subject.get("role_v2"),
        auth_subject.get("role"),
    )
    onboarding_state = _validated_onboarding_state(auth_subject.get("onboarding_state"))
    is_admin = auth_subject.get("is_admin")
    if normalized_role is None:
        raise ValueError("Canonical role authority missing")
    if onboarding_state is None:
        raise ValueError("Canonical onboarding_state invalid")
    if not isinstance(is_admin, bool):
        raise ValueError("Canonical is_admin invalid")

    profile = await get_profile(user_id)

    return {
        "id": user_id,
        "email": payload.get("email"),
        "onboarding_state": onboarding_state,
        "role": normalized_role,
        "role_v2": normalized_role,
        "is_admin": is_admin,
        "display_name": profile.get("display_name") if profile else None,
        "bio": profile.get("bio") if profile else None,
        "photo_url": profile.get("photo_url") if profile else None,
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

    return await _build_current_user(user_id, payload)


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

    try:
        return await _build_current_user(user_id, payload)
    except ValueError:
        return None


CurrentUser = Annotated[dict, Depends(get_current_user)]
OptionalCurrentUser = Annotated[dict | None, Depends(get_optional_user)]
