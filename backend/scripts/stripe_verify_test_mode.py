#!/usr/bin/env python3
"""Verify Stripe configuration using backend/.env (dev/prod aware)."""
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
SK_LIVE_RE = re.compile(r"^sk_live_")
PK_TEST_RE = re.compile(r"^pk_test_")
PK_LIVE_RE = re.compile(r"^pk_live_")
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


def resolve_env_mode(env: dict[str, str]) -> tuple[str, str]:
    raw = env.get("APP_ENV") or env.get("ENVIRONMENT") or env.get("ENV") or ""
    normalized = raw.strip().lower()
    if normalized in {"prod", "production", "live"}:
        return "prod", raw or "production"
    if normalized:
        return "dev", raw
    return "dev", "development"


def _bool_env(env: dict[str, str], name: str, default: bool) -> bool:
    raw = env.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}


def check_value(
    errors: list[str],
    warnings: list[str],
    name: str,
    value: str,
    pattern: re.Pattern[str] | None = None,
    required: bool = True,
) -> str:
    if not value:
        if required:
            errors.append(f"{name} is missing in backend/.env")
        else:
            warnings.append(f"{name} is missing in backend/.env")
        return ""
    if pattern and not pattern.match(value):
        if required:
            errors.append(f"{name} does not match expected pattern")
        else:
            warnings.append(f"{name} does not match expected pattern")
    return value


def ensure_match(
    errors: list[str],
    warnings: list[str],
    name: str,
    actual: str,
    expected: str,
    mode_label: str,
    required: bool,
) -> None:
    if actual and expected and actual != expected:
        if required:
            errors.append(f"{name} does not match {mode_label} value")
        else:
            warnings.append(f"{name} does not match {mode_label} value")


def main() -> None:
    env = load_env()
    errors: list[str] = []
    warnings: list[str] = []

    mode, mode_label = resolve_env_mode(env)
    subscriptions_enabled = _bool_env(
        env,
        "SUBSCRIPTIONS_ENABLED",
        default=mode == "prod",
    )

    active_secret = env.get("STRIPE_SECRET_KEY", "").strip()
    active_publishable = env.get("STRIPE_PUBLISHABLE_KEY", "").strip()
    active_webhook = env.get("STRIPE_WEBHOOK_SECRET", "").strip()
    active_billing = env.get("STRIPE_BILLING_WEBHOOK_SECRET", "").strip()

    test_secret = env.get("STRIPE_TEST_SECRET_KEY", "").strip()
    test_publishable = env.get("STRIPE_TEST_PUBLISHABLE_KEY", "").strip()
    test_webhook = env.get("STRIPE_TEST_WEBHOOK_SECRET", "").strip()
    test_billing_webhook = (
        env.get("STRIPE_TEST_WEBHOOK_BILLING_SECRET", "").strip()
        or env.get("STRIPE_TEST_BILLING_WEBHOOK_SECRET", "").strip()
    )

    live_secret = env.get("STRIPE_LIVE_SECRET_KEY", "").strip()
    live_publishable = env.get("STRIPE_LIVE_PUBLISHABLE_KEY", "").strip()
    live_webhook = env.get("STRIPE_LIVE_WEBHOOK_SECRET", "").strip()
    live_billing_webhook = env.get("STRIPE_LIVE_BILLING_WEBHOOK_SECRET", "").strip()

    billing_required = subscriptions_enabled
    if mode == "prod":
        expected_secret = check_value(errors, warnings, "STRIPE_LIVE_SECRET_KEY", live_secret, SK_LIVE_RE)
        expected_publishable = check_value(
            errors, warnings, "STRIPE_LIVE_PUBLISHABLE_KEY", live_publishable, PK_LIVE_RE
        )
        expected_webhook = check_value(
            errors, warnings, "STRIPE_LIVE_WEBHOOK_SECRET", live_webhook, WHSEC_RE
        )
        expected_billing = check_value(
            errors,
            warnings,
            "STRIPE_LIVE_BILLING_WEBHOOK_SECRET",
            live_billing_webhook,
            WHSEC_RE,
            required=billing_required,
        )
        active_secret = check_value(errors, warnings, "STRIPE_SECRET_KEY", active_secret, SK_LIVE_RE)
        active_publishable = check_value(
            errors, warnings, "STRIPE_PUBLISHABLE_KEY", active_publishable, PK_LIVE_RE
        )
        active_webhook = check_value(errors, warnings, "STRIPE_WEBHOOK_SECRET", active_webhook, WHSEC_RE)
        active_billing = check_value(
            errors,
            warnings,
            "STRIPE_BILLING_WEBHOOK_SECRET",
            active_billing,
            WHSEC_RE,
            required=billing_required,
        )
    else:
        expected_secret = check_value(
            errors, warnings, "STRIPE_TEST_SECRET_KEY", test_secret, SK_TEST_RE, required=False
        )
        expected_publishable = check_value(
            errors,
            warnings,
            "STRIPE_TEST_PUBLISHABLE_KEY",
            test_publishable,
            PK_TEST_RE,
            required=False,
        )
        expected_webhook = check_value(
            errors,
            warnings,
            "STRIPE_TEST_WEBHOOK_SECRET",
            test_webhook,
            WHSEC_RE,
            required=False,
        )
        expected_billing = check_value(
            errors,
            warnings,
            "STRIPE_TEST_WEBHOOK_BILLING_SECRET",
            test_billing_webhook,
            WHSEC_RE,
            required=False,
        )
        active_secret = check_value(errors, warnings, "STRIPE_SECRET_KEY", active_secret)
        if active_secret and not SK_TEST_RE.match(active_secret):
            warnings.append("STRIPE_SECRET_KEY is not a test key in dev")
        active_publishable = check_value(
            errors, warnings, "STRIPE_PUBLISHABLE_KEY", active_publishable
        )
        if active_publishable and not PK_TEST_RE.match(active_publishable):
            warnings.append("STRIPE_PUBLISHABLE_KEY is not a test key in dev")
        active_webhook = check_value(errors, warnings, "STRIPE_WEBHOOK_SECRET", active_webhook, WHSEC_RE)
        active_billing = check_value(
            errors,
            warnings,
            "STRIPE_BILLING_WEBHOOK_SECRET",
            active_billing,
            WHSEC_RE,
            required=billing_required,
        )

    ensure_match(errors, warnings, "STRIPE_SECRET_KEY", active_secret, expected_secret, mode_label, required=False)
    ensure_match(
        errors, warnings, "STRIPE_PUBLISHABLE_KEY", active_publishable, expected_publishable, mode_label, required=False
    )
    ensure_match(errors, warnings, "STRIPE_WEBHOOK_SECRET", active_webhook, expected_webhook, mode_label, required=False)
    ensure_match(
        errors,
        warnings,
        "STRIPE_BILLING_WEBHOOK_SECRET",
        active_billing,
        expected_billing,
        mode_label,
        required=False,
    )

    livemode = None
    if active_secret:
        try:
            stripe.api_key = active_secret
            acct = stripe.Account.retrieve()
            livemode = acct.get("livemode")
            expected_livemode = mode == "prod"
            if livemode is not None and livemode != expected_livemode:
                errors.append(
                    "Stripe account mode mismatch: "
                    f"expected {'live' if expected_livemode else 'test'}"
                )
        except stripe.error.StripeError:  # type: ignore[attr-defined]
            if mode == "prod":
                errors.append("Stripe authentication failed for STRIPE_SECRET_KEY")
            else:
                warnings.append("Stripe authentication failed for STRIPE_SECRET_KEY")

    expected_paths_raw = env.get("STRIPE_EXPECTED_WEBHOOK_PATHS", "").strip()
    if expected_paths_raw:
        expected_paths = [p.strip() for p in expected_paths_raw.split(",") if p.strip()]
    elif mode == "prod":
        expected_paths = ["/webhooks/stripe", "/api/billing/webhook"]
    else:
        expected_paths = ["/api/billing/webhook"]

    found_paths: dict[str, bool] = {path: False for path in expected_paths}
    listed_endpoints = False
    if active_secret:
        try:
            endpoints = stripe.WebhookEndpoint.list(limit=100)
            listed_endpoints = True
            for endpoint in endpoints.auto_paging_iter():
                url = endpoint.get("url")
                if not url:
                    continue
                path = urlparse(url).path.rstrip("/")
                for expected in expected_paths:
                    if path.endswith(expected):
                        found_paths[expected] = True
        except stripe.error.StripeError:  # type: ignore[attr-defined]
            if mode == "prod":
                errors.append("Failed to list Stripe webhook endpoints")
            else:
                warnings.append("Failed to list Stripe webhook endpoints")

    if listed_endpoints:
        for expected, found in found_paths.items():
            if not found:
                if mode == "prod":
                    errors.append(f"Stripe webhook endpoint for {expected} not found")
                else:
                    warnings.append(f"Stripe webhook endpoint for {expected} not found")

    print(f"==> Stripe verification ({mode_label})")
    print(f"- STRIPE_SECRET_KEY: {'set' if active_secret else 'missing'}")
    print(f"- STRIPE_PUBLISHABLE_KEY: {'set' if active_publishable else 'missing'}")
    print(f"- STRIPE_WEBHOOK_SECRET: {'set' if active_webhook else 'missing'}")
    print(f"- STRIPE_BILLING_WEBHOOK_SECRET: {'set' if active_billing else 'missing'}")
    if livemode is not None:
        print(f"- Stripe account livemode: {livemode}")
    if expected_paths:
        summary = "; ".join(
            f"{path}={'found' if found_paths.get(path) else 'missing'}"
            for path in expected_paths
        )
        print(f"- Webhook endpoints: {summary}")
    else:
        print("- Webhook endpoints: none expected")

    if warnings:
        print("Stripe verification: WARN")
        for warning in warnings:
            print(f"  - {warning}")

    if errors:
        print("Stripe verification: FAIL")
        for err in errors:
            print(f"  - {err}")
        raise SystemExit(1)

    print("Stripe verification: PASS")


if __name__ == "__main__":
    main()
