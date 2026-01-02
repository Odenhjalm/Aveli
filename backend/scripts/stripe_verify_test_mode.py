#!/usr/bin/env python3
"""Verify Stripe keys are aligned with APP_ENV (test vs live)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "backend" / ".env"

if ENV_PATH.exists():
    load_dotenv(ENV_PATH, override=False)


def _val(key: str) -> str:
    return (os.environ.get(key) or "").strip()


def _is_live_secret(value: str) -> bool:
    return value.startswith("sk_live_")


def _is_test_secret(value: str) -> bool:
    return value.startswith("sk_test_")


def _is_live_publishable(value: str) -> bool:
    return value.startswith("pk_live_")


def _is_test_publishable(value: str) -> bool:
    return value.startswith("pk_test_")


def _exists(path: Path) -> bool:
    return path.exists() and path.is_file()


def main() -> int:
    if not ENV_PATH.exists():
        print("FAIL: backend/.env missing; cannot verify Stripe config.", file=sys.stderr)
        return 1

    app_env = (_val("APP_ENV") or _val("ENV") or _val("ENVIRONMENT")).lower()
    mode = "production" if app_env in {"prod", "production", "live"} else "development"

    required = [
        "STRIPE_SECRET_KEY",
        "STRIPE_PUBLISHABLE_KEY",
        "STRIPE_WEBHOOK_SECRET",
        "STRIPE_BILLING_WEBHOOK_SECRET",
        "AVELI_PRICE_MONTHLY",
        "AVELI_PRICE_YEARLY",
    ]
    missing = [key for key in required if not _val(key)]

    if missing:
        print("FAIL: Missing required Stripe keys:")
        for key in missing:
            print(f"- {key}")
        return 1

    active_secret = _val("STRIPE_SECRET_KEY")
    active_pub = _val("STRIPE_PUBLISHABLE_KEY")
    active_webhook = _val("STRIPE_WEBHOOK_SECRET")
    active_billing = _val("STRIPE_BILLING_WEBHOOK_SECRET")

    price_monthly = _val("AVELI_PRICE_MONTHLY")
    price_yearly = _val("AVELI_PRICE_YEARLY")

    errors: list[str] = []
    warnings: list[str] = []

    if mode == "development":
        if _is_live_secret(active_secret):
            warnings.append("STRIPE_SECRET_KEY is sk_live_ in development")
        if _is_live_publishable(active_pub):
            warnings.append("STRIPE_PUBLISHABLE_KEY is pk_live_ in development")
        if not (_is_test_secret(active_secret) or _is_live_secret(active_secret)):
            errors.append("STRIPE_SECRET_KEY must be sk_test_ or sk_live_")
        if not (_is_test_publishable(active_pub) or _is_live_publishable(active_pub)):
            errors.append("STRIPE_PUBLISHABLE_KEY must be pk_test_ or pk_live_")
    else:
        if not _is_live_secret(active_secret):
            errors.append("STRIPE_SECRET_KEY must be sk_live_ in production")
        if not _is_live_publishable(active_pub):
            errors.append("STRIPE_PUBLISHABLE_KEY must be pk_live_ in production")

    if active_webhook and not active_webhook.startswith("whsec_"):
        warnings.append("STRIPE_WEBHOOK_SECRET should start with whsec_")
    if active_billing and not active_billing.startswith("whsec_"):
        warnings.append("STRIPE_BILLING_WEBHOOK_SECRET should start with whsec_")
    if price_monthly and not price_monthly.startswith("price_"):
        warnings.append("AVELI_PRICE_MONTHLY should start with price_")
    if price_yearly and not price_yearly.startswith("price_"):
        warnings.append("AVELI_PRICE_YEARLY should start with price_")

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
