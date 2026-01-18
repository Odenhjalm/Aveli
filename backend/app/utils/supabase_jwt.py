from __future__ import annotations

import time
from typing import Any

import httpx
from jose import JWTError, jwk, jwt

_DEFAULT_JWKS_CACHE_SECONDS = 300
_JWKS_CACHE: dict[str, Any] = {
    "url": None,
    "expires_at": 0.0,
    "keys": {},
}


class SupabaseJwtError(Exception):
    pass


def _fetch_jwks(url: str) -> dict[str, Any]:
    try:
        resp = httpx.get(url, timeout=5)
        resp.raise_for_status()
        data = resp.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise SupabaseJwtError(f"Failed to fetch JWKS: {exc}") from exc
    if not isinstance(data, dict) or "keys" not in data:
        raise SupabaseJwtError("JWKS response missing keys")
    return data


def _normalize_jwks(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    keys: dict[str, dict[str, Any]] = {}
    for entry in data.get("keys", []):
        if not isinstance(entry, dict):
            continue
        kid = entry.get("kid")
        if kid:
            keys[kid] = entry
    return keys


def _get_cached_keys(url: str, *, force_refresh: bool = False) -> dict[str, dict[str, Any]]:
    now = time.monotonic()
    if not force_refresh:
        if _JWKS_CACHE["url"] == url and now < _JWKS_CACHE["expires_at"]:
            cached = _JWKS_CACHE.get("keys")
            if isinstance(cached, dict):
                return cached

    data = _fetch_jwks(url)
    keys = _normalize_jwks(data)
    _JWKS_CACHE["url"] = url
    _JWKS_CACHE["keys"] = keys
    _JWKS_CACHE["expires_at"] = now + _DEFAULT_JWKS_CACHE_SECONDS
    return keys


def verify_supabase_access_token(
    token: str,
    *,
    jwks_url: str,
    issuer: str | None = None,
) -> dict[str, Any]:
    try:
        header = jwt.get_unverified_header(token)
    except JWTError as exc:
        raise SupabaseJwtError("Invalid token header") from exc

    alg = header.get("alg")
    if alg not in ("RS256", "ES256"):
        raise SupabaseJwtError(f"Unsupported JWT alg: {alg}")
    kid = header.get("kid")
    if not kid:
        raise SupabaseJwtError("JWT header missing kid")

    keys = _get_cached_keys(jwks_url)
    key_data = keys.get(kid)
    if not key_data:
        keys = _get_cached_keys(jwks_url, force_refresh=True)
        key_data = keys.get(kid)
    if not key_data:
        raise SupabaseJwtError("JWT kid not found in JWKS")

    key = jwk.construct(key_data, alg)
    options = {"verify_aud": False}
    try:
        return jwt.decode(
            token,
            key,
            algorithms=[alg],
            issuer=issuer,
            options=options,
        )
    except JWTError as exc:
        raise SupabaseJwtError("JWT verification failed") from exc
