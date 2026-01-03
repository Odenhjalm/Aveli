#!/usr/bin/env python3
"""Verify Stripe keys are aligned with APP_ENV (test vs live)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = Path(os.environ.get("BACKEND_ENV_FILE", "/home/oden/Aveli/backend/.env"))

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
        print(f"FAIL: backend env missing at {ENV_PATH}; cannot verify Stripe config.", file=sys.stderr)
        return 1

    app_env = (_val("APP_ENV") or _val("ENV") or _val("ENVIRONMENT")).lower()
    mode = "production" if app_env in {"prod", "production", "live"} else "development"
    require_live = os.environ.get("REQUIRE_LIVE_STRIPE_KEYS", "0") in {"1", "true", "TRUE"}

    required = [
        "STRIPE_SECRET_KEY",
        "STRIPE_PUBLISHABLE_KEY",
        "STRIPE_WEBHOOK_SECRET",
        "STRIPE_BILLING_WEBHOOK_SECRET",
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

    errors: list[str] = []
    warnings: list[str] = []

    if mode == "development":
        if not _is_test_secret(active_secret):
            errors.append("STRIPE_SECRET_KEY must be sk_test_ in development")
        if not _is_test_publishable(active_pub):
            errors.append("STRIPE_PUBLISHABLE_KEY must be pk_test_ in development")
    else:
        if _is_test_secret(active_secret) and _is_live_publishable(active_pub):
            warnings.append("Stripe secret is test but publishable is live")
        if _is_live_secret(active_secret) and _is_test_publishable(active_pub):
            warnings.append("Stripe secret is live but publishable is test")
        if _is_live_secret(active_secret) != _is_live_publishable(active_pub):
            errors.append("Stripe keys must both be test or both be live")
        if require_live:
            if not _is_live_secret(active_secret):
                errors.append("STRIPE_SECRET_KEY must be sk_live_ in production (REQUIRE_LIVE_STRIPE_KEYS=1)")
            if not _is_live_publishable(active_pub):
                errors.append("STRIPE_PUBLISHABLE_KEY must be pk_live_ in production (REQUIRE_LIVE_STRIPE_KEYS=1)")
        else:
            if _is_test_secret(active_secret):
                warnings.append("Production verify using test Stripe secret; set REQUIRE_LIVE_STRIPE_KEYS=1 to enforce live keys")
            if _is_test_publishable(active_pub):
                warnings.append("Production verify using test Stripe publishable key; set REQUIRE_LIVE_STRIPE_KEYS=1 to enforce live keys")

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
