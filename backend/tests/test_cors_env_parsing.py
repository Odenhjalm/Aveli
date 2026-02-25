import json

from app.main import get_allowed_origins


def test_cors_parses_json_array(monkeypatch):
    monkeypatch.setenv(
        "CORS_ALLOW_ORIGINS",
        json.dumps(["https://app.aveli.app", "http://localhost:3000"]),
    )
    origins = get_allowed_origins()
    assert "https://app.aveli.app" in origins
    assert "http://localhost:3000" in origins


def test_cors_parses_csv(monkeypatch):
    monkeypatch.setenv(
        "CORS_ALLOW_ORIGINS",
        "https://app.aveli.app,http://localhost:3000",
    )
    origins = get_allowed_origins()
    assert "https://app.aveli.app" in origins
    assert "http://localhost:3000" in origins


def test_cors_strips_trailing_slash(monkeypatch):
    monkeypatch.setenv(
        "CORS_ALLOW_ORIGINS",
        "https://app.aveli.app/",
    )
    origins = get_allowed_origins()
    assert origins == ["https://app.aveli.app"]
