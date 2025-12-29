#!/usr/bin/env python3
"""Automated smoke test for seminar session lifecycle (register/start/end).

This script exercises the following backend flows against a running Aveli backend:
  1. Register (or log in) a host and promote to teacher (optionally via DATABASE_URL).
  2. Register (or log in) a participant account.
  3. Host creates a seminar, starts a session, participant registers, host ends the session.

The script validates every HTTP response and raises on unexpected status codes.
It can optionally start a lightweight LiveKit REST mock (CreateRoom/EndRoom) so the backend
does not reach the real LiveKit API. Ensure your backend is configured with LIVEKIT_API_URL
pointing at the mock host/port when using this flag, and that LIVEKIT_WS_URL is set.

Example:
    scripts/qa_session_smoke.py --base-url http://localhost:8080 --mock-livekit \
        --database-url postgres://postgres:postgres@localhost:5432/wisdom

CLI flags can be provided via environment variables:
    QA_API_BASE_URL
    QA_HOST_EMAIL / QA_HOST_PASSWORD
    QA_PARTICIPANT_EMAIL / QA_PARTICIPANT_PASSWORD
    QA_DATABASE_URL
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Optional

import psycopg
import requests


class SmokeTestError(RuntimeError):
    """Raised when a smoke test step fails."""


@dataclass
class AuthSession:
    token: str
    user_id: str
    email: str


def _env_or_default(key: str, value: Optional[str], fallback: Optional[str] = None) -> Optional[str]:
    return value or os.environ.get(key) or fallback


def _auth_headers(session: AuthSession) -> dict[str, str]:
    return {"Authorization": f"Bearer {session.token}"}


class _LiveKitMockHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _write_json(self, payload: dict) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):  # noqa: N802 (BaseHTTPRequestHandler API)
        if self.path.endswith("CreateRoom"):
            self._write_json({"room": {"name": "mock-room"}})
        elif self.path.endswith("EndRoom"):
            self._write_json({"ok": True})
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()

    def log_message(self, format: str, *args):  # noqa: A003 - lint false positive for builtin shadow
        return  # Silence default stdout logging


def _start_livekit_mock(host: str, port: int) -> HTTPServer:
    server = HTTPServer((host, port), _LiveKitMockHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(f"[livekit-mock] Listening on http://{host}:{port}", file=sys.stderr)
    return server


def _stop_livekit_mock(server: HTTPServer) -> None:
    server.shutdown()
    server.server_close()


def _ensure_account(
    base_url: str,
    email: str,
    password: str,
    display_name: str,
) -> AuthSession:
    register_resp = requests.post(
        f"{base_url}/auth/register",
        json={"email": email, "password": password, "display_name": display_name},
        timeout=10,
    )
    if register_resp.status_code not in (201, 400):
        raise SmokeTestError(
            f"Register failed for {email}: {register_resp.status_code} {register_resp.text}"
        )
    login_resp = requests.post(
        f"{base_url}/auth/login",
        json={"email": email, "password": password},
        timeout=10,
    )
    if login_resp.status_code != 200:
        raise SmokeTestError(f"Login failed for {email}: {login_resp.status_code} {login_resp.text}")
    token = login_resp.json().get("access_token")
    if not token:
        raise SmokeTestError("Login response missing access_token")
    profile_resp = requests.get(
        f"{base_url}/profiles/me",
        headers={"Authorization": f"Bearer {token}"},
        timeout=10,
    )
    if profile_resp.status_code != 200:
        raise SmokeTestError(
            f"Failed to fetch profile for {email}: {profile_resp.status_code} {profile_resp.text}"
        )
    user_id = profile_resp.json().get("user_id")
    if not user_id:
        raise SmokeTestError("Profile response missing user_id")
    return AuthSession(token=token, user_id=str(user_id), email=email)


def _promote_teacher(database_url: str, user_id: str) -> None:
    try:
        with psycopg.connect(database_url, autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "update app.profiles set role_v2 = 'teacher' where user_id = %s",
                    (user_id,),
                )
                if cur.rowcount == 0:
                    raise SmokeTestError(
                        "Unable to promote host account to teacher (no matching profile row)"
                    )
    except psycopg.Error as exc:  # pragma: no cover - best effort diagnostics
        raise SmokeTestError(f"Database promotion failed: {exc}") from exc


def _assert_teacher_role(base_url: str, session: AuthSession) -> None:
    resp = requests.get(
        f"{base_url}/profiles/me",
        headers=_auth_headers(session),
        timeout=10,
    )
    if resp.status_code != 200:
        raise SmokeTestError(f"Failed to verify teacher role: {resp.status_code} {resp.text}")
    role = resp.json().get("role_v2") or resp.json().get("role")
    if role != "teacher":
        raise SmokeTestError(
            "Host account is not a teacher; provide --database-url or promote manually before rerunning"
        )


def _create_seminar(base_url: str, session: AuthSession) -> dict:
    scheduled_at = datetime.now(timezone.utc) + timedelta(minutes=30)
    payload = {
        "title": "QA Session Smoke",
        "description": "Automated seminar session lifecycle smoke test",
        "scheduled_at": scheduled_at.isoformat(),
        "duration_minutes": 45,
    }
    resp = requests.post(
        f"{base_url}/studio/seminars",
        json=payload,
        headers=_auth_headers(session),
        timeout=10,
    )
    if resp.status_code != 200:
        raise SmokeTestError(f"Failed to create seminar: {resp.status_code} {resp.text}")
    return resp.json()


def _publish_seminar(base_url: str, seminar_id: str, session: AuthSession) -> None:
    resp = requests.post(
        f"{base_url}/studio/seminars/{seminar_id}/publish",
        headers=_auth_headers(session),
        timeout=10,
    )
    if resp.status_code == 409:
        return  # already published/scheduled – acceptable
    if resp.status_code != 200:
        raise SmokeTestError(f"Failed to publish seminar: {resp.status_code} {resp.text}")


def _mark_seminar_free(database_url: Optional[str], seminar_id: str) -> None:
    if not database_url:
        return
    try:
        with psycopg.connect(database_url, autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    update app.seminars
                    set livekit_metadata =
                      coalesce(livekit_metadata, '{}'::jsonb)
                      || jsonb_build_object('is_free', true)
                    where id = %s
                    """,
                    (seminar_id,),
                )
                if cur.rowcount == 0:
                    raise SmokeTestError("Unable to flag seminar as free for registration")
    except psycopg.Error as exc:  # pragma: no cover - best effort diagnostics
        raise SmokeTestError(f"Database seminar update failed: {exc}") from exc


def _start_session(base_url: str, seminar_id: str, session: AuthSession) -> dict:
    resp = requests.post(
        f"{base_url}/studio/seminars/{seminar_id}/sessions/start",
        json={},
        headers=_auth_headers(session),
        timeout=15,
    )
    if resp.status_code != 200:
        raise SmokeTestError(f"Failed to start session: {resp.status_code} {resp.text}")
    payload = resp.json()
    started_session = payload.get("session")
    if not started_session or started_session.get("status") != "live":
        raise SmokeTestError("Start session response missing expected live session payload")
    return started_session


def _register_participant(base_url: str, seminar_id: str, session: AuthSession) -> None:
    resp = requests.post(
        f"{base_url}/seminars/{seminar_id}/register",
        headers=_auth_headers(session),
        timeout=10,
    )
    if resp.status_code not in (200, 201):
        raise SmokeTestError(
            f"Participant registration failed: {resp.status_code} {resp.text}"
        )


def _end_session(base_url: str, seminar_id: str, seminar_session_id: str, session: AuthSession) -> dict:
    resp = requests.post(
        f"{base_url}/studio/seminars/{seminar_id}/sessions/{seminar_session_id}/end",
        json={"reason": "QA smoke complete"},
        headers=_auth_headers(session),
        timeout=10,
    )
    if resp.status_code != 200:
        raise SmokeTestError(f"Failed to end session: {resp.status_code} {resp.text}")
    payload = resp.json()
    if payload.get("status") != "ended":
        raise SmokeTestError("End session response missing ended status")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-url",
        default=_env_or_default("QA_API_BASE_URL", None, "http://localhost:8080"),
        help="Wisdom backend base URL (default: %(default)s or QA_API_BASE_URL)",
    )
    parser.add_argument(
        "--host-email",
        default=_env_or_default("QA_HOST_EMAIL", None),
        help="Host account email (default: generate random)",
    )
    parser.add_argument(
        "--host-password",
        default=_env_or_default("QA_HOST_PASSWORD", None),
        help="Host account password (default: generate random)",
    )
    parser.add_argument(
        "--participant-email",
        default=_env_or_default("QA_PARTICIPANT_EMAIL", None),
        help="Participant account email (default: generate random)",
    )
    parser.add_argument(
        "--participant-password",
        default=_env_or_default("QA_PARTICIPANT_PASSWORD", None),
        help="Participant password (default: generate random)",
    )
    parser.add_argument(
        "--database-url",
        default=_env_or_default("QA_DATABASE_URL", None),
        help="Postgres connection URL for promoting host to teacher (optional)",
    )
    parser.add_argument(
        "--mock-livekit",
        action="store_true",
        help="Start an in-process LiveKit REST mock on --mock-host/--mock-port",
    )
    parser.add_argument(
        "--mock-host",
        default="127.0.0.1",
        help="LiveKit mock bind host (default: %(default)s)",
    )
    parser.add_argument(
        "--mock-port",
        type=int,
        default=9753,
        help="LiveKit mock bind port (default: %(default)s)",
    )

    args = parser.parse_args()

    base_url = args.base_url.rstrip("/")
    host_email = args.host_email or f"host_{uuid.uuid4().hex[:8]}@qa.wisdom"
    host_password = args.host_password or f"Host-{uuid.uuid4().hex[:8]}!"
    participant_email = args.participant_email or f"participant_{uuid.uuid4().hex[:8]}@qa.wisdom"
    participant_password = args.participant_password or f"Part-{uuid.uuid4().hex[:8]}!"

    mock_server: Optional[HTTPServer] = None
    if args.mock_livekit:
        mock_server = _start_livekit_mock(args.mock_host, args.mock_port)
        print(
            f"[info] Ensure backend LIVEKIT_API_URL=http://{args.mock_host}:{args.mock_port}",
            file=sys.stderr,
        )

    try:
        print(f"[info] Ensuring host account {host_email}")
        host_session = _ensure_account(base_url, host_email, host_password, display_name="QA Host")
        try:
            _assert_teacher_role(base_url, host_session)
        except SmokeTestError:
            if not args.database_url:
                raise
            print("[info] Promoting host to teacher via database")
            _promote_teacher(args.database_url, host_session.user_id)
            _assert_teacher_role(base_url, host_session)

        print(f"[info] Host {host_email} ready as teacher")

        print(f"[info] Ensuring participant account {participant_email}")
        participant_session = _ensure_account(
            base_url, participant_email, participant_password, display_name="QA Participant"
        )

        seminar = _create_seminar(base_url, host_session)
        seminar_id = seminar["id"]
        print(f"[info] Created seminar {seminar_id}")

        _publish_seminar(base_url, seminar_id, host_session)
        print("[info] Seminar published")

        _mark_seminar_free(args.database_url, seminar_id)
        print("[info] Seminar marked as free")

        live_session = _start_session(base_url, seminar_id, host_session)
        session_id = live_session["id"]
        print(f"[info] Session started (id={session_id})")

        _register_participant(base_url, seminar_id, participant_session)
        print("[info] Participant registered successfully")

        ended_session = _end_session(base_url, seminar_id, session_id, host_session)
        print("[success] Session ended cleanly")

        print(json.dumps(
            {
                "seminar_id": seminar_id,
                "session_id": session_id,
                "host_email": host_email,
                "participant_email": participant_email,
                "session_status": ended_session["status"],
            },
            indent=2,
        ))
        return 0
    except SmokeTestError as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1
    finally:
        if mock_server:
            _stop_livekit_mock(mock_server)


if __name__ == "__main__":
    sys.exit(main())
