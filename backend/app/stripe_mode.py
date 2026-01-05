from __future__ import annotations

import os
from dataclasses import dataclass
from enum import Enum
from typing import Any

import stripe
from starlette.concurrency import run_in_threadpool

from .config import settings
from .schemas.billing import SubscriptionInterval


class StripeMode(str, Enum):
    test = "test"
    live = "live"


class StripeConfigurationError(RuntimeError):
    """Raised when Stripe env/config cannot be resolved safely."""


@dataclass
class StripeContext:
    secret_key: str
    secret_source: str
    mode: StripeMode


@dataclass
class MembershipPriceConfig:
    price_id: str
    env_var: str
    product_id: str | None


def _resolve_secret_key() -> tuple[str, str]:
    env_candidates = [
        ((os.environ.get("STRIPE_SECRET_KEY") or "").strip(), "STRIPE_SECRET_KEY"),
        ((os.environ.get("STRIPE_TEST_SECRET_KEY") or "").strip(), "STRIPE_TEST_SECRET_KEY"),
        ((os.environ.get("STRIPE_LIVE_SECRET_KEY") or "").strip(), "STRIPE_LIVE_SECRET_KEY"),
    ]
    populated = [(value, name) for value, name in env_candidates if value]
    distinct_values = {value for value, _ in populated}
    if len(distinct_values) > 1:
        raise StripeConfigurationError(
            f"Conflicting Stripe secrets set: {', '.join(name for _, name in populated)}"
        )

    if populated:
        preferred = next((pair for pair in populated if pair[1] == "STRIPE_SECRET_KEY"), None)
        return preferred or populated[0]

    if settings.stripe_secret_key:
        return settings.stripe_secret_key, "STRIPE_SECRET_KEY"
    if settings.stripe_test_secret_key:
        return settings.stripe_test_secret_key, "STRIPE_TEST_SECRET_KEY"
    if settings.stripe_live_secret_key:
        return settings.stripe_live_secret_key, "STRIPE_LIVE_SECRET_KEY"

    raise StripeConfigurationError("Stripe secret key is missing (set STRIPE_SECRET_KEY)")


def resolve_stripe_context() -> StripeContext:
    secret_key, secret_source = _resolve_secret_key()
    if secret_key.startswith("sk_test_"):
        mode = StripeMode.test
    elif secret_key.startswith("sk_live_"):
        mode = StripeMode.live
    else:
        raise StripeConfigurationError(f"{secret_source} must start with sk_test_ or sk_live_")
    return StripeContext(secret_key=secret_key, secret_source=secret_source, mode=mode)


def resolve_membership_price(
    interval: SubscriptionInterval, context: StripeContext
) -> MembershipPriceConfig:
    if context.mode is StripeMode.test:
        product_id = settings.stripe_test_membership_product_id
        if not product_id:
            raise StripeConfigurationError(
                "STRIPE_TEST_MEMBERSHIP_PRODUCT_ID missing for Stripe test mode"
            )
        if interval is SubscriptionInterval.month:
            price_id = settings.stripe_test_membership_price_monthly
            env_var = "STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY"
        elif interval is SubscriptionInterval.year:
            price_id = settings.stripe_test_membership_price_id_yearly
            env_var = "STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY"
        else:  # pragma: no cover - defensive
            raise StripeConfigurationError(f"Unsupported subscription interval: {interval}")
        if not price_id:
            raise StripeConfigurationError(f"{env_var} missing for Stripe test mode")
        return MembershipPriceConfig(price_id=price_id, env_var=env_var, product_id=product_id)

    if interval is SubscriptionInterval.month:
        price_id = settings.stripe_price_monthly
        env_var = "AVELI_PRICE_MONTHLY"
    elif interval is SubscriptionInterval.year:
        price_id = settings.stripe_price_yearly
        env_var = "AVELI_PRICE_YEARLY"
    else:  # pragma: no cover - defensive
        raise StripeConfigurationError(f"Unsupported subscription interval: {interval}")

    if not price_id:
        raise StripeConfigurationError(f"{env_var} missing for Stripe live mode")

    return MembershipPriceConfig(
        price_id=price_id,
        env_var=env_var,
        product_id=settings.stripe_membership_product_id,
    )


def resolve_webhook_secret(kind: str, context: StripeContext) -> tuple[str, str]:
    if kind == "billing":
        if context.mode is StripeMode.test:
            secret = settings.stripe_test_webhook_billing_secret
            env_var = "STRIPE_TEST_WEBHOOK_BILLING_SECRET"
        else:
            secret = settings.stripe_billing_webhook_secret or settings.stripe_webhook_secret
            env_var = "STRIPE_BILLING_WEBHOOK_SECRET" if settings.stripe_billing_webhook_secret else "STRIPE_WEBHOOK_SECRET"
    else:
        if context.mode is StripeMode.test:
            secret = settings.stripe_test_webhook_secret
            env_var = "STRIPE_TEST_WEBHOOK_SECRET"
        else:
            secret = settings.stripe_webhook_secret
            env_var = "STRIPE_WEBHOOK_SECRET"

    if not secret:
        raise StripeConfigurationError(f"{env_var} missing for Stripe {context.mode.value} mode")
    return secret, env_var


async def ensure_price_accessible(
    price_config: MembershipPriceConfig, context: StripeContext
) -> dict[str, Any]:
    def _retrieve() -> dict[str, Any]:
        stripe.api_key = context.secret_key
        return stripe.Price.retrieve(price_config.price_id)

    try:
        price = await run_in_threadpool(_retrieve)
    except stripe.error.InvalidRequestError as exc:  # type: ignore[attr-defined]
        if getattr(exc, "code", "") == "resource_missing":
            raise StripeConfigurationError(
                f"{price_config.env_var} ({price_config.price_id}) is not available in Stripe {context.mode.value} mode ({context.secret_source})"
            ) from exc
        raise StripeConfigurationError(
            f"Stripe rejected price {price_config.price_id} from {price_config.env_var} ({context.mode.value} mode)"
        ) from exc
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise StripeConfigurationError(
            f"Failed to load Stripe price {price_config.price_id} from {price_config.env_var} ({context.mode.value} mode)"
        ) from exc

    livemode = price.get("livemode")
    if isinstance(livemode, bool):
        if context.mode is StripeMode.test and livemode:
            raise StripeConfigurationError(
                f"{price_config.env_var} ({price_config.price_id}) points to a live price while using sk_test_* ({context.secret_source})"
            )
        if context.mode is StripeMode.live and not livemode:
            raise StripeConfigurationError(
                f"{price_config.env_var} ({price_config.price_id}) points to a test price while using sk_live_* ({context.secret_source})"
            )

    product = price.get("product")
    if price_config.product_id and str(product) != price_config.product_id:
        raise StripeConfigurationError(
            f"{price_config.env_var} ({price_config.price_id}) is linked to product {product} instead of {price_config.product_id}"
        )

    return price


__all__ = [
    "StripeConfigurationError",
    "StripeContext",
    "StripeMode",
    "MembershipPriceConfig",
    "ensure_price_accessible",
    "resolve_membership_price",
    "resolve_stripe_context",
    "resolve_webhook_secret",
]
