from __future__ import annotations

import base64
from datetime import datetime, timedelta, timezone

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from jose import JWTError, jwt

from app import auth
from app.utils import supabase_jwt


def _b64url_uint(value: int) -> str:
    raw = value.to_bytes(32, "big")
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _ec_signing_key(*, kid: str) -> tuple[str, dict[str, object]]:
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_numbers = private_key.public_key().public_numbers()
    private_pem = private_key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode("ascii")
    return private_pem, {
        "alg": "ES256",
        "crv": "P-256",
        "key_ops": ["verify"],
        "kid": kid,
        "kty": "EC",
        "use": "sig",
        "x": _b64url_uint(public_numbers.x),
        "y": _b64url_uint(public_numbers.y),
    }


def _es256_token(
    *,
    private_pem: str,
    kid: str,
    issuer: str,
    sub: str,
    audience: str = "authenticated",
) -> str:
    return jwt.encode(
        {
            "sub": sub,
            "email": f"{sub}@example.com",
            "role": "authenticated",
            "aud": audience,
            "iss": issuer,
            "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
        },
        private_pem,
        algorithm="ES256",
        headers={"kid": kid, "alg": "ES256"},
    )


def _configure_supabase_jwks(monkeypatch, *, kid: str = "test-kid"):
    issuer = "https://example.supabase.co/auth/v1"
    jwks_url = "https://example.supabase.co/auth/v1/.well-known/jwks.json"
    private_pem, key = _ec_signing_key(kid=kid)
    supabase_jwt._JWKS_CACHE.update({"url": None, "expires_at": 0.0, "keys": {}})
    monkeypatch.setattr(auth.settings, "jwt_secret", "local-secret", raising=False)
    monkeypatch.setattr(auth.settings, "jwt_algorithm", "HS256", raising=False)
    monkeypatch.setattr(auth, "SUPABASE_JWKS_URL", jwks_url, raising=False)
    monkeypatch.setattr(auth, "SUPABASE_JWT_ISSUER", issuer, raising=False)
    monkeypatch.setattr(auth, "SUPABASE_JWT_AUDIENCE", "authenticated", raising=False)
    monkeypatch.setattr(
        supabase_jwt,
        "_fetch_jwks",
        lambda url: {"keys": [key]},
        raising=False,
    )
    return private_pem, issuer, kid


def test_decode_access_token_accepts_supabase_es256_jwks_token(monkeypatch):
    private_pem, issuer, kid = _configure_supabase_jwks(monkeypatch)

    payload, source = auth._decode_access_token(
        _es256_token(
            private_pem=private_pem,
            kid=kid,
            issuer=issuer,
            sub="11111111-1111-4111-8111-111111111111",
        )
    )

    assert source == "supabase"
    assert payload["sub"] == "11111111-1111-4111-8111-111111111111"


def test_decode_access_token_rejects_supabase_token_with_unknown_kid(monkeypatch):
    private_pem, issuer, _ = _configure_supabase_jwks(monkeypatch, kid="known-kid")

    with pytest.raises(JWTError):
        auth._decode_access_token(
            _es256_token(
                private_pem=private_pem,
                kid="unknown-kid",
                issuer=issuer,
                sub="22222222-2222-4222-8222-222222222222",
            )
        )


def test_decode_access_token_enforces_supabase_audience(monkeypatch):
    private_pem, issuer, kid = _configure_supabase_jwks(monkeypatch)

    with pytest.raises(JWTError):
        auth._decode_access_token(
            _es256_token(
                private_pem=private_pem,
                kid=kid,
                issuer=issuer,
                audience="wrong-audience",
                sub="22222222-2222-4222-8222-222222222222",
            )
        )


def test_decode_access_token_rejects_supabase_hs256_tokens(monkeypatch):
    monkeypatch.setattr(auth.settings, "jwt_secret", "local-secret", raising=False)
    monkeypatch.setattr(auth.settings, "jwt_algorithm", "HS256", raising=False)

    with pytest.raises(JWTError):
        auth._decode_access_token(
            jwt.encode(
                {
                    "sub": "22222222-2222-4222-8222-222222222222",
                    "email": "user@example.com",
                    "role": "authenticated",
                    "aud": "authenticated",
                    "iss": "https://example.supabase.co/auth/v1",
                    "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
                },
                "supabase-secret",
                algorithm="HS256",
            )
        )


def test_decode_access_token_rejects_wrong_supabase_issuer(monkeypatch):
    private_pem, issuer, kid = _configure_supabase_jwks(monkeypatch)

    with pytest.raises(JWTError):
        auth._decode_access_token(
            _es256_token(
                private_pem=private_pem,
                kid=kid,
                issuer=f"{issuer}/wrong",
                sub="22222222-2222-4222-8222-222222222222",
            )
        )


def test_decode_access_token_prefers_local_jwt_secret_for_local_tokens(monkeypatch):
    monkeypatch.setattr(auth.settings, "jwt_secret", "local-secret", raising=False)
    monkeypatch.setattr(auth.settings, "jwt_algorithm", "HS256", raising=False)

    token = jwt.encode(
        {
            "sub": "33333333-3333-4333-8333-333333333333",
            "token_type": "access",
            "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
        },
        "local-secret",
        algorithm="HS256",
    )

    payload, source = auth._decode_access_token(token)

    assert source == "local"
    assert payload["sub"] == "33333333-3333-4333-8333-333333333333"
