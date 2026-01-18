#!/usr/bin/env python3
"""
Provision deterministic test users into the live Supabase project.

Safety rails:
- Requires PROVISION_LIVE=1
- Validates SUPABASE_PROJECT_REF matches SUPABASE_URL
- Honors DRY_RUN=1 to skip writes while still validating inputs

Usage:
  PROVISION_LIVE=1 DRY_RUN=1 python backend/scripts/provision_test_users.py
  PROVISION_LIVE=1 python backend/scripts/provision_test_users.py
"""
from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, NoReturn

import httpx
from dotenv import dotenv_values

BACKEND_ENV_FILE = Path(os.environ.get("BACKEND_ENV_FILE", "/home/oden/Aveli/backend/.env"))
DEFAULT_PASSWORD = "Secret123!ChangeMe"
TARGET_USERS = [
    {"email": "admin@aveli.app", "role": "admin", "is_admin": True, "metadata": {"is_admin": True}},
    {"email": "ai.admin@aveli.app", "role": "admin", "is_admin": True, "metadata": {"is_admin": True, "is_ai_admin": True}},
    {"email": "teacher@aveli.app", "role": "teacher", "is_admin": False, "metadata": {"is_teacher": True}},
    {"email": "teacher2@aveli.app", "role": "teacher", "is_admin": False, "metadata": {"is_teacher": True}},
    {"email": "user.1@aveli.app", "role": "user", "is_admin": False, "metadata": {}},
    {"email": "user.2@aveli.app", "role": "user", "is_admin": False, "metadata": {}},
]

USER_ROLE_ENUM = {"user", "professional", "teacher"}
PROFILE_ROLE_ENUM = {"student", "teacher", "admin"}


@dataclass
class SummaryRow:
    email: str
    user_id: str
    role: str
    is_admin: bool
    status: str


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_env() -> Dict[str, str]:
    if not BACKEND_ENV_FILE.exists():
        die(f"Env file not found: {BACKEND_ENV_FILE}")
    env = {k: v for k, v in dotenv_values(BACKEND_ENV_FILE).items() if v is not None}
    return env


def project_ref_from_url(url: str) -> str:
    match = re.search(r"https?://([a-z0-9-]+)\.supabase\.co", url)
    if not match:
        die("SUPABASE_URL does not look like a Supabase project URL")
    return match.group(1)


def get_supabase_config(env: Dict[str, str]) -> tuple[str, str, str]:
    supabase_url = env.get("SUPABASE_URL")
    service_key = env.get("SUPABASE_SECRET_API_KEY") or env.get("SUPABASE_SERVICE_ROLE_KEY")
    project_ref_expected = env.get("SUPABASE_PROJECT_REF")
    if not supabase_url:
        die("SUPABASE_URL is missing in env")
    if not service_key:
        die("SUPABASE_SECRET_API_KEY/SUPABASE_SERVICE_ROLE_KEY is missing in env")
    if not project_ref_expected:
        die("SUPABASE_PROJECT_REF is required for safety")

    project_ref_actual = project_ref_from_url(supabase_url)
    if project_ref_actual != project_ref_expected:
        die(
            "SUPABASE_URL project ref does not match SUPABASE_PROJECT_REF; refusing to run"
        )
    return supabase_url.rstrip("/"), service_key, project_ref_actual


def build_client(base_url: str, service_key: str) -> httpx.Client:
    headers = {
        "Authorization": f"Bearer {service_key}",
        "apikey": service_key,
        "Content-Type": "application/json",
    }
    return httpx.Client(base_url=base_url, headers=headers, timeout=20.0)


def fetch_user(client: httpx.Client, email: str) -> Optional[Dict[str, Any]]:
    resp = client.get("/auth/v1/admin/users", params={"email": email})
    if resp.status_code >= 400:
        die(f"Failed to fetch user {email}: {resp.status_code} {resp.text}")
    data = resp.json()
    users: List[Dict[str, Any]]
    if isinstance(data, dict) and "users" in data:
        users = data.get("users") or []
    elif isinstance(data, list):
        users = data
    else:
        users = []
    email_lower = email.lower()
    for user in users:
        if str(user.get("email", "")).lower() == email_lower:
            return user
    return None


def create_user(
    client: httpx.Client,
    *,
    email: str,
    password: str,
    metadata: Dict[str, Any],
) -> Dict[str, Any]:
    payload = {
        "email": email,
        "password": password,
        "email_confirm": True,
        "user_metadata": metadata or {},
    }
    resp = client.post("/auth/v1/admin/users", json=payload)
    if resp.status_code not in (200, 201):
        die(f"Failed to create user {email}: {resp.status_code} {resp.text}")
    return resp.json()


def update_user(
    client: httpx.Client,
    *,
    user_id: str,
    email: str,
    password: str,
    metadata: Dict[str, Any],
) -> Dict[str, Any]:
    payload = {"password": password, "email_confirm": True}
    if metadata:
        payload["user_metadata"] = metadata
    resp = client.put(f"/auth/v1/admin/users/{user_id}", json=payload)
    if resp.status_code >= 400:
        die(f"Failed to update user {email}: {resp.status_code} {resp.text}")
    try:
        return resp.json()
    except Exception:
        return {"id": user_id}


def normalize_roles(role: str, is_admin: bool) -> tuple[str, str]:
    role_lower = role.lower()
    profile_role = "admin" if is_admin or role_lower == "admin" else "teacher" if role_lower == "teacher" else "student"
    user_role = role_lower if role_lower in USER_ROLE_ENUM else "user"
    return user_role, profile_role


def upsert_profile(
    client: httpx.Client,
    *,
    user_id: str,
    email: str,
    role: str,
    is_admin: bool,
) -> None:
    role_v2, profile_role = normalize_roles(role, is_admin)
    payload = {
        "user_id": user_id,
        "email": email,
        "role_v2": role_v2,
        "role": profile_role,
        "is_admin": is_admin,
    }
    headers = {
        "Prefer": "resolution=merge-duplicates,return=minimal",
        "Accept-Profile": "app",
        "Content-Profile": "app",
    }
    resp = client.post("/rest/v1/profiles", json=payload, headers=headers)
    if resp.status_code >= 400:
        die(f"Failed to upsert profile for {user_id}: {resp.status_code} {resp.text}")


def print_summary(rows: List[SummaryRow]) -> None:
    headers = ["email", "user_id", "role", "is_admin", "status"]
    col_widths = {h: len(h) for h in headers}
    for row in rows:
        col_widths["email"] = max(col_widths["email"], len(row.email))
        col_widths["user_id"] = max(col_widths["user_id"], len(row.user_id))
        col_widths["role"] = max(col_widths["role"], len(row.role))
        col_widths["is_admin"] = max(col_widths["is_admin"], len(str(row.is_admin)))
        col_widths["status"] = max(col_widths["status"], len(row.status))

    def fmt_row(vals: Dict[str, Any]) -> str:
        return "  ".join(str(vals[h]).ljust(col_widths[h]) for h in headers)

    print(fmt_row({h: h for h in headers}))
    print("  ".join("-" * col_widths[h] for h in headers))
    for row in rows:
        print(
            fmt_row(
                {
                    "email": row.email,
                    "user_id": row.user_id,
                    "role": row.role,
                    "is_admin": row.is_admin,
                    "status": row.status,
                }
            )
        )


def main() -> None:
    if os.environ.get("PROVISION_LIVE") != "1":
        die("Set PROVISION_LIVE=1 to run this script")
    dry_run = os.environ.get("DRY_RUN") == "1"

    env = load_env()
    supabase_url, service_key, project_ref = get_supabase_config(env)
    print(f"Target project: {project_ref} (live)")
    if dry_run:
        print("DRY_RUN=1 enabled: no writes will be performed")

    with build_client(supabase_url, service_key) as client:
        summary: List[SummaryRow] = []
        for user_def in TARGET_USERS:
            email = user_def["email"]
            role = user_def["role"]
            is_admin = bool(user_def.get("is_admin"))
            desired_metadata = {**(user_def.get("metadata") or {}), "role": role}

            existing = fetch_user(client, email)
            status = "exists" if existing else "missing"
            user_id = existing.get("id") if existing else "<pending>"

            if existing:
                if not dry_run:
                    current_meta = existing.get("user_metadata") or {}
                    merged_meta = {**current_meta, **desired_metadata}
                    update_user(
                        client,
                        user_id=existing["id"],
                        email=email,
                        password=DEFAULT_PASSWORD,
                        metadata=merged_meta,
                    )
                    status = "updated"
                else:
                    status = "exists (dry-run)"
            else:
                if dry_run:
                    status = "missing (dry-run)"
                else:
                    created = create_user(
                        client,
                        email=email,
                        password=DEFAULT_PASSWORD,
                        metadata=desired_metadata,
                    )
                    user_id = created.get("id", "<unknown>")
                    status = "created"

            if user_id != "<pending>" and not dry_run:
                upsert_profile(client, user_id=user_id, email=email, role=role, is_admin=is_admin)
                if status == "updated":
                    status = "updated/profile"
                elif status == "created":
                    status = "created/profile"

            summary.append(
                SummaryRow(
                    email=email,
                    user_id=user_id,
                    role=role,
                    is_admin=is_admin,
                    status=status,
                )
            )

    print("\nProvisioning summary:")
    print_summary(summary)


if __name__ == "__main__":
    main()
