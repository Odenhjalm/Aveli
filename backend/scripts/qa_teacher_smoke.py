#!/usr/bin/env python3
"""End-to-end smoke test for teacher/Stripe/SFU flows."""
from __future__ import annotations

import argparse
import asyncio
import os
import sys
import uuid

import httpx


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


async def _run_health_checks(client: httpx.AsyncClient) -> None:
    try:
        health = await client.get("/healthz")
        ready = await client.get("/readyz")
        print("[healthz]", health.json())
        print("[readyz]", ready.json())
    except httpx.HTTPStatusError as exc:
        print(f"[warn] health checks failed: {exc}")


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("QA_API_BASE_URL", "http://127.0.0.1:8080"))
    parser.add_argument("--seminar-id", help="Optional seminar UUID to test SFU token flow")
    args = parser.parse_args()

    email = f"qa_{uuid.uuid4().hex[:8]}@aveli.local"
    password = "Secret123!"

    async with httpx.AsyncClient(base_url=args.base_url, timeout=20) as client:
        await _run_health_checks(client)
        token, refresh = await _register_and_login(client, email, password)
        services = await _list_services(client, token)
        if not services:
            print("[warn] inga aktiva tjänster – hoppar över order/Stripe-flödet")
        else:
            order = await _create_order(client, token, services[0]["id"])
            try:
                checkout_url = await _checkout(client, token, order["id"])
                print(f"[payments] Payment Element: {checkout_url}")
            except httpx.HTTPStatusError as exc:
                print(f"[warn] kunde inte skapa checkout-session: {exc}")
        if args.seminar_id:
            try:
                token_payload = await _fetch_sfu_token(client, token, args.seminar_id)
                print(f"[sfu] token hämtad ({token_payload['ws_url']})")
            except httpx.HTTPStatusError as exc:
                print(f"[warn] SFU-token misslyckades: {exc}")

        if _subscriptions_enabled():
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
                print(f"[warn] Subscriptions API misslyckades: {exc}")
        else:
            print("[billing] subscriptions disabled; skipping subscription flow")
        if refresh:
            refresh_resp = await client.post("/auth/refresh", json={"refresh_token": refresh})
            refresh_resp.raise_for_status()
            print("[auth] refresh succeeded")
        print("[done] QA-script klart")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(1)
