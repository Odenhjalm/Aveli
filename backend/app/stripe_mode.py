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


def _normalize_mode(raw: str) -> StripeMode | None:
    value = raw.strip().lower()
    if not value:
        return None
    if value in ("test", "testing", "dev", "development"):
        return StripeMode.test
    if value in ("prod", "production", "live"):
        return StripeMode.live
    return None


def _explicit_mode_from_env() -> StripeMode | None:
    raw = (os.environ.get("STRIPE_KEYSET") or os.environ.get("APP_ENV_MODE") or "").strip()
    if not raw:
        return None
    mode = _normalize_mode(raw)
    if not mode:
        raise StripeConfigurationError("STRIPE_KEYSET/APP_ENV_MODE måste vara 'test' eller 'live'.")
    return mode


def _is_prod_env() -> bool:
    raw = (
        os.environ.get("APP_ENV")
        or os.environ.get("ENVIRONMENT")
        or os.environ.get("ENV")
        or ""
    )
    return raw.strip().lower() in ("prod", "production", "live")


def _infer_mode_from_keys() -> StripeMode | None:
    env_candidates = [
        ((os.environ.get("STRIPE_SECRET_KEY") or "").strip(), "STRIPE_SECRET_KEY"),
        ((os.environ.get("STRIPE_TEST_SECRET_KEY") or "").strip(), "STRIPE_TEST_SECRET_KEY"),
        ((os.environ.get("STRIPE_LIVE_SECRET_KEY") or "").strip(), "STRIPE_LIVE_SECRET_KEY"),
    ]
    if any(value for value, _ in env_candidates):
        candidates = env_candidates
    else:
        candidates = [
            ((settings.stripe_secret_key or "").strip(), "settings.stripe_secret_key"),
            ((settings.stripe_test_secret_key or "").strip(), "settings.stripe_test_secret_key"),
            ((settings.stripe_live_secret_key or "").strip(), "settings.stripe_live_secret_key"),
        ]
    has_test = False
    has_live = False
    for value, _ in candidates:
        if not value:
            continue
        if value.startswith("sk_test_"):
            has_test = True
        elif value.startswith("sk_live_"):
            has_live = True
        if has_test and has_live:
            return None
    if has_test:
        return StripeMode.test
    if has_live:
        return StripeMode.live
    return None


def _resolve_requested_mode() -> StripeMode:
    explicit_mode = _explicit_mode_from_env()
    if explicit_mode:
        if _is_prod_env() and explicit_mode is StripeMode.test:
            raise StripeConfigurationError(
                "APP_ENV anger produktion men Stripe-läget är test. Sätt STRIPE_KEYSET/APP_ENV_MODE=live."
            )
        return explicit_mode
    if _is_prod_env():
        return StripeMode.live
    if os.environ.get("BACKEND_ENV_OVERLAY_FILE"):
        return StripeMode.test
    inferred = _infer_mode_from_keys()
    if inferred:
        return inferred
    return StripeMode.live


def _resolve_secret_key(env_mode: StripeMode) -> tuple[str, str]:
    env_candidates = [
        ((os.environ.get("STRIPE_SECRET_KEY") or "").strip(), "STRIPE_SECRET_KEY"),
        ((os.environ.get("STRIPE_TEST_SECRET_KEY") or "").strip(), "STRIPE_TEST_SECRET_KEY"),
        ((os.environ.get("STRIPE_LIVE_SECRET_KEY") or "").strip(), "STRIPE_LIVE_SECRET_KEY"),
        ((settings.stripe_secret_key or "").strip(), "settings.stripe_secret_key"),
        ((settings.stripe_test_secret_key or "").strip(), "settings.stripe_test_secret_key"),
        ((settings.stripe_live_secret_key or "").strip(), "settings.stripe_live_secret_key"),
    ]

    test_candidates: list[tuple[str, str]] = []
    live_candidates: list[tuple[str, str]] = []

    for value, name in env_candidates:
        if not value:
            continue
        if value.startswith("sk_test_"):
            test_candidates.append((value, name))
        elif value.startswith("sk_live_"):
            live_candidates.append((value, name))
        else:
            raise StripeConfigurationError(f"{name} måste börja med sk_test_ eller sk_live_")

    test_values = {value for value, _ in test_candidates}
    live_values = {value for value, _ in live_candidates}
    if len(test_values) > 1:
        sources = ", ".join(name for _, name in test_candidates)
        raise StripeConfigurationError(f"Motstridiga Stripe-testnycklar är satta i: {sources}")
    if len(live_values) > 1:
        sources = ", ".join(name for _, name in live_candidates)
        raise StripeConfigurationError(f"Motstridiga Stripe-live-nycklar är satta i: {sources}")

    def pick(
        preferred_order: tuple[str, ...], candidates: list[tuple[str, str]]
    ) -> tuple[str, str] | None:
        for name in preferred_order:
            match = next((pair for pair in candidates if pair[1] == name), None)
            if match:
                return match
        return candidates[0] if candidates else None

    if env_mode is StripeMode.test:
        preferred_test = (
            "STRIPE_TEST_SECRET_KEY",
            "settings.stripe_test_secret_key",
            "STRIPE_SECRET_KEY",
            "settings.stripe_secret_key",
        )
        match = pick(preferred_test, test_candidates)
        if match:
            return match
        if live_candidates:
            raise StripeConfigurationError("Stripe-läget är test men bara live-nycklar är satta.")
    else:
        preferred_live = (
            "STRIPE_SECRET_KEY",
            "settings.stripe_secret_key",
            "STRIPE_LIVE_SECRET_KEY",
            "settings.stripe_live_secret_key",
        )
        match = pick(preferred_live, live_candidates)
        if match:
            return match
        if test_candidates:
            raise StripeConfigurationError("Stripe-läget är live men bara testnycklar är satta.")

    raise StripeConfigurationError("Stripe-nyckel saknas. Sätt STRIPE_SECRET_KEY.")


def resolve_stripe_context() -> StripeContext:
    env_mode = _resolve_requested_mode()
    secret_key, secret_source = _resolve_secret_key(env_mode)
    if secret_key.startswith("sk_test_"):
        mode = StripeMode.test
    elif secret_key.startswith("sk_live_"):
        mode = StripeMode.live
    else:
        raise StripeConfigurationError(f"{secret_source} måste börja med sk_test_ eller sk_live_")

    if mode is StripeMode.test and env_mode is StripeMode.live:
        raise StripeConfigurationError(
            f"{secret_source} är en testnyckel (sk_test_*) men Stripe-läget är live"
        )
    if mode is StripeMode.live and env_mode is StripeMode.test:
        raise StripeConfigurationError(
            f"{secret_source} är en live-nyckel (sk_live_*) men Stripe-läget är test"
        )

    return StripeContext(secret_key=secret_key, secret_source=secret_source, mode=mode)


def resolve_membership_price(
    interval: SubscriptionInterval, context: StripeContext
) -> MembershipPriceConfig:
    if context.mode is StripeMode.test:
        product_id = settings.stripe_test_membership_product_id
        if not product_id:
            raise StripeConfigurationError(
                "STRIPE_TEST_MEMBERSHIP_PRODUCT_ID saknas för Stripe-testläge"
            )
        if interval is SubscriptionInterval.month:
            price_id = settings.stripe_test_membership_price_monthly
            env_var = "STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY"
        elif interval is SubscriptionInterval.year:
            price_id = settings.stripe_test_membership_price_id_yearly
            env_var = "STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY"
        else:  # pragma: no cover - defensive
            raise StripeConfigurationError(f"Prenumerationsintervallet stöds inte: {interval}")
        if not price_id:
            raise StripeConfigurationError(f"{env_var} saknas för Stripe-testläge")
        return MembershipPriceConfig(price_id=price_id, env_var=env_var, product_id=product_id)

    if interval is SubscriptionInterval.month:
        price_id = settings.stripe_price_monthly
        env_var = "AVELI_PRICE_MONTHLY"
    elif interval is SubscriptionInterval.year:
        price_id = settings.stripe_price_yearly
        env_var = "AVELI_PRICE_YEARLY"
    else:  # pragma: no cover - defensive
        raise StripeConfigurationError(f"Prenumerationsintervallet stöds inte: {interval}")

    if not price_id:
        raise StripeConfigurationError(f"{env_var} saknas för Stripe-live-läge")

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
            env_var = (
                "STRIPE_BILLING_WEBHOOK_SECRET"
                if settings.stripe_billing_webhook_secret
                else "STRIPE_WEBHOOK_SECRET"
            )
    else:
        if context.mode is StripeMode.test:
            secret = settings.stripe_test_webhook_secret
            env_var = "STRIPE_TEST_WEBHOOK_SECRET"
        else:
            secret = settings.stripe_webhook_secret
            env_var = "STRIPE_WEBHOOK_SECRET"

    if not secret:
        raise StripeConfigurationError(f"{env_var} saknas för Stripe-{context.mode.value}-läge")
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
                f"{price_config.env_var} ({price_config.price_id}) är inte tillgängligt i "
                f"Stripe-{context.mode.value}-läge ({context.secret_source})"
            ) from exc
        raise StripeConfigurationError(
            f"Stripe avvisade priset {price_config.price_id} från {price_config.env_var} ({context.mode.value}-läge)"
        ) from exc
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise StripeConfigurationError(
            f"Kunde inte hämta Stripe-priset {price_config.price_id} från {price_config.env_var} "
            f"({context.mode.value}-läge)"
        ) from exc

    livemode = price.get("livemode")
    if isinstance(livemode, bool):
        if context.mode is StripeMode.test and livemode:
            raise StripeConfigurationError(
                f"{price_config.env_var} ({price_config.price_id}) pekar på ett live-pris medan "
                f"sk_test_* används ({context.secret_source})"
            )
        if context.mode is StripeMode.live and not livemode:
            raise StripeConfigurationError(
                f"{price_config.env_var} ({price_config.price_id}) pekar på ett testpris medan "
                f"sk_live_* används ({context.secret_source})"
            )

    product = price.get("product")
    if price_config.product_id and str(product) != price_config.product_id:
        raise StripeConfigurationError(
            f"{price_config.env_var} ({price_config.price_id}) är kopplat till produkten {product} "
            f"i stället för {price_config.product_id}"
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
