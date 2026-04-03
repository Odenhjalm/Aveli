import json
import os
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlparse

from pydantic import AliasChoices, AnyUrl, Field, TypeAdapter, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


_PRODUCTION_ENVS = {"prod", "production", "live"}
_LOCAL_DB_HOSTS = {"localhost", "127.0.0.1", "::1", "db", "host.docker.internal"}
_ALLOWED_MCP_MODES = {"local", "production"}
_BACKEND_DIR = Path(__file__).resolve().parents[1]
_SETTINGS_ENV_FILES = (
    str(_BACKEND_DIR / ".env"),
    str(_BACKEND_DIR / ".env.local"),
)
_ANY_URL_ADAPTER = TypeAdapter(AnyUrl)


def _truthy_env(key: str) -> bool:
    return (os.environ.get(key) or "").strip().lower() in {"1", "true", "yes", "y", "on"}


def _app_env_lower() -> str:
    raw = os.environ.get("APP_ENV") or os.environ.get("ENVIRONMENT") or os.environ.get("ENV") or ""
    return raw.strip().lower()


def _is_cloud_runtime() -> bool:
    return bool(
        os.environ.get("FLY_APP_NAME")
        or os.environ.get("K_SERVICE")
        or os.environ.get("AWS_EXECUTION_ENV")
        or os.environ.get("DYNO")
    )


def _db_target(db_url: str) -> str:
    parsed = urlparse(db_url)
    host = parsed.hostname or "unknown"
    port = f":{parsed.port}" if parsed.port else ""
    dbname = (parsed.path or "").lstrip("/") or "postgres"
    return f"{host}{port}/{dbname}"


def _looks_like_supabase_host(hostname: str) -> bool:
    host = hostname.strip().lower()
    if not host:
        return False
    if host.endswith(".supabase.co") or host.endswith(".supabase.com"):
        return True
    return "supabase" in host


def _normalize_cors_origin(value: str | None) -> str | None:
    if not value:
        return None
    raw = value.strip().strip('"').strip("'")
    if not raw:
        return None
    parsed = urlparse(raw)
    scheme = (parsed.scheme or "").lower().strip()
    if scheme not in {"http", "https"}:
        return None
    hostname = (parsed.hostname or "").strip()
    if not hostname:
        return None
    port = parsed.port
    if port and not ((scheme == "http" and port == 80) or (scheme == "https" and port == 443)):
        return f"{scheme}://{hostname}:{port}"
    return f"{scheme}://{hostname}"


def _normalize_db_component(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _format_db_host(host: str) -> str:
    if ":" in host and not host.startswith("["):
        return f"[{host}]"
    return host


def _build_database_url(
    *,
    host: str,
    port: int,
    name: str,
    user: str,
    password: str,
) -> str:
    return (
        f"postgresql://{quote(user, safe='')}:{quote(password, safe='')}"
        f"@{_format_db_host(host)}:{port}/{quote(name, safe='')}"
    )


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_SETTINGS_ENV_FILES,
        env_ignore_empty=True,
        extra="ignore",
    )

    supabase_url: AnyUrl | None = None
    supabase_anon_key: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "SUPABASE_ANON_KEY",
            "SUPABASE_PUBLISHABLE_API_KEY",
            "SUPABASE_PUBLIC_API_KEY",
        ),
    )
    supabase_service_role_key: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "SUPABASE_SERVICE_ROLE_KEY",
            "SUPABASE_SECRET_API_KEY",
        ),
    )
    supabase_jwks_url: AnyUrl | None = Field(
        default=None, validation_alias=AliasChoices("SUPABASE_JWKS_URL")
    )
    supabase_jwt_issuer: str | None = Field(
        default=None, validation_alias=AliasChoices("SUPABASE_JWT_ISSUER")
    )
    supabase_jwt_secret: str | None = Field(
        default=None, validation_alias=AliasChoices("SUPABASE_JWT_SECRET")
    )
    supabase_jwt_secret_legacy: str | None = Field(
        default=None, validation_alias=AliasChoices("SUPABASE_JWT_SECRET_LEGACY")
    )
    supabase_db_url: AnyUrl | None = None
    database_url: AnyUrl | None = None
    database_host: str | None = Field(default=None, validation_alias="DATABASE_HOST")
    database_port: int | None = Field(default=None, validation_alias="DATABASE_PORT")
    database_name: str | None = Field(default=None, validation_alias="DATABASE_NAME")
    database_user: str | None = Field(default=None, validation_alias="DATABASE_USER")
    database_password: str | None = Field(default=None, validation_alias="DATABASE_PASSWORD")
    mcp_mode: str = Field(default="local", validation_alias="MCP_MODE")
    mcp_production_database_url: AnyUrl | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "MCP_PRODUCTION_DATABASE_URL",
            "MCP_PRODUCTION_SUPABASE_DB_URL",
        ),
    )
    jwt_secret: str = "change-me"
    jwt_algorithm: str = "HS256"
    jwt_expires_minutes: int = 15
    jwt_refresh_expires_minutes: int = 60 * 24
    media_root: str = "media"
    frontend_base_url: str | None = "http://localhost:3000"
    stripe_checkout_base: str | None = None
    stripe_checkout_ui_mode: str | None = "custom"
    checkout_success_url: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "CHECKOUT_SUCCESS_URL",
            "STRIPE_CHECKOUT_SUCCESS_URL",
            "STRIPE_RETURN_URL",
        ),
    )
    checkout_cancel_url: str | None = Field(
        default=None,
        validation_alias=AliasChoices("CHECKOUT_CANCEL_URL", "STRIPE_CHECKOUT_CANCEL_URL"),
    )
    stripe_secret_key: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "STRIPE_SECRET_KEY",
            "STRIPE_TEST_SECRET_KEY",
            "STRIPE_LIVE_SECRET_KEY",
        ),
    )
    stripe_test_secret_key: str | None = Field(
        default=None, validation_alias="STRIPE_TEST_SECRET_KEY"
    )
    stripe_live_secret_key: str | None = Field(
        default=None, validation_alias="STRIPE_LIVE_SECRET_KEY"
    )
    stripe_webhook_secret: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "STRIPE_WEBHOOK_SECRET",
            "STRIPE_TEST_WEBHOOK_SECRET",
            "STRIPE_LIVE_WEBHOOK_SECRET",
        ),
    )
    stripe_billing_webhook_secret: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "STRIPE_BILLING_WEBHOOK_SECRET",
            "STRIPE_BILLING_WEBHOOK_SECTRET",
            "STRIPE_TEST_WEBHOOK_BILLING_SECRET",
            "STRIPE_LIVE_BILLING_WEBHOOK_SECRET",
        ),
    )
    stripe_price_monthly: str | None = Field(
        default=None,
        validation_alias=AliasChoices("STRIPE_PRICE_MONTHLY", "AVELI_PRICE_MONTHLY"),
    )
    stripe_price_yearly: str | None = Field(
        default=None,
        validation_alias=AliasChoices("STRIPE_PRICE_YEARLY", "AVELI_PRICE_YEARLY"),
    )
    stripe_membership_product_id: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "STRIPE_MEMBERSHIP_PRODUCT_ID",
            "AVELI_MEMBERSHIP_PRODUCT_ID",
        ),
    )
    stripe_test_publishable_key: str | None = Field(
        default=None, validation_alias="STRIPE_TEST_PUBLISHABLE_KEY"
    )
    stripe_test_webhook_secret: str | None = Field(
        default=None, validation_alias="STRIPE_TEST_WEBHOOK_SECRET"
    )
    stripe_test_webhook_billing_secret: str | None = Field(
        default=None, validation_alias="STRIPE_TEST_WEBHOOK_BILLING_SECRET"
    )
    stripe_test_membership_product_id: str | None = Field(
        default=None, validation_alias="STRIPE_TEST_MEMBERSHIP_PRODUCT_ID"
    )
    stripe_test_membership_price_monthly: str | None = Field(
        default=None, validation_alias="STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY"
    )
    stripe_test_membership_price_id_yearly: str | None = Field(
        default=None, validation_alias="STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY"
    )
    stripe_connect_client_id: str | None = None
    stripe_connect_refresh_url: str | None = None
    stripe_connect_return_url: str | None = None
    livekit_api_key: str | None = None
    livekit_api_secret: str | None = None
    livekit_ws_url: str | None = "wss://lk.wisdom.dev"
    livekit_api_url: str | None = None
    livekit_webhook_secret: str | None = None
    cors_allow_origins: list[str] = [
        "https://app.aveli.app",
        "https://aveli.fly.dev",
        "http://localhost:3000",
        "http://localhost:5173",
    ]
    cors_allow_origin_regex: str | None = r"http://localhost(:\d+)?"
    lesson_media_max_bytes: int = 2 * 1024 * 1024 * 1024
    media_upload_max_image_bytes: int = 25 * 1024 * 1024
    media_upload_max_audio_bytes: int = 5 * 1024 * 1024 * 1024
    media_upload_max_video_bytes: int = 5 * 1024 * 1024 * 1024
    media_playback_url_ttl_seconds: int = 3600
    media_signing_secret: str | None = None
    media_signing_ttl_seconds: int = 600
    media_public_cache_seconds: int = 3600
    media_source_bucket: str = "course-media"
    media_public_bucket: str = "public-media"
    media_transcode_enabled: bool = True
    media_transcode_poll_interval_seconds: int = 10
    media_transcode_batch_size: int = 3
    media_transcode_stale_lock_seconds: int = 1800
    media_transcode_max_attempts: int = 5
    media_transcode_max_retry_seconds: int = 300
    sentry_dsn: str | None = Field(
        default=None, validation_alias=AliasChoices("SENTRY_DSN", "BACKEND_SENTRY_DSN")
    )
    sentry_traces_sample_rate: float = Field(
        default=0.0,
        validation_alias=AliasChoices(
            "SENTRY_TRACES_SAMPLE_RATE",
            "BACKEND_SENTRY_TRACES_SAMPLE_RATE",
        ),
    )
    resend_api_key: str | None = Field(default=None, validation_alias="RESEND_API_KEY")
    email_from: str | None = Field(default=None, validation_alias="EMAIL_FROM")
    membership_expiry_warning_interval_seconds: int = 60 * 60 * 24
    enable_test_session_headers: bool = False
    logs_mcp_enabled: bool = Field(default_factory=lambda: not _is_cloud_runtime())
    media_control_plane_mcp_enabled: bool = Field(
        default_factory=lambda: not _is_cloud_runtime()
    )
    verification_mcp_enabled: bool = Field(
        default_factory=lambda: not _is_cloud_runtime()
    )
    domain_observability_mcp_enabled: bool = Field(
        default_factory=lambda: not _is_cloud_runtime()
    )

    @field_validator("mcp_mode", mode="before")
    @classmethod
    def _normalize_mcp_mode(cls, value: Any) -> str:
        normalized = str(value or "local").strip().lower()
        if normalized not in _ALLOWED_MCP_MODES:
            expected = ", ".join(sorted(_ALLOWED_MCP_MODES))
            raise ValueError(f"MCP_MODE must be one of: {expected}")
        return normalized

    @property
    def mcp_production_mode(self) -> bool:
        return self.mcp_mode == "production"

    @property
    def mcp_workers_enabled(self) -> bool:
        return not self.mcp_production_mode

    @property
    def supabase_jwt_secrets(self) -> tuple[str, ...]:
        secrets: list[str] = []
        seen: set[str] = set()
        for value in (self.supabase_jwt_secret, self.supabase_jwt_secret_legacy):
            normalized = _normalize_db_component(value)
            if normalized is None or normalized in seen:
                continue
            seen.add(normalized)
            secrets.append(normalized)
        return tuple(secrets)

    @property
    def mcp_environment(self) -> dict[str, Any]:
        return {
            "mcp_mode": self.mcp_mode,
            "production_data": self.mcp_production_mode,
            "access_mode": "read_only",
        }

    @model_validator(mode="after")
    def _populate_database_url(self):
        if self.mcp_production_mode:
            if self.mcp_production_database_url is None:
                raise ValueError(
                    "MCP_MODE=production requires "
                    "MCP_PRODUCTION_DATABASE_URL or MCP_PRODUCTION_SUPABASE_DB_URL"
                )
            self.database_url = self.mcp_production_database_url
        else:
            db_fields = {
                "DATABASE_HOST": _normalize_db_component(self.database_host),
                "DATABASE_PORT": self.database_port,
                "DATABASE_NAME": _normalize_db_component(self.database_name),
                "DATABASE_USER": _normalize_db_component(self.database_user),
                "DATABASE_PASSWORD": _normalize_db_component(self.database_password),
            }
            missing = [key for key, value in db_fields.items() if value in (None, "")]
            if missing:
                raise ValueError(
                    "Local database configuration requires explicit "
                    + ", ".join(missing)
                )
            derived_url = _build_database_url(
                host=str(db_fields["DATABASE_HOST"]),
                port=int(db_fields["DATABASE_PORT"]),
                name=str(db_fields["DATABASE_NAME"]),
                user=str(db_fields["DATABASE_USER"]),
                password=str(db_fields["DATABASE_PASSWORD"]),
            )
            self.database_url = _ANY_URL_ADAPTER.validate_python(derived_url)

        db_url = self.database_url.unicode_string()
        parsed = urlparse(db_url)
        hostname = (parsed.hostname or "").strip().lower()

        if hostname and hostname not in _LOCAL_DB_HOSTS and _looks_like_supabase_host(hostname):
            allow_remote = _truthy_env("AVELI_ALLOW_REMOTE_DB") or self.mcp_production_mode
            app_env = _app_env_lower()
            is_prod_env = app_env in _PRODUCTION_ENVS
            if not allow_remote and not (is_prod_env and _is_cloud_runtime()):
                target = _db_target(db_url)
                raise ValueError(
                    "Refusing to start with remote Supabase database outside of production runtime "
                    f"(APP_ENV={app_env or 'unset'}, target={target}). "
                    "Point DATABASE_HOST/DATABASE_PORT/DATABASE_NAME/DATABASE_USER/"
                    "DATABASE_PASSWORD to your local Postgres clone, or set "
                    "AVELI_ALLOW_REMOTE_DB=1 to override."
                )

        return self

    @field_validator("cors_allow_origins", mode="before")
    @classmethod
    def _split_origins(cls, value):
        if isinstance(value, str):
            raw = value.strip()
            if not raw:
                return []
            if raw.startswith("["):
                try:
                    value = json.loads(raw)
                except json.JSONDecodeError as exc:
                    raise ValueError("cors_allow_origins JSON must be a list of strings") from exc
            else:
                value = raw.split(",")

        if isinstance(value, (list, tuple, set)):
            origins: list[str] = []
            seen: set[str] = set()
            for origin in value:
                if not isinstance(origin, str):
                    raise ValueError("cors_allow_origins entries must be strings")
                normalized = _normalize_cors_origin(origin)
                if not normalized:
                    continue
                key = normalized.lower()
                if key in seen:
                    continue
                seen.add(key)
                origins.append(normalized)
            return origins
        return value


settings = Settings()
