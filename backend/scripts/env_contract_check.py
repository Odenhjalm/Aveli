#!/usr/bin/env python3
"""Minimal backend env contract check.

Ensures required env files are present. Does not print secrets.
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


def _normalize_stripe_mode(raw: str) -> str | None:
    value = raw.strip().lower()
    if not value:
        return None
    if value in {"test", "testing", "dev", "development"}:
        return "test"
    if value in {"prod", "production", "live"}:
        return "live"
    return None


def _is_prod_env(raw: str) -> bool:
    return raw.strip().lower() in {"prod", "production", "live"}


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
    if _is_prod_env(env_lower):
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

    stripe_required_keys = {
        "STRIPE_SECRET_KEY",
        "STRIPE_PUBLISHABLE_KEY",
        "STRIPE_WEBHOOK_SECRET",
        "STRIPE_BILLING_WEBHOOK_SECRET",
        "AVELI_PRICE_MONTHLY",
        "AVELI_PRICE_YEARLY",
    }

    missing_required = [
        key for key in required_keys if key not in stripe_required_keys and not _env_value(env_map, key)
    ]
    missing_prod = []
    missing_optional = []
    stripe_errors: list[str] = []
    stripe_warnings: list[str] = []

    if mode == "production":
        missing_prod = [key for key in sorted(prod_only) if not _env_value(env_map, key)]

    explicit_raw = _env_value(env_map, "STRIPE_KEYSET") or _env_value(env_map, "APP_ENV_MODE")
    stripe_mode = None
    explicit_mode = False
    if explicit_raw:
        stripe_mode = _normalize_stripe_mode(explicit_raw)
        if not stripe_mode:
            stripe_errors.append("STRIPE_KEYSET/APP_ENV_MODE must be 'test' or 'live'.")
        else:
            explicit_mode = True
            if mode == "production" and stripe_mode == "test":
                stripe_errors.append(
                    "APP_ENV indicates production but Stripe mode is test; set STRIPE_KEYSET/APP_ENV_MODE=live."
                )

    if not stripe_mode:
        if mode == "production":
            stripe_mode = "live"
        elif overlay_set:
            stripe_mode = "test"
        else:
            stripe_mode = "live"

    test_candidates: list[tuple[str, str]] = []
    live_candidates: list[tuple[str, str]] = []
    invalid_candidates: list[tuple[str, str]] = []
    for name in ("STRIPE_SECRET_KEY", "STRIPE_TEST_SECRET_KEY", "STRIPE_LIVE_SECRET_KEY"):
        value = _env_value(env_map, name)
        if not value:
            continue
        if value.startswith("sk_test_"):
            test_candidates.append((value, name))
        elif value.startswith("sk_live_"):
            live_candidates.append((value, name))
        else:
            invalid_candidates.append((value, name))

    if not explicit_mode and mode != "production" and not overlay_set:
        if test_candidates and not live_candidates:
            stripe_mode = "test"
        elif live_candidates and not test_candidates:
            stripe_mode = "live"

    test_values = {value for value, _ in test_candidates}
    live_values = {value for value, _ in live_candidates}
    if len(test_values) > 1:
        sources = ", ".join(name for _, name in test_candidates)
        if overlay_set:
            stripe_warnings.append(f"Conflicting Stripe test secrets set across: {sources}")
        else:
            stripe_errors.append(f"Conflicting Stripe test secrets set across: {sources}")
    if len(live_values) > 1:
        sources = ", ".join(name for _, name in live_candidates)
        if overlay_set:
            stripe_warnings.append(f"Conflicting Stripe live secrets set across: {sources}")
        else:
            stripe_errors.append(f"Conflicting Stripe live secrets set across: {sources}")

    def pick(preferred: tuple[str, ...], candidates: list[tuple[str, str]]) -> tuple[str, str] | None:
        for name in preferred:
            match = next((pair for pair in candidates if pair[1] == name), None)
            if match:
                return match
        return candidates[0] if candidates else None

    active_name = None
    active_value = None
    if stripe_mode == "test":
        match = pick(("STRIPE_TEST_SECRET_KEY", "STRIPE_SECRET_KEY"), test_candidates)
        if match:
            active_value, active_name = match
        elif live_candidates:
            stripe_errors.append("Stripe mode is test but only live Stripe secrets are set.")
        elif invalid_candidates:
            _, bad_name = invalid_candidates[0]
            stripe_errors.append(f"{bad_name} must start with sk_test_ or sk_live_")
        else:
            stripe_errors.append("Stripe secret key missing for test mode (set STRIPE_TEST_SECRET_KEY).")
    else:
        match = pick(("STRIPE_SECRET_KEY", "STRIPE_LIVE_SECRET_KEY"), live_candidates)
        if match:
            active_value, active_name = match
        elif test_candidates:
            stripe_errors.append("Stripe mode is live but only test Stripe secrets are set.")
        elif invalid_candidates:
            _, bad_name = invalid_candidates[0]
            stripe_errors.append(f"{bad_name} must start with sk_test_ or sk_live_")
        else:
            stripe_errors.append("Stripe secret key missing for live mode (set STRIPE_SECRET_KEY).")

    if stripe_mode == "test" and live_candidates:
        sources = ", ".join(name for _, name in live_candidates)
        stripe_warnings.append(
            f"Live Stripe secret present ({sources}) while Stripe mode is test; test keys will be used."
        )
    elif stripe_mode == "live" and test_candidates:
        sources = ", ".join(name for _, name in test_candidates)
        stripe_warnings.append(
            f"Test Stripe secret present ({sources}) while Stripe mode is live; live keys will be used."
        )

    if active_value:
        if stripe_mode == "test" and not active_value.startswith("sk_test_"):
            stripe_errors.append("Stripe mode is test but active secret is not sk_test_*")
        if stripe_mode == "live" and not active_value.startswith("sk_live_"):
            stripe_errors.append("Stripe mode is live but active secret is not sk_live_*")

    active_publishable = ""
    publishable_invalid = False
    if stripe_mode == "test":
        test_publishable = _env_value(env_map, "STRIPE_TEST_PUBLISHABLE_KEY")
        if test_publishable:
            if test_publishable.startswith("pk_test_"):
                active_publishable = test_publishable
            else:
                publishable_invalid = True
        if not active_publishable:
            base_publishable = _env_value(env_map, "STRIPE_PUBLISHABLE_KEY")
            if base_publishable:
                if base_publishable.startswith("pk_test_"):
                    active_publishable = base_publishable
                else:
                    publishable_invalid = True
    else:
        base_publishable = _env_value(env_map, "STRIPE_PUBLISHABLE_KEY")
        if base_publishable:
            if base_publishable.startswith("pk_live_"):
                active_publishable = base_publishable
            else:
                publishable_invalid = True
        if not active_publishable:
            live_publishable = _env_value(env_map, "STRIPE_LIVE_PUBLISHABLE_KEY")
            if live_publishable:
                if live_publishable.startswith("pk_live_"):
                    active_publishable = live_publishable
                else:
                    publishable_invalid = True

    if not active_publishable:
        if publishable_invalid:
            if stripe_mode == "test":
                stripe_errors.append("Stripe publishable key must be pk_test_ when using sk_test_*")
            else:
                stripe_errors.append("Stripe publishable key must be pk_live_ when using sk_live_*")
        else:
            stripe_errors.append("Stripe publishable key is missing for the active mode")

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
    else:
        missing_live = [
            key
            for key in ("AVELI_PRICE_MONTHLY", "AVELI_PRICE_YEARLY")
            if not _env_value(env_map, key)
        ]
        if missing_live:
            stripe_errors.append("Live membership price ids are missing: " + ", ".join(missing_live))

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

    print(f"PASS: env contract satisfied ({mode}, stripe={stripe_mode}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
