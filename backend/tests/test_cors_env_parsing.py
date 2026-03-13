from app.config import Settings


def _settings(**overrides) -> Settings:
    return Settings(database_url="postgresql://localhost:5432/aveli_test", **overrides)


def test_cors_defaults_include_explicit_prod_and_dev_origins():
    settings = _settings()

    assert settings.cors_allow_origins == [
        "https://app.aveli.app",
        "https://aveli.fly.dev",
        "http://localhost:3000",
        "http://localhost:5173",
    ]
    assert settings.cors_allow_origin_regex == r"http://localhost(:\d+)?"


def test_cors_parses_json_array():
    settings = _settings(
        cors_allow_origins='["https://app.aveli.app/", "http://localhost:3000"]'
    )

    assert settings.cors_allow_origins == [
        "https://app.aveli.app",
        "http://localhost:3000",
    ]


def test_cors_parses_csv_and_deduplicates():
    settings = _settings(
        cors_allow_origins="https://app.aveli.app/, http://localhost:3000, https://app.aveli.app"
    )

    assert settings.cors_allow_origins == [
        "https://app.aveli.app",
        "http://localhost:3000",
    ]
