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
