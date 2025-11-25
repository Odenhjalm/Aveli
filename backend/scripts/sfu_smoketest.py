#!/usr/bin/env python3
"""
End-to-end smoke test for the Live Seminar flow.

This script assumes your local backend is running with the seed users from
`002_seed_dev.sql`. It exercises the following actions:

1. Log in as the seeded teacher (`teacher@wisdom.dev` / `password123`)
2. Create a draft seminar
3. Start a session (LiveKit REST is assumed to be mocked/disabled)
4. Log in as the seeded student (`student@wisdom.dev` / `password123`)
5. Register for the seminar as the student
6. End the session

Run:
    python scripts/sfu_smoketest.py --base-url http://127.0.0.1:8080
"""

from __future__ import annotations

import argparse
import asyncio
import sys
import uuid
from dataclasses import dataclass

import httpx


@dataclass
class Tokens:
    access: str
    refresh: str


async def login(client: httpx.AsyncClient, email: str, password: str) -> Tokens:
    resp = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
        timeout=20.0,
    )
    resp.raise_for_status()
    data = resp.json()
    return Tokens(access=data["access_token"], refresh=data["refresh_token"])


async def create_seminar(client: httpx.AsyncClient, token: str) -> str:
    payload = {
        "title": f"Smoke Seminar {uuid.uuid4().hex[:6]}",
        "description": "Automated smoke test seminar",
    }
    resp = await client.post(
        "/studio/seminars",
        json=payload,
        headers={"Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    seminar = resp.json()
    return str(seminar["id"])


async def start_session(client: httpx.AsyncClient, token: str, seminar_id: str) -> dict:
    resp = await client.post(
        f"/studio/seminars/{seminar_id}/sessions/start",
        headers={"Authorization": f"Bearer {token}"},
        json={},
    )
    resp.raise_for_status()
    return resp.json()


async def end_session(client: httpx.AsyncClient, token: str, seminar_id: str, session_id: str) -> None:
    resp = await client.post(
        f"/studio/seminars/{seminar_id}/sessions/{session_id}/end",
        headers={"Authorization": f"Bearer {token}"},
        json={"reason": "smoke_test"},
    )
    resp.raise_for_status()


async def register_participant(client: httpx.AsyncClient, token: str, seminar_id: str) -> None:
    resp = await client.post(
        f"/seminars/{seminar_id}/register",
        headers={"Authorization": f"Bearer {token}"},
    )
    if resp.status_code == 409:
        # Already registered – acceptable for smoke test reruns
        return
    resp.raise_for_status()


async def run_smoke_test(base_url: str) -> None:
    async with httpx.AsyncClient(base_url=base_url, timeout=30.0) as client:
        print(f"➡️  Logging in as teacher at {base_url}")
        teacher_tokens = await login(client, "teacher@wisdom.dev", "password123")

        print("➡️  Creating seminar")
        seminar_id = await create_seminar(client, teacher_tokens.access)
        print(f"   Seminar ID: {seminar_id}")

        print("➡️  Starting session (LiveKit REST mocked/disabled)")
        session_payload = await start_session(client, teacher_tokens.access, seminar_id)
        session_id = session_payload["session"]["id"]
        print(f"   Session ID: {session_id}")

        print("➡️  Logging in as student")
        student_tokens = await login(client, "student@wisdom.dev", "password123")

        print("➡️  Registering student to seminar")
        await register_participant(client, student_tokens.access, seminar_id)

        print("➡️  Ending session")
        await end_session(client, teacher_tokens.access, seminar_id, session_id)

        print("✅ Smoke test completed successfully")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Live Seminar smoke test")
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8080",
        help="Base URL for the backend (default: %(default)s)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        asyncio.run(run_smoke_test(args.base_url))
    except httpx.HTTPError as exc:
        print(f"❌ HTTP error: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # pragma: no cover - best effort smoke run
        print(f"❌ Unexpected error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
