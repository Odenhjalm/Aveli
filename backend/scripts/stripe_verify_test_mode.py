#!/usr/bin/env python3
"""Verify Stripe keys are aligned with the active Stripe secret (test vs live)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ENV_PATH = ROOT / "backend" / ".env"
ENV_PATH = Path(os.getenv("BACKEND_ENV_FILE") or DEFAULT_ENV_PATH)
OVERLAY_ENV_VALUE = os.getenv("BACKEND_ENV_OVERLAY_FILE", "")
ENV_OVERLAY_PATH = Path(OVERLAY_ENV_VALUE) if OVERLAY_ENV_VALUE else None


def _val(key: str) -> str:
    return (os.environ.get(key) or "").strip()


def _is_live_publishable(value: str) -> bool:
    return value.startswith("pk_live_")


def _is_test_publishable(value: str) -> bool:
    return value.startswith("pk_test_")


def _exists(path: Path) -> bool:
    return path.exists() and path.is_file()


def main() -> int:
    env_errors: list[str] = []
    if ENV_PATH.exists():
        load_dotenv(ENV_PATH, override=False)
    else:
        env_errors.append(f"backend env missing at {ENV_PATH}")

    if ENV_OVERLAY_PATH:
        if ENV_OVERLAY_PATH.exists():
            load_dotenv(ENV_OVERLAY_PATH, override=True)
        else:
            env_errors.append(f"overlay env missing at {ENV_OVERLAY_PATH}")

    if env_errors:
        print("FAIL: " + "; ".join(env_errors) + "; cannot verify Stripe config.", file=sys.stderr)
        return 1

    try:
        from app import stripe_mode
    except Exception as exc:  # pragma: no cover - defensive
        print(f"FAIL: could not import Stripe mode resolver: {exc}", file=sys.stderr)
        return 1

    try:
        context = stripe_mode.resolve_stripe_context()
    except stripe_mode.StripeConfigurationError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    mode = context.mode.value
    errors: list[str] = []
    warnings: list[str] = []

    if mode == "test":
        active_pub = _val("STRIPE_TEST_PUBLISHABLE_KEY") or _val("STRIPE_PUBLISHABLE_KEY")
        active_webhook = _val("STRIPE_TEST_WEBHOOK_SECRET") or _val("STRIPE_WEBHOOK_SECRET")
        active_billing = _val("STRIPE_TEST_WEBHOOK_BILLING_SECRET") or _val("STRIPE_BILLING_WEBHOOK_SECRET")
    else:
        active_pub = _val("STRIPE_PUBLISHABLE_KEY")
        active_webhook = _val("STRIPE_WEBHOOK_SECRET")
        active_billing = _val("STRIPE_BILLING_WEBHOOK_SECRET")

    if not active_pub:
        errors.append("Stripe publishable key is missing for the active mode")
    elif mode == "test" and not _is_test_publishable(active_pub):
        errors.append("Stripe publishable key must be pk_test_ when using sk_test_*")
    elif mode == "live" and not _is_live_publishable(active_pub):
        errors.append("Stripe publishable key must be pk_live_ when using sk_live_*")

    if not active_webhook or not active_billing:
        errors.append("Stripe webhook secrets are missing for the active mode (provide STRIPE_WEBHOOK_SECRET/STRIPE_BILLING_WEBHOOK_SECRET or test equivalents)")
    else:
        for label, secret_value in (
            ("payment", active_webhook),
            ("billing", active_billing),
        ):
            if not secret_value.startswith("whsec_"):
                warnings.append(f"{label} webhook secret does not start with whsec_")

    if mode == "test":
        missing_test = [
            key
            for key in (
                "STRIPE_TEST_MEMBERSHIP_PRODUCT_ID",
                "STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY",
                "STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY",
            )
            if not _val(key)
        ]
        if missing_test:
            warnings.append(
                "Test membership product/price ids are missing (STRIPE_TEST_MEMBERSHIP_PRODUCT_ID, STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY, STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY); required for full test checkout flows"
            )
    else:
        missing_live = [
            key
            for key in ("AVELI_PRICE_MONTHLY", "AVELI_PRICE_YEARLY")
            if not _val(key)
        ]
        if missing_live:
            errors.append("Live membership price ids are missing: " + ", ".join(missing_live))

    stripe_routes = ROOT / "backend" / "app" / "routes"
    webhook_file = stripe_routes / "stripe_webhooks.py"
    billing_file = stripe_routes / "stripe_webhook.py"
    main_file = ROOT / "backend" / "app" / "main.py"

    if not _exists(webhook_file):
        errors.append("Missing stripe_webhooks.py route module")
    if not _exists(billing_file):
        errors.append("Missing stripe_webhook.py route module")
    if _exists(main_file):
        text = main_file.read_text(encoding="utf-8")
        if "stripe_webhooks" not in text:
            errors.append("stripe_webhooks router not wired in main.py")
        if "stripe_webhook" not in text:
            errors.append("stripe_webhook router not wired in main.py")
    else:
        errors.append("Missing main.py to verify Stripe routes")

    if warnings:
        for warning in warnings:
            print(f"WARN: {warning}")

    if errors:
        print("FAIL: Stripe key verification failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"PASS: Stripe keys verified ({mode}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
