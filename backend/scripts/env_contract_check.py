#!/usr/bin/env python3
"""Validate backend/.env against required key contract.

Environment-aware:
- Development: warns for optional DB/JWT keys.
- Production: requires DB/JWT + live Stripe keys.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ENV_PATH = ROOT / "backend" / ".env"
ENV_PATH = Path(os.getenv("BACKEND_ENV_FILE") or DEFAULT_ENV_PATH)
OVERLAY_ENV_VALUE = os.getenv("BACKEND_ENV_OVERLAY_FILE", "")
ENV_OVERLAY_PATH = Path(OVERLAY_ENV_VALUE) if OVERLAY_ENV_VALUE else None
REQUIRED_PATH = ROOT / "ENV_REQUIRED_KEYS.txt"


def _parse_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
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
        if key:
            data[key] = value
    return data


def _load_required(path: Path) -> list[str]:
    keys: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        keys.append(line)
    return keys


def _env_value(env_map: dict[str, str], key: str) -> str:
    return os.environ.get(key) or env_map.get(key, "")


def _is_test_publishable(value: str) -> bool:
    return value.startswith("pk_test_")


def _is_live_publishable(value: str) -> bool:
    return value.startswith("pk_live_")


def main() -> int:
    overlay_set = bool(OVERLAY_ENV_VALUE)
    if not ENV_PATH.exists():
        print(f"ERROR: backend env missing at {ENV_PATH} (required for env contract check).", file=sys.stderr)
        return 1
    if overlay_set and (ENV_OVERLAY_PATH is None or not ENV_OVERLAY_PATH.exists()):
        print(
            f"ERROR: overlay env missing at {ENV_OVERLAY_PATH} (required for env contract check).",
            file=sys.stderr,
        )
        return 1
    if not REQUIRED_PATH.exists():
        print("ERROR: ENV_REQUIRED_KEYS.txt missing.", file=sys.stderr)
        return 1

    env_map = _parse_env(ENV_PATH)
    if overlay_set and ENV_OVERLAY_PATH:
        env_map.update(_parse_env(ENV_OVERLAY_PATH))

    required_keys = _load_required(REQUIRED_PATH)

    app_env = (
        _env_value(env_map, "APP_ENV")
        or _env_value(env_map, "ENV")
        or _env_value(env_map, "ENVIRONMENT")
    )
    env_lower = app_env.lower() if app_env else ""
    if env_lower in {"prod", "production", "live"}:
        mode = "production"
    else:
        mode = "development"
        if not env_lower:
            print("WARN: APP_ENV/ENV not set; assuming development.", file=sys.stderr)

    prod_only = {
        "SUPABASE_DB_URL",
        "JWT_SECRET",
        "JWT_ALGORITHM",
        "JWT_EXPIRES_MINUTES",
        "JWT_REFRESH_EXPIRES_MINUTES",
    }

    missing_required = [key for key in required_keys if not _env_value(env_map, key)]
    missing_prod = []
    missing_optional = []
    stripe_errors: list[str] = []
    stripe_warnings: list[str] = []

    if mode == "production":
        missing_prod = [key for key in sorted(prod_only) if not _env_value(env_map, key)]

    stripe_candidates = [
        (name, _env_value(env_map, name))
        for name in ("STRIPE_SECRET_KEY", "STRIPE_TEST_SECRET_KEY", "STRIPE_LIVE_SECRET_KEY")
        if _env_value(env_map, name)
    ]
    distinct_secrets = {value for _, value in stripe_candidates}
    stripe_mode = "unknown"
    if len(distinct_secrets) > 1:
        stripe_warnings.append(
            "Multiple Stripe secrets detected; selecting active key by mode/priority "
            "(overlay prefers test keys, otherwise prefers STRIPE_SECRET_KEY)"
        )
    if stripe_candidates:
        preferred_order = (
            ["STRIPE_TEST_SECRET_KEY", "STRIPE_SECRET_KEY", "STRIPE_LIVE_SECRET_KEY"]
            if overlay_set
            else ["STRIPE_SECRET_KEY", "STRIPE_TEST_SECRET_KEY", "STRIPE_LIVE_SECRET_KEY"]
        )
        active_name, active_value = None, None
        for candidate in preferred_order:
            match = next(((n, v) for n, v in stripe_candidates if n == candidate), None)
            if match:
                active_name, active_value = match
                break
        if not active_name:
            active_name, active_value = stripe_candidates[0]
        if active_value.startswith("sk_test_"):
            stripe_mode = "test"
        elif active_value.startswith("sk_live_"):
            stripe_mode = "live"
        else:
            stripe_errors.append(f"{active_name} must start with sk_test_ or sk_live_")
    else:
        stripe_errors.append(
            "Stripe secret key missing (set STRIPE_SECRET_KEY or STRIPE_TEST_SECRET_KEY or STRIPE_LIVE_SECRET_KEY)"
        )

    active_publishable = ""
    if stripe_mode == "test" and _env_value(env_map, "STRIPE_TEST_PUBLISHABLE_KEY"):
        active_publishable = _env_value(env_map, "STRIPE_TEST_PUBLISHABLE_KEY")
    else:
        active_publishable = _env_value(env_map, "STRIPE_PUBLISHABLE_KEY")
    if not active_publishable:
        stripe_errors.append("Stripe publishable key is missing for the active mode")
    elif stripe_mode == "test" and not _is_test_publishable(active_publishable):
        stripe_errors.append("Stripe publishable key must be pk_test_ when using sk_test_*")
    elif stripe_mode == "live" and not _is_live_publishable(active_publishable):
        stripe_errors.append("Stripe publishable key must be pk_live_ when using sk_live_*")

    active_webhook = _env_value(env_map, "STRIPE_WEBHOOK_SECRET")
    active_billing = _env_value(env_map, "STRIPE_BILLING_WEBHOOK_SECRET")
    if stripe_mode == "test":
        active_webhook = _env_value(env_map, "STRIPE_TEST_WEBHOOK_SECRET") or active_webhook
        active_billing = _env_value(env_map, "STRIPE_TEST_WEBHOOK_BILLING_SECRET") or active_billing

    if not active_webhook or not active_billing:
        stripe_errors.append(
            "Stripe webhook secrets are missing for the active mode (provide STRIPE_WEBHOOK_SECRET/STRIPE_BILLING_WEBHOOK_SECRET or test equivalents)"
        )
    else:
        if not active_webhook.startswith("whsec_"):
            stripe_warnings.append("Payment webhook secret does not start with whsec_")
        if not active_billing.startswith("whsec_"):
            stripe_warnings.append("Billing webhook secret does not start with whsec_")

    if stripe_mode == "test":
        missing_test = [
            key
            for key in (
                "STRIPE_TEST_MEMBERSHIP_PRODUCT_ID",
                "STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY",
                "STRIPE_TEST_MEMBERSHIP_PRICE_ID_YEARLY",
            )
            if not _env_value(env_map, key)
        ]
        if missing_test:
            stripe_warnings.append(
                "Test membership product/price ids are missing; required for full test checkout flows"
            )

    if missing_required:
        print("FAIL: Missing required keys:")
        for key in missing_required:
            print(f"- {key}")

    if missing_prod:
        print("FAIL: Missing production-only keys:")
        for key in missing_prod:
            print(f"- {key}")

    if stripe_errors:
        print("FAIL: Stripe configuration errors:")
        for error in stripe_errors:
            print(f"- {error}")

    if missing_optional:
        print("WARN: Optional keys missing for development:")
        for key in missing_optional:
            print(f"- {key}")

    for warning in stripe_warnings:
        print(f"WARN: {warning}")

    if missing_required or missing_prod or stripe_errors:
        return 1

    print(f"PASS: env contract satisfied ({mode}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
