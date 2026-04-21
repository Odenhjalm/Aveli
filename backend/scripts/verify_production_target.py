#!/usr/bin/env python3
"""Verify the production Supabase target from runtime authority evidence.

This verifier is intentionally designed to work without raw secret disclosure.
It accepts runtime-origin URL evidence plus deployed secret digests and
classifies the target as VERIFIED (DERIVED_RUNTIME_AUTHORITY) only when the
runtime authority surfaces converge on one project ref.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


_RUNTIME_ORIGINS = frozenset(
    {
        "fly_log",
        "fly_logs",
        "runtime_env",
        "runtime_environment",
    }
)
_HEX_DIGEST_RE = re.compile(r"^[0-9a-f]{64}$")
_PROJECT_REF_RE = re.compile(r"^[a-z0-9]{6,}$")
_SUPABASE_SUFFIXES = (".supabase.co", ".supabase.com")
_USERINFO_RE = re.compile(r"^[a-z][a-z0-9+.-]*://(?P<userinfo>[^@/?#]+)@", re.I)
_HOST_AFTER_AT_RE = re.compile(r"@(?P<host>[^/:?#]+)")


def _normalize_text(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip()
    return normalized or None


def _normalize_name(value: str | None) -> str:
    return (_normalize_text(value) or "").upper()


def _normalize_origin(value: str | None) -> str:
    return (_normalize_text(value) or "").lower()


def _normalize_project_ref(value: str | None) -> str | None:
    normalized = (_normalize_text(value) or "").lower()
    if not normalized:
        return None
    if not _PROJECT_REF_RE.fullmatch(normalized):
        return None
    return normalized


def _normalize_digest(value: str | None) -> str | None:
    normalized = (_normalize_text(value) or "").lower()
    if not normalized:
        return None
    if not _HEX_DIGEST_RE.fullmatch(normalized):
        return None
    return normalized


def _safe_urlparse(value: str) -> Any:
    sanitized = re.sub(r":\[[^\]]*\]@", ":redacted@", value)
    try:
        return urlparse(sanitized)
    except ValueError:
        return None


def derive_project_ref_from_supabase_url(value: str | None) -> str | None:
    raw = _normalize_text(value)
    if raw is None:
        return None
    parsed = _safe_urlparse(raw)
    host = ((parsed.hostname if parsed else "") or "").lower()
    for suffix in _SUPABASE_SUFFIXES:
        if not host.endswith(suffix):
            continue
        label = host[: -len(suffix)]
        if not label or "." in label:
            return None
        return _normalize_project_ref(label)
    return None


def derive_project_ref_from_database_url(value: str | None) -> str | None:
    raw = _normalize_text(value)
    if raw is None:
        return None
    userinfo_match = _USERINFO_RE.match(raw)
    username = ""
    if userinfo_match:
        userinfo = userinfo_match.group("userinfo")
        username = _normalize_text(userinfo.split(":", 1)[0]) or ""
    if username.startswith("postgres."):
        return _normalize_project_ref(username.split(".", 1)[1])

    parsed = _safe_urlparse(raw)
    host = ((parsed.hostname if parsed else "") or "").lower()
    if not host:
        host_match = _HOST_AFTER_AT_RE.search(raw)
        if host_match:
            host = host_match.group("host").lower()
    for suffix in _SUPABASE_SUFFIXES:
        if host.startswith("db.") and host.endswith(suffix):
            middle = host[len("db.") : -len(suffix)]
            if middle:
                return _normalize_project_ref(middle)
        if host.endswith(suffix):
            label = host[: -len(suffix)]
            if label and "." not in label:
                return _normalize_project_ref(label)
    return None


def derive_project_ref(
    *,
    surface_name: str,
    value: str | None,
    explicit_project_ref: str | None = None,
) -> str | None:
    normalized_name = _normalize_name(surface_name)
    explicit = _normalize_project_ref(explicit_project_ref)
    if explicit is not None:
        return explicit

    if normalized_name == "SUPABASE_PROJECT_REF":
        return _normalize_project_ref(value)
    if normalized_name == "SUPABASE_URL":
        return derive_project_ref_from_supabase_url(value)
    if normalized_name in {"DATABASE_URL", "SUPABASE_DB_URL"}:
        return derive_project_ref_from_database_url(value)
    return (
        derive_project_ref_from_database_url(value)
        or derive_project_ref_from_supabase_url(value)
        or _normalize_project_ref(value)
    )


@dataclass(frozen=True)
class SurfaceObservation:
    name: str
    origin: str
    value: str | None = None
    project_ref: str | None = None

    @property
    def normalized_name(self) -> str:
        return _normalize_name(self.name)

    @property
    def normalized_origin(self) -> str:
        return _normalize_origin(self.origin)

    @property
    def is_runtime_authority(self) -> bool:
        return self.normalized_origin in _RUNTIME_ORIGINS

    @property
    def derived_project_ref(self) -> str | None:
        return derive_project_ref(
            surface_name=self.normalized_name,
            value=self.value,
            explicit_project_ref=self.project_ref,
        )

    def to_summary(self) -> dict[str, Any]:
        return {
            "name": self.normalized_name,
            "origin": self.normalized_origin,
            "project_ref": self.derived_project_ref,
            "runtime_authority": self.is_runtime_authority,
        }


@dataclass(frozen=True)
class SecretDigestObservation:
    name: str
    origin: str
    digest: str

    @property
    def normalized_name(self) -> str:
        return _normalize_name(self.name)

    @property
    def normalized_origin(self) -> str:
        return _normalize_origin(self.origin)

    @property
    def normalized_digest(self) -> str | None:
        return _normalize_digest(self.digest)

    def to_summary(self) -> dict[str, Any]:
        return {
            "name": self.normalized_name,
            "origin": self.normalized_origin,
            "digest": self.normalized_digest,
        }


def _parse_surface_observation(raw: dict[str, Any]) -> SurfaceObservation:
    return SurfaceObservation(
        name=str(raw.get("name") or ""),
        origin=str(raw.get("origin") or ""),
        value=_normalize_text(raw.get("value")),
        project_ref=_normalize_text(raw.get("project_ref")),
    )


def _parse_secret_digest_observation(raw: dict[str, Any]) -> SecretDigestObservation:
    return SecretDigestObservation(
        name=str(raw.get("name") or ""),
        origin=str(raw.get("origin") or ""),
        digest=str(raw.get("digest") or ""),
    )


def _unique(values: list[str | None]) -> list[str]:
    return sorted({value for value in values if value})


def _build_runtime_conflicts(observations: list[SurfaceObservation]) -> list[dict[str, Any]]:
    runtime_observations = [item for item in observations if item.is_runtime_authority]
    runtime_refs = _unique([item.derived_project_ref for item in runtime_observations])
    if len(runtime_refs) <= 1:
        return []

    return [
        {
            "name": item.normalized_name,
            "origin": item.normalized_origin,
            "project_ref": item.derived_project_ref,
        }
        for item in runtime_observations
        if item.derived_project_ref is not None
    ]


def _collect_digest_sets(
    observations: list[SecretDigestObservation],
) -> tuple[dict[str, list[str]], list[dict[str, Any]]]:
    digest_sets: dict[str, set[str]] = {}
    invalid: list[dict[str, Any]] = []
    for item in observations:
        normalized = item.normalized_digest
        if normalized is None:
            invalid.append(item.to_summary())
            continue
        digest_sets.setdefault(item.normalized_name, set()).add(normalized)
    return {name: sorted(values) for name, values in digest_sets.items()}, invalid


def verify_production_target(payload: dict[str, Any]) -> dict[str, Any]:
    surface_observations = [
        _parse_surface_observation(item)
        for item in payload.get("surfaces", [])
        if isinstance(item, dict)
    ]
    secret_digests = [
        _parse_secret_digest_observation(item)
        for item in payload.get("secret_digests", [])
        if isinstance(item, dict)
    ]

    runtime_database_surfaces = [
        item
        for item in surface_observations
        if item.is_runtime_authority and item.normalized_name == "DATABASE_URL"
    ]
    runtime_supabase_surfaces = [
        item
        for item in surface_observations
        if item.is_runtime_authority and item.normalized_name == "SUPABASE_URL"
    ]
    runtime_database_refs = _unique([item.derived_project_ref for item in runtime_database_surfaces])
    runtime_supabase_refs = _unique([item.derived_project_ref for item in runtime_supabase_surfaces])
    runtime_authority_refs = _unique(
        [item.derived_project_ref for item in surface_observations if item.is_runtime_authority]
    )
    runtime_conflicts = _build_runtime_conflicts(surface_observations)
    digest_sets, invalid_digests = _collect_digest_sets(secret_digests)

    database_digest_set = digest_sets.get("DATABASE_URL", [])
    supabase_db_digest_set = digest_sets.get("SUPABASE_DB_URL", [])
    digest_equality = (
        len(database_digest_set) == 1
        and database_digest_set == supabase_db_digest_set
    )

    matching_runtime_ref = None
    if len(runtime_database_refs) == 1 and runtime_database_refs == runtime_supabase_refs:
        matching_runtime_ref = runtime_database_refs[0]

    conditions = {
        "database_url_runtime_project_ref": len(runtime_database_refs) == 1,
        "supabase_url_runtime_project_ref": len(runtime_supabase_refs) == 1,
        "runtime_origin_evidence": bool(runtime_database_surfaces) and bool(runtime_supabase_surfaces),
        "database_url_and_supabase_db_url_share_deployed_digest": digest_equality,
        "no_conflicting_runtime_project_ref": len(runtime_authority_refs) == 1,
    }

    failure_codes: list[str] = []
    if not conditions["database_url_runtime_project_ref"]:
        failure_codes.append("runtime_database_url_project_ref_unverified")
    if not conditions["supabase_url_runtime_project_ref"]:
        failure_codes.append("runtime_supabase_url_project_ref_unverified")
    if not conditions["runtime_origin_evidence"]:
        failure_codes.append("runtime_authority_origin_missing")
    if not conditions["database_url_and_supabase_db_url_share_deployed_digest"]:
        failure_codes.append("deployed_digest_mismatch")
    if not conditions["no_conflicting_runtime_project_ref"]:
        failure_codes.append("conflicting_runtime_project_ref")
    if invalid_digests:
        failure_codes.append("invalid_secret_digest_evidence")

    verified = all(conditions.values()) and matching_runtime_ref is not None and not invalid_digests

    return {
        "status": "VERIFIED" if verified else "UNVERIFIED",
        "classification": "DERIVED_RUNTIME_AUTHORITY" if verified else None,
        "project_ref": matching_runtime_ref,
        "raw_secret_values_required": False,
        "blocked_forbidden_when_conditions_met": all(conditions.values()),
        "conditions": conditions,
        "failure_codes": failure_codes,
        "runtime_authority_surfaces": [
            item.to_summary() for item in surface_observations if item.is_runtime_authority
        ],
        "ignored_non_runtime_surfaces": [
            item.to_summary() for item in surface_observations if not item.is_runtime_authority
        ],
        "secret_digests": digest_sets,
        "conflicting_runtime_surfaces": runtime_conflicts,
        "invalid_secret_digests": invalid_digests,
    }


def _load_payload(path: str) -> dict[str, Any]:
    if path == "-":
        return json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Verify the production Supabase target from runtime-origin URL evidence "
            "and deployed secret digests without requiring raw secret values."
        )
    )
    parser.add_argument(
        "--evidence",
        required=True,
        help="Path to a JSON evidence file, or '-' to read JSON from stdin.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON output.",
    )
    args = parser.parse_args(argv)

    payload = _load_payload(args.evidence)
    result = verify_production_target(payload)
    json.dump(result, sys.stdout, indent=2 if args.pretty else None, sort_keys=True)
    sys.stdout.write("\n")
    return 0 if result["status"] == "VERIFIED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
