import re

import pytest

from app.config import Settings


def _settings(**overrides) -> Settings:
    return Settings(
        _env_file=None,
        database_host="localhost",
        database_port=5432,
        database_name="aveli_test",
        database_user="postgres",
        database_password="postgres",
        **overrides,
    )


def test_cors_defaults_include_prod_origin_and_localhost_regex():
    settings = _settings()

    assert settings.cors_allow_origins == ["https://aveli.app"]
    assert settings.cors_allow_origin_regex == r"http://(localhost|127\.0\.0\.1)(:\d+)?"
    assert re.fullmatch(settings.cors_allow_origin_regex, "http://localhost:51829")
    assert re.fullmatch(settings.cors_allow_origin_regex, "http://127.0.0.1:51829")


def test_cors_includes_configured_frontend_origin_when_regex_does_not_cover_it():
    settings = _settings(frontend_base_url="https://app.aveli.app/dashboard")

    assert settings.cors_allow_origins == [
        "https://aveli.app",
        "https://app.aveli.app",
    ]


def test_cors_parses_json_array():
    settings = _settings(
        cors_allow_origins='["https://aveli.app/", "http://localhost:3000"]'
    )

    assert settings.cors_allow_origins == [
        "https://aveli.app",
        "http://localhost:3000",
    ]


def test_cors_parses_csv_and_deduplicates():
    settings = _settings(
        cors_allow_origins="https://aveli.app/, http://localhost:3000, https://aveli.app"
    )

    assert settings.cors_allow_origins == [
        "https://aveli.app",
        "http://localhost:3000",
    ]


def test_cors_reads_allowed_origins_from_env(monkeypatch):
    monkeypatch.setenv("ALLOWED_ORIGINS", "https://aveli.app, https://preview.aveli.app")

    settings = _settings()

    assert settings.cors_allow_origins == [
        "https://aveli.app",
        "https://preview.aveli.app",
    ]


def test_cors_rejects_wildcard_origin_entries():
    with pytest.raises(ValueError, match="Wildcard CORS origins are not allowed"):
        _settings(cors_allow_origins="*")
