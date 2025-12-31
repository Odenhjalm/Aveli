#!/usr/bin/env python3
"""End-to-end smoke test for teacher/Stripe/SFU flows."""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import hmac
import json
import os
import sys
import time
import uuid

import httpx


def _is_strict_mode() -> bool:
    return os.environ.get("CI", "").lower() in {"1", "true", "yes"}


def _bool_env(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _warn(message: str, warnings: list[str]) -> None:
    warnings.append(message)
    print(f"[warn] {message}")


def _build_stripe_signature(secret: str, payload: str) -> str:
    timestamp = int(time.time())
    signed_payload = f"{timestamp}.{payload}".encode("utf-8")
    digest = hmac.new(secret.encode("utf-8"), signed_payload, hashlib.sha256).hexdigest()
    return f"t={timestamp},v1={digest}"


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


async def _checkout(client: httpx.AsyncClient, token: str, order_id: str):
    resp = await client.post(
        "/payments/stripe/create-session",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "order_id": order_id,
            "success_url": "https://example.org/success",
            "cancel_url": "https://example.org/cancel",
        },
    )
    resp.raise_for_status()
    return resp.json()["url"]


async def _fetch_sfu_token(client: httpx.AsyncClient, token: str, seminar_id: str):
    resp = await client.post(
        "/sfu/token",
        headers={"Authorization": f"Bearer {token}"},
        json={"seminar_id": seminar_id},
    )
    resp.raise_for_status()
    return resp.json()


async def _run_health_checks(client: httpx.AsyncClient, warnings: list[str]) -> None:
    try:
        health = await client.get("/healthz")
        ready = await client.get("/readyz")
        print("[healthz]", health.json())
        print("[readyz]", ready.json())
    except httpx.HTTPStatusError as exc:
        _warn(f"health checks failed: {exc}", warnings)


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("QA_API_BASE_URL", "http://127.0.0.1:8080"))
    parser.add_argument("--seminar-id", help="Optional seminar UUID to test SFU token flow")
    args = parser.parse_args()

    email = f"qa_{uuid.uuid4().hex[:8]}@aveli.local"
    password = "Secret123!"
    warnings: list[str] = []
    strict_mode = _is_strict_mode()

    async with httpx.AsyncClient(base_url=args.base_url, timeout=20) as client:
        await _run_health_checks(client, warnings)
        token, refresh = await _register_and_login(client, email, password)
        profile_resp = await client.get(
            "/profiles/me", headers={"Authorization": f"Bearer {token}"}
        )
        profile_resp.raise_for_status()
        user_id = profile_resp.json().get("user_id")
        services = await _list_services(client, token)
        if not services:
            _warn("inga aktiva tjänster – hoppar över order/Stripe-flödet", warnings)
        else:
            order = await _create_order(client, token, services[0]["id"])
            try:
                checkout_url = await _checkout(client, token, order["id"])
                print(f"[payments] Payment Element: {checkout_url}")
            except httpx.HTTPStatusError as exc:
                _warn(f"kunde inte skapa checkout-session: {exc}", warnings)
        if args.seminar_id:
            try:
                token_payload = await _fetch_sfu_token(client, token, args.seminar_id)
                print(f"[sfu] token hämtad ({token_payload['ws_url']})")
            except httpx.HTTPStatusError as exc:
                _warn(f"SFU-token misslyckades: {exc}", warnings)

        app_env = os.environ.get("APP_ENV", "").strip().lower()
        subscriptions_enabled = _bool_env(
            "SUBSCRIPTIONS_ENABLED",
            default=app_env in {"prod", "production", "live"},
        )
        if not subscriptions_enabled:
            message = "subscriptions disabled; skipping subscription flow"
            if app_env in {"prod", "production", "live"}:
                _warn(message, warnings)
            else:
                print(f"[billing] {message}")
        else:
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
                checkout_url = session_payload.get("checkout_url")
                if not checkout_url:
                    _warn("subscription session saknar checkout_url", warnings)
                else:
                    print("[billing] subscription session", checkout_url)
                membership_resp = await client.get(
                    "/api/me/membership",
                    headers={"Authorization": f"Bearer {token}"},
                )
                membership_resp.raise_for_status()
                membership_payload = membership_resp.json().get("membership")
                if not membership_payload:
                    _warn("membership saknas efter create-subscription", warnings)
                else:
                    print("[billing] membership state", membership_resp.json())
                    secret = os.environ.get("STRIPE_BILLING_WEBHOOK_SECRET") or os.environ.get(
                        "STRIPE_WEBHOOK_SECRET"
                    )
                    customer_id = membership_payload.get("stripe_customer_id")
                    price_id = membership_payload.get("price_id")
                    interval = membership_payload.get("plan_interval") or "month"
                    if not secret:
                        _warn("saknar STRIPE_BILLING_WEBHOOK_SECRET; webhook-test hoppas over", warnings)
                    elif not (customer_id and price_id):
                        _warn("membership saknar Stripe-referenser; webhook-test hoppas over", warnings)
                    else:
                        event_payload = {
                            "id": f"evt_{uuid.uuid4().hex[:12]}",
                            "type": "customer.subscription.updated",
                            "data": {
                                "object": {
                                    "id": f"sub_{uuid.uuid4().hex[:12]}",
                                    "customer": customer_id,
                                    "status": "active",
                                    "items": {
                                        "data": [
                                            {
                                                "price": {
                                                    "id": price_id,
                                                    "recurring": {"interval": interval},
                                                }
                                            }
                                        ]
                                    },
                                    "metadata": {"user_id": user_id} if user_id else {},
                                }
                            },
                        }
                        payload_json = json.dumps(event_payload)
                        signature = _build_stripe_signature(secret, payload_json)
                        webhook_resp = await client.post(
                            "/api/billing/webhook",
                            content=payload_json,
                            headers={"stripe-signature": signature},
                        )
                        if webhook_resp.status_code != 200:
                            _warn(
                                f"webhook misslyckades: {webhook_resp.status_code} {webhook_resp.text}",
                                warnings,
                            )
                        else:
                            updated_resp = await client.get(
                                "/api/me/membership",
                                headers={"Authorization": f"Bearer {token}"},
                            )
                            updated_resp.raise_for_status()
                            updated = updated_resp.json().get("membership") or {}
                            if updated.get("status") != "active":
                                _warn(
                                    f"membership status efter webhook: {updated.get('status')}",
                                    warnings,
                                )
            except httpx.HTTPStatusError as exc:
                _warn(f"Subscriptions API misslyckades: {exc}", warnings)
        if refresh:
            refresh_resp = await client.post("/auth/refresh", json={"refresh_token": refresh})
            refresh_resp.raise_for_status()
            print("[auth] refresh succeeded")
        print("[done] QA-script klart")

    if strict_mode and warnings:
        raise SystemExit("Smoke test warnings in CI mode")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(1)
