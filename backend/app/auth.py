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
from .db import get_conn

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")
oauth2_optional_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)


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
        if not jwks_url:
            raise exc
        issuer = _supabase_jwt_issuer()
        try:
            payload = verify_supabase_access_token(
                token, jwks_url=jwks_url, issuer=issuer
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

    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT u.id,
                   u.email,
                   COALESCE(p.role_v2, 'user') AS role_v2,
                   COALESCE(p.is_admin, false) AS is_admin,
                   p.display_name,
                   p.bio,
                   p.photo_url
            FROM auth.users AS u
            LEFT JOIN app.profiles AS p ON p.user_id = u.id
            WHERE u.id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = await cur.fetchone()
    if not row:
        raise credentials_exception
    data = dict(row)
    data.setdefault("role_v2", "user")
    data["is_admin"] = bool(data.get("is_admin"))
    return data


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

    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT u.id,
                   u.email,
                   COALESCE(p.role_v2, 'user') AS role_v2,
                   COALESCE(p.is_admin, false) AS is_admin,
                   p.display_name,
                   p.bio,
                   p.photo_url
            FROM auth.users AS u
            LEFT JOIN app.profiles AS p ON p.user_id = u.id
            WHERE u.id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = await cur.fetchone()
    if not row:
        return None
    data = dict(row)
    data.setdefault("role_v2", "user")
    data["is_admin"] = bool(data.get("is_admin"))
    return data


CurrentUser = Annotated[dict, Depends(get_current_user)]
OptionalCurrentUser = Annotated[dict | None, Depends(get_optional_user)]
