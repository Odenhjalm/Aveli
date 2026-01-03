from pydantic import AliasChoices, AnyUrl, Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=(".env", "../.env"), extra="ignore")

    supabase_url: AnyUrl
    supabase_anon_key: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "SUPABASE_ANON_KEY",
            "SUPABASE_PUBLISHABLE_API_KEY",
            "SUPABASE_PUBLIC_API_KEY",
        ),
    )
    supabase_service_role_key: str = Field(
        validation_alias=AliasChoices(
            "SUPABASE_SERVICE_ROLE_KEY",
            "SUPABASE_SECRET_API_KEY",
        ),
    )
    supabase_db_url: AnyUrl
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
        validation_alias=AliasChoices("CHECKOUT_SUCCESS_URL", "STRIPE_CHECKOUT_SUCCESS_URL"),
    )
    checkout_cancel_url: str | None = Field(
        default=None,
        validation_alias=AliasChoices("CHECKOUT_CANCEL_URL", "STRIPE_CHECKOUT_CANCEL_URL"),
    )
    stripe_secret_key: str | None = None
    stripe_webhook_secret: str | None = None
    stripe_billing_webhook_secret: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "STRIPE_BILLING_WEBHOOK_SECRET",
            "STRIPE_BILLING_WEBHOOK_SECTRET",
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
    stripe_test_price_monthly: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "STRIPE_TEST_PRICE_MONTHLY",
            "STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY",
        ),
    )
    stripe_test_price_yearly: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "STRIPE_TEST_PRICE_YEARLY",
            "STRIPE_TEST_MEMBERSHIP_PRICE_YEARLY",
            "STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY",
        ),
    )
    stripe_test_membership_product_id: str | None = Field(
        default=None,
        validation_alias=AliasChoices("STRIPE_TEST_MEMBERSHIP_PRODUCT_ID"),
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
    media_signing_secret: str | None = None
    media_signing_ttl_seconds: int = 600
    media_allow_legacy_media: bool = True
    media_public_cache_seconds: int = 3600

    @model_validator(mode="after")
    def _populate_database_url(self):
        if self.database_url is None:
            self.database_url = self.supabase_db_url
        return self

    @field_validator("cors_allow_origins", mode="before")
    @classmethod
    def _split_origins(cls, value):
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


settings = Settings()
