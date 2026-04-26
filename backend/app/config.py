import json
import os
import re
from pathlib import Path
from typing import Annotated, Any
from urllib.parse import quote, urlparse

from pydantic import AliasChoices, AnyUrl, Field, TypeAdapter, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


_PRODUCTION_ENVS = {"prod", "production", "live"}
_LOCAL_DB_HOSTS = {"localhost", "127.0.0.1", "::1", "db", "host.docker.internal"}
_ALLOWED_MCP_MODES = {"local", "production"}
_CLOUD_RUNTIME_ENV_KEYS = ("FLY_APP_NAME", "K_SERVICE", "AWS_EXECUTION_ENV", "DYNO")
_BACKEND_DIR = Path(__file__).resolve().parents[1]
_SETTINGS_ENV_FILES = (
    str(_BACKEND_DIR / ".env"),
    str(_BACKEND_DIR / ".env.local"),
)
_ANY_URL_ADAPTER = TypeAdapter(AnyUrl)
_DEFAULT_CORS_ALLOW_ORIGINS = ("https://aveli.app",)
_DEFAULT_CORS_ALLOW_ORIGIN_REGEX = r"http://(localhost|127\.0\.0\.1)(:\d+)?"
_OPEN_CORS_ORIGIN_REGEXES = frozenset({"*", ".*", "^.*$", ".+", "^.+$"})


def _truthy_env(key: str) -> bool:
    return (os.environ.get(key) or "").strip().lower() in {"1", "true", "yes", "y", "on"}


def _app_env_lower() -> str:
    raw = os.environ.get("APP_ENV") or os.environ.get("ENVIRONMENT") or os.environ.get("ENV") or ""
    return raw.strip().lower()


def _explicit_local_runtime() -> bool:
    mcp_mode = (os.environ.get("MCP_MODE") or "").strip().lower()
    return _app_env_lower() == "local" and mcp_mode == "local"


def _is_cloud_runtime() -> bool:
    if _explicit_local_runtime():
        return False
    if _app_env_lower() in _PRODUCTION_ENVS:
        return True
    return any(os.environ.get(key) for key in _CLOUD_RUNTIME_ENV_KEYS)


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


def _parse_cors_origins(value: Any) -> Any:
    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return []
        if raw.startswith("["):
            try:
                value = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise ValueError("ALLOWED_ORIGINS JSON must be a list of strings") from exc
        else:
            value = raw.split(",")

    if isinstance(value, (list, tuple, set)):
        origins: list[str] = []
        seen: set[str] = set()
        for origin in value:
            if not isinstance(origin, str):
                raise ValueError("ALLOWED_ORIGINS entries must be strings")
            raw_origin = origin.strip()
            if not raw_origin:
                continue
            if "*" in raw_origin:
                raise ValueError(
                    "Wildcard CORS origins are not allowed. "
                    "Use ALLOWED_ORIGIN_REGEX for localhost port matching."
                )
            normalized = _normalize_cors_origin(raw_origin)
            if not normalized:
                raise ValueError(f"Invalid CORS origin: {origin!r}")
            key = normalized.lower()
            if key in seen:
                continue
            seen.add(key)
            origins.append(normalized)
        return origins
    return value


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
        populate_by_name=True,
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
    netlify_auth_token: str | None = Field(default=None, validation_alias="NETLIFY_AUTH_TOKEN")
    netlify_site_id: str | None = Field(
        default=None,
        validation_alias=AliasChoices("NETLIFY_SITE_ID", "SITE_ID"),
    )
    netlify_api_base_url: str = Field(
        default="https://api.netlify.com/api/v1",
        validation_alias="NETLIFY_API_BASE_URL",
    )
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
    cors_allow_origins: Annotated[list[str], NoDecode] = Field(
        default_factory=lambda: list(_DEFAULT_CORS_ALLOW_ORIGINS),
        validation_alias=AliasChoices("ALLOWED_ORIGINS", "CORS_ALLOW_ORIGINS"),
    )
    cors_allow_origin_regex: str | None = Field(
        default=_DEFAULT_CORS_ALLOW_ORIGIN_REGEX,
        validation_alias=AliasChoices("ALLOWED_ORIGIN_REGEX", "CORS_ALLOW_ORIGIN_REGEX"),
    )
    lesson_media_max_bytes: int = 2 * 1024 * 1024 * 1024
    media_upload_max_image_bytes: int = 25 * 1024 * 1024
    media_upload_max_audio_bytes: int = 5 * 1024 * 1024 * 1024
    media_upload_max_video_bytes: int = 5 * 1024 * 1024 * 1024
    media_playback_url_ttl_seconds: int = 3600
    media_signing_secret: str | None = None
    media_signing_ttl_seconds: int = 600
    media_public_cache_seconds: int = 3600
    media_source_bucket: str = "course-media"
    media_profile_bucket: str = "profile-media"
    media_public_bucket: str = "public-media"
    media_transcode_enabled: bool = True
    media_transcode_poll_interval_seconds: int = 10
    media_transcode_batch_size: int = 3
    media_transcode_stale_lock_seconds: int = 1800
    media_transcode_max_attempts: int = 5
    media_transcode_max_retry_seconds: int = 300
    course_drip_worker_interval_seconds: int = 60 * 60
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
    notification_dispatcher_interval_seconds: int = 30
    firebase_project_id: str | None = Field(
        default=None,
        validation_alias=AliasChoices("FIREBASE_PROJECT_ID", "FCM_PROJECT_ID"),
    )
    firebase_service_account_json: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "FIREBASE_SERVICE_ACCOUNT_JSON",
            "FCM_SERVICE_ACCOUNT_JSON",
        ),
    )
    firebase_service_account_file: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "FIREBASE_SERVICE_ACCOUNT_FILE",
            "GOOGLE_APPLICATION_CREDENTIALS",
        ),
    )
    fcm_api_base_url: str = Field(
        default="https://fcm.googleapis.com",
        validation_alias="FCM_API_BASE_URL",
    )
    fcm_oauth_token_url: str = Field(
        default="https://oauth2.googleapis.com/token",
        validation_alias="FCM_OAUTH_TOKEN_URL",
    )
    fcm_request_timeout_seconds: float = Field(
        default=10.0,
        validation_alias="FCM_REQUEST_TIMEOUT_SECONDS",
    )
    # Required for deterministic Windows local runtime verification without replay:
    # start workers in read-only standby mode so backend health surfaces stay verifiable.
    runtime_verify_no_write: bool = Field(
        default=False,
        validation_alias="AVELI_RUNTIME_VERIFY_NO_WRITE",
    )
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
    supabase_observability_mcp_enabled: bool = Field(
        default_factory=lambda: not _is_cloud_runtime()
    )
    stripe_observability_mcp_enabled: bool = Field(
        default_factory=lambda: not _is_cloud_runtime()
    )
    netlify_observability_mcp_enabled: bool = Field(
        default_factory=lambda: not _is_cloud_runtime()
    )
    dev_operator_observability_mcp_enabled: bool = Field(
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
    def cloud_runtime(self) -> bool:
        return _is_cloud_runtime()

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
        is_cloud_runtime = _is_cloud_runtime()

        if is_cloud_runtime:
            if self.database_url is None:
                raise ValueError("Cloud runtime requires DATABASE_URL")
        elif self.mcp_production_mode:
            if self.mcp_production_database_url is None:
                raise ValueError(
                    "MCP_MODE=production requires "
                    "MCP_PRODUCTION_DATABASE_URL or MCP_PRODUCTION_SUPABASE_DB_URL"
                )
            self.database_url = self.mcp_production_database_url
        else:
            explicit_database_url = _normalize_db_component(
                os.environ.get("DATABASE_URL")
            )
            if explicit_database_url:
                explicit_host = (
                    urlparse(explicit_database_url).hostname or ""
                ).strip().lower()
                if explicit_host not in _LOCAL_DB_HOSTS:
                    target = _db_target(explicit_database_url)
                    raise ValueError(
                        "Refusing to start local runtime with non-local database target "
                        f"(target={target}). Point DATABASE_URL to the local "
                        "Postgres clone or use MCP_MODE=production with an explicit "
                        "production database URL."
                    )
                self.database_url = _ANY_URL_ADAPTER.validate_python(
                    explicit_database_url
                )
            else:
                db_fields = {
                    "DATABASE_HOST": _normalize_db_component(self.database_host),
                    "DATABASE_PORT": self.database_port,
                    "DATABASE_NAME": _normalize_db_component(self.database_name),
                    "DATABASE_USER": _normalize_db_component(self.database_user),
                    "DATABASE_PASSWORD": _normalize_db_component(
                        self.database_password
                    ),
                }
                missing = [
                    key for key, value in db_fields.items() if value in (None, "")
                ]
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

        if is_cloud_runtime and hostname in _LOCAL_DB_HOSTS:
            target = _db_target(db_url)
            raise ValueError(
                "Refusing to start cloud runtime with local database target "
                f"(target={target}). Set DATABASE_URL to the production database."
            )

        if hostname and hostname not in _LOCAL_DB_HOSTS and _looks_like_supabase_host(hostname):
            allow_remote = (
                _truthy_env("AVELI_ALLOW_REMOTE_DB")
                or self.mcp_production_mode
                or is_cloud_runtime
            )
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

    @model_validator(mode="after")
    def _include_frontend_cors_origin(self):
        frontend_origin = _normalize_cors_origin(self.frontend_base_url)
        if not frontend_origin:
            return self

        if frontend_origin in self.cors_allow_origins:
            return self

        pattern = self.cors_allow_origin_regex
        if pattern and re.fullmatch(pattern, frontend_origin):
            return self

        self.cors_allow_origins = [*self.cors_allow_origins, frontend_origin]
        return self

    @field_validator("cors_allow_origins", mode="before")
    @classmethod
    def _split_origins(cls, value):
        return _parse_cors_origins(value)

    @field_validator("cors_allow_origin_regex", mode="before")
    @classmethod
    def _normalize_origin_regex(cls, value: Any) -> str | None:
        if value is None:
            return None
        raw = str(value).strip().strip('"').strip("'")
        if not raw:
            return None
        if raw in _OPEN_CORS_ORIGIN_REGEXES:
            raise ValueError("Open CORS origin regex is not allowed")
        return raw


settings = Settings()
