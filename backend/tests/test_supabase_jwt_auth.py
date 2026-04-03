from __future__ import annotations

from datetime import datetime, timedelta, timezone

from jose import jwt

from app import auth


def _hs256_token(*, secret: str, issuer: str, sub: str) -> str:
    return jwt.encode(
        {
            "sub": sub,
            "email": f"{sub}@example.com",
            "role": "authenticated",
            "iss": issuer,
            "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
        },
        secret,
        algorithm="HS256",
    )


def test_decode_access_token_accepts_current_supabase_jwt_secret(monkeypatch):
    issuer = "https://example.supabase.co/auth/v1"
    monkeypatch.setattr(auth.settings, "jwt_secret", "local-secret", raising=False)
    monkeypatch.setattr(auth.settings, "supabase_url", None, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwks_url", None, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwt_issuer", issuer, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwt_secret", "current-secret", raising=False)
    monkeypatch.setattr(
        auth.settings,
        "supabase_jwt_secret_legacy",
        "legacy-secret",
        raising=False,
    )

    payload, source = auth._decode_access_token(
        _hs256_token(
            secret="current-secret",
            issuer=issuer,
            sub="11111111-1111-4111-8111-111111111111",
        )
    )

    assert source == "supabase"
    assert payload["sub"] == "11111111-1111-4111-8111-111111111111"


def test_decode_access_token_accepts_legacy_supabase_jwt_secret(monkeypatch):
    issuer = "https://example.supabase.co/auth/v1"
    monkeypatch.setattr(auth.settings, "jwt_secret", "local-secret", raising=False)
    monkeypatch.setattr(auth.settings, "supabase_url", None, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwks_url", None, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwt_issuer", issuer, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwt_secret", "current-secret", raising=False)
    monkeypatch.setattr(
        auth.settings,
        "supabase_jwt_secret_legacy",
        "legacy-secret",
        raising=False,
    )

    payload, source = auth._decode_access_token(
        _hs256_token(
            secret="legacy-secret",
            issuer=issuer,
            sub="22222222-2222-4222-8222-222222222222",
        )
    )

    assert source == "supabase"
    assert payload["sub"] == "22222222-2222-4222-8222-222222222222"


def test_decode_access_token_prefers_local_jwt_secret_for_local_tokens(monkeypatch):
    monkeypatch.setattr(auth.settings, "jwt_secret", "local-secret", raising=False)
    monkeypatch.setattr(auth.settings, "jwt_algorithm", "HS256", raising=False)
    monkeypatch.setattr(auth.settings, "supabase_url", None, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwks_url", None, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwt_issuer", None, raising=False)
    monkeypatch.setattr(auth.settings, "supabase_jwt_secret", "current-secret", raising=False)
    monkeypatch.setattr(
        auth.settings,
        "supabase_jwt_secret_legacy",
        "legacy-secret",
        raising=False,
    )

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
