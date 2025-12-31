#!/usr/bin/env python3
"""Verify Stripe test-mode configuration using backend/.env."""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import urlparse

try:
    import stripe
except Exception:  # pragma: no cover - dependency guard
    print("ERROR: stripe library not available; run `poetry install`", file=sys.stderr)
    raise SystemExit(1)


ROOT_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT_DIR / "backend" / ".env"

SK_TEST_RE = re.compile(r"^sk_test_")
PK_TEST_RE = re.compile(r"^pk_test_")
WHSEC_RE = re.compile(r"^whsec_")


def _die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_env() -> dict[str, str]:
    if not ENV_FILE.exists():
        _die("backend/.env missing – create it from backend/.env.example")
    env: dict[str, str] = {}
    for raw_line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value and value[0] == value[-1] and value[0] in ("\"", "'"):
            value = value[1:-1]
        env[key] = value
    return env


def main() -> None:
    env = load_env()
    errors: list[str] = []

    def require(key: str, pattern: re.Pattern[str] | None = None) -> str:
        value = env.get(key, "").strip()
        if not value:
            errors.append(f"{key} is missing in backend/.env")
            return ""
        if pattern and not pattern.match(value):
            errors.append(f"{key} does not match expected test pattern")
        return value

    secret_key = require("STRIPE_SECRET_KEY", SK_TEST_RE)
    publishable_key = require("STRIPE_PUBLISHABLE_KEY", PK_TEST_RE)
    webhook_secret = require("STRIPE_WEBHOOK_SECRET", WHSEC_RE)
    billing_webhook_secret = require("STRIPE_BILLING_WEBHOOK_SECRET", WHSEC_RE)

    livemode = None
    if secret_key:
        try:
            stripe.api_key = secret_key
            acct = stripe.Account.retrieve()
            livemode = acct.get("livemode")
            if livemode:
                errors.append("Stripe account is in live mode; expected test mode")
        except stripe.error.StripeError:  # type: ignore[attr-defined]
            errors.append("Stripe authentication failed for STRIPE_SECRET_KEY")

    found_payment = False
    found_billing = False
    listed_endpoints = False
    if secret_key:
        try:
            endpoints = stripe.WebhookEndpoint.list(limit=100)
            listed_endpoints = True
            for endpoint in endpoints.auto_paging_iter():
                url = endpoint.get("url")
                if not url:
                    continue
                path = urlparse(url).path.rstrip("/")
                if path.endswith("/webhooks/stripe"):
                    found_payment = True
                if path.endswith("/api/billing/webhook"):
                    found_billing = True
        except stripe.error.StripeError:  # type: ignore[attr-defined]
            errors.append("Failed to list Stripe webhook endpoints")

    if listed_endpoints:
        if not found_payment:
            errors.append("Stripe webhook endpoint for /webhooks/stripe not found (test mode)")
        if not found_billing:
            errors.append("Stripe webhook endpoint for /api/billing/webhook not found (test mode)")

    print("==> Stripe test mode verification")
    print(f"- STRIPE_SECRET_KEY: {'set' if secret_key else 'missing'}")
    print(f"- STRIPE_PUBLISHABLE_KEY: {'set' if publishable_key else 'missing'}")
    print(f"- STRIPE_WEBHOOK_SECRET: {'set' if webhook_secret else 'missing'}")
    print(f"- STRIPE_BILLING_WEBHOOK_SECRET: {'set' if billing_webhook_secret else 'missing'}")
    if livemode is not None:
        print(f"- Stripe account livemode: {livemode}")
    print(f"- Webhook endpoints: /webhooks/stripe={'found' if found_payment else 'missing'}; "
          f"/api/billing/webhook={'found' if found_billing else 'missing'}")

    if errors:
        print("Stripe verification: FAIL")
        for err in errors:
            print(f"  - {err}")
        raise SystemExit(1)

    print("Stripe verification: PASS")


if __name__ == "__main__":
    main()
