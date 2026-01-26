#!/usr/bin/env python3
"""End-to-end smoke test for teacher/Stripe/SFU flows."""
from __future__ import annotations

import argparse
import asyncio
import os
import sys
import uuid

import httpx
import psycopg

from app import stripe_mode
from app.schemas.billing import SubscriptionInterval

DEFAULT_BASE_URL = "http://127.0.0.1:8080"


def resolve_base_url(cli_value: str | None = None) -> str:
    if cli_value:
        return cli_value
    return os.environ.get("QA_BASE_URL") or os.environ.get("API_BASE_URL") or DEFAULT_BASE_URL


def _ensure_db_url(url: str | None) -> str | None:
    if not url:
        return None
    if "sslmode=" in url:
        return url
    if "localhost" in url or "127.0.0.1" in url:
        return url
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}sslmode=require"


def _cleanup_user(db_url: str, email: str) -> None:
    print(f"[cleanup] deleting auth user {email}")
    with psycopg.connect(db_url, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM auth.users WHERE lower(email) = lower(%s)",
                (email,),
            )


def _subscriptions_enabled() -> bool:
    value = os.environ.get("SUBSCRIPTIONS_ENABLED", "true").strip().lower()
    return value not in {"false", "0", "no"}


async def _register_and_login(client: httpx.AsyncClient, email: str, password: str):
    print(f"[auth] registering {email}")
    register = await client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "QA Teacher"},
    )
    if register.status_code not in (201, 400):
        register.raise_for_status()

    print("[auth] logging in")
    login = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    login.raise_for_status()
    data = login.json()
    return data["access_token"], data.get("refresh_token")


async def _list_services(client: httpx.AsyncClient, token: str):
    resp = await client.get(
        "/services",
        params={"status": "active"},
        headers={"Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    payload = resp.json()
    return payload.get("items") or []


async def _create_order(client: httpx.AsyncClient, token: str, service_id: str):
    resp = await client.post(
        "/orders",
        headers={"Authorization": f"Bearer {token}"},
        json={"service_id": service_id},
    )
    resp.raise_for_status()
    return resp.json()["order"]


async def _fetch_sfu_token(client: httpx.AsyncClient, token: str, seminar_id: str):
    resp = await client.post(
        "/sfu/token",
        headers={"Authorization": f"Bearer {token}"},
        json={"seminar_id": seminar_id},
    )
    resp.raise_for_status()
    return resp.json()


async def _run_health_checks(client: httpx.AsyncClient, base_url: str) -> None:
    try:
        health = await client.get("/healthz")
        ready = await client.get("/readyz")
        health.raise_for_status()
        ready.raise_for_status()
        print("[healthz]", health.json())
        print("[readyz]", ready.json())
    except (httpx.RequestError, httpx.HTTPStatusError):
        print(f"Backend not reachable at {base_url}. Start it with: ./scripts/start_backend.sh")
        sys.exit(1)


async def _resolve_membership_price() -> tuple[stripe_mode.StripeContext, stripe_mode.MembershipPriceConfig]:
    try:
        context = stripe_mode.resolve_stripe_context()
        price_config = stripe_mode.resolve_membership_price(SubscriptionInterval.month, context)
        await stripe_mode.ensure_price_accessible(price_config, context)
        return context, price_config
    except stripe_mode.StripeConfigurationError as exc:
        print(f"[stripe] {exc}")
        sys.exit(1)


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", help="Override base URL for the backend")
    parser.add_argument(
        "--db-url",
        help="Postgres connection URL (used for automatic cleanup)",
        default=os.environ.get("QA_DB_URL") or os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL"),
    )
    parser.add_argument("--keep-data", action="store_true", help="Skip cleanup of QA user")
    parser.add_argument("--seminar-id", help="Optional seminar UUID to test SFU token flow")
    args = parser.parse_args()

    base_url = resolve_base_url(args.base_url)
    print(f"[config] base URL: {base_url}")
    db_url = _ensure_db_url(args.db_url)

    email = f"qa_{uuid.uuid4().hex[:8]}@aveli.local"
    password = "Secret123!"

    try:
        async with httpx.AsyncClient(base_url=base_url, timeout=20) as client:
            await _run_health_checks(client, base_url)
            token, refresh = await _register_and_login(client, email, password)
            services = await _list_services(client, token)
            if not services:
                print("[warn] inga aktiva tjänster – hoppar över order/Stripe-flödet")
            else:
                await _create_order(client, token, services[0]["id"])
                print(
                    f"[payments] skapade order för service {services[0]['id']} (ingen payment-element-körning)"
                )
            if args.seminar_id:
                try:
                    token_payload = await _fetch_sfu_token(client, token, args.seminar_id)
                    print(f"[sfu] token hämtad ({token_payload['ws_url']})")
                except httpx.HTTPStatusError as exc:
                    print(f"[warn] SFU-token misslyckades: {exc}")

            stripe_context, price_config = await _resolve_membership_price()
            print(
                "[stripe] mode=%s price=%s product=%s env=%s source=%s"
                % (
                    stripe_context.mode.value,
                    price_config.price_id,
                    price_config.product_id,
                    price_config.env_var,
                    stripe_context.secret_source,
                )
            )

            if not _subscriptions_enabled():
                print("[billing] subscriptions disabled; QA requires Stripe subscription flow")
                sys.exit(1)

            try:
                sub_resp = await client.post(
                    "/api/billing/create-subscription",
                    headers={"Authorization": f"Bearer {token}"},
                    json={
                        "plan_interval": "month",
                        "success_url": "http://localhost:3000/billing/success",
                        "cancel_url": "http://localhost:3000/billing/cancel",
                    },
                )
                sub_resp.raise_for_status()
                session_payload = sub_resp.json()
                print("[billing] subscription session", session_payload.get("checkout_url"))
                membership_resp = await client.get(
                    "/api/me/membership",
                    headers={"Authorization": f"Bearer {token}"},
                )
                membership_resp.raise_for_status()
                print("[billing] membership state", membership_resp.json())
            except httpx.HTTPStatusError as exc:
                body = exc.response.text if exc.response is not None else str(exc)
                print(
                    "[stripe] subscription checkout failed mode=%s price=%s product=%s env=%s status=%s body=%s"
                    % (
                        stripe_context.mode.value,
                        price_config.price_id,
                        price_config.product_id,
                        price_config.env_var,
                        exc.response.status_code if exc.response else "unknown",
                        body,
                    )
                )
                sys.exit(1)
            if refresh:
                refresh_resp = await client.post("/auth/refresh", json={"refresh_token": refresh})
                refresh_resp.raise_for_status()
                print("[auth] refresh succeeded")
            print("[done] QA-script klart")
    finally:
        if args.keep_data:
            return
        if not db_url:
            print(
                "[cleanup] QA user not removed (missing --db-url / SUPABASE_DB_URL).",
                file=sys.stderr,
            )
            return
        try:
            _cleanup_user(db_url, email)
        except Exception as exc:  # pragma: no cover
            print(f"[cleanup] failed to remove QA user: {exc}", file=sys.stderr)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(1)
