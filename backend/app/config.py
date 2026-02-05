from urllib.parse import urlparse

from pydantic import AliasChoices, AnyUrl, Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _cors_origin_from_url(value: str | None) -> str | None:
    if not value:
        return None
    raw = value.strip()
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


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=(".env", "../.env"), extra="ignore")

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
    supabase_db_url: AnyUrl | None = None
    database_url: AnyUrl | None = None
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
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ]
    cors_allow_origin_regex: str | None = r"http://(localhost|127\.0\.0\.1)(:\d+)?"
    lesson_media_max_bytes: int = 2 * 1024 * 1024 * 1024
    media_upload_max_image_bytes: int = 25 * 1024 * 1024
    media_upload_max_audio_bytes: int = 5 * 1024 * 1024 * 1024
    media_upload_max_video_bytes: int = 5 * 1024 * 1024 * 1024
    media_playback_url_ttl_seconds: int = 3600
    media_signing_secret: str | None = None
    media_signing_ttl_seconds: int = 600
    media_allow_legacy_media: bool = True
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

    @model_validator(mode="after")
    def _populate_database_url(self):
        if self.database_url is None:
            if self.supabase_db_url is None:
                raise ValueError("DATABASE_URL or SUPABASE_DB_URL is required")
            self.database_url = self.supabase_db_url

        frontend_origin = _cors_origin_from_url(self.frontend_base_url)
        if frontend_origin:
            existing = {origin.strip().lower() for origin in self.cors_allow_origins if origin}
            if frontend_origin.strip().lower() not in existing:
                self.cors_allow_origins.append(frontend_origin)

        return self

    @field_validator("cors_allow_origins", mode="before")
    @classmethod
    def _split_origins(cls, value):
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


settings = Settings()
