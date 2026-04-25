#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import urlsplit

import requests

try:
    import psycopg
    from psycopg.rows import dict_row
except Exception as exc:  # pragma: no cover - surfaced in direct script usage
    raise SystemExit("psycopg is required for user snapshot backfill tooling") from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ENV_FILE = REPO_ROOT / "backend" / ".env"
DEFAULT_SNAPSHOT_DIR = REPO_ROOT / "restore" / "backup"
DEFAULT_DATABASE_URL = os.environ.get("DATABASE_URL") or ""

SNAPSHOT_SCHEMA_V1 = "aveli.production_user_stripe_audit.v1"
SNAPSHOT_SCHEMA_V2 = "aveli.production_user_stripe_audit.v2"
SUPPORTED_SNAPSHOT_SCHEMAS = frozenset({SNAPSHOT_SCHEMA_V1, SNAPSHOT_SCHEMA_V2})
PLAN_SCHEMA_V1 = "aveli.user_snapshot_backfill.plan.v1"
PLAN_HASH_ALGORITHM = "sha256_canonical_json_without_plan_meta.payload_sha256"
SNAPSHOT_HASH_ALGORITHM = "sha256_canonical_json_without_snapshot_meta.payload_sha256"
RAW_FILE_SHA256 = "sha256_raw_file_bytes"

STRIPE_API_BASE = "https://api.stripe.com/v1"
ALLOW_HOSTED_APPLY_ENV = "ALLOW_HOSTED_USER_SNAPSHOT_BACKFILL"
STATELESS_VERIFICATION_RESET_CLASS = "stateless_verification"
STATEFUL_BUSINESS_RESET_CLASS = "stateful_business"
SUPPORTED_RESET_CLASSES = frozenset(
    {STATELESS_VERIFICATION_RESET_CLASS, STATEFUL_BUSINESS_RESET_CLASS}
)
LOCAL_DATABASE_HOSTS = frozenset({"127.0.0.1", "localhost", "::1"})
PROFILE_MEDIA_SOURCE_PREFIXES = (
    ("media", "source", "profile-avatar"),
    ("media", "source", "profile-media"),
    ("media", "source", "profile"),
)
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TIMESTAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T")
REQUIRED_MEDIA_ASSET_FIELDS = (
    "media_asset_id",
    "media_type",
    "purpose",
    "original_object_path",
    "ingest_format",
    "playback_object_path",
    "playback_format",
    "state",
    "error_message",
    "processing_attempts",
    "processing_locked_at",
    "next_retry_at",
    "file_size",
    "content_hash_algorithm",
    "content_hash",
    "created_at",
    "updated_at",
    "subject_user_id",
)
MEDIA_ASSET_COLUMNS = (
    "id",
    "media_type",
    "purpose",
    "original_object_path",
    "ingest_format",
    "playback_object_path",
    "playback_format",
    "state",
    "error_message",
    "processing_attempts",
    "processing_locked_at",
    "next_retry_at",
    "file_size",
    "content_hash_algorithm",
    "content_hash",
    "created_at",
    "updated_at",
)


class UserSnapshotBackfillError(RuntimeError):
    pass


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _normalize_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise UserSnapshotBackfillError(f"{label} must be an object")
    return value


def _require_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise UserSnapshotBackfillError(f"{label} must be a list")
    return value


def _optional_uuid(value: Any, label: str) -> str | None:
    text = _normalize_text(value)
    if text is None:
        return None
    normalized = text.lower()
    if not UUID_RE.fullmatch(normalized):
        raise UserSnapshotBackfillError(f"{label} must be a UUID")
    return normalized


def _require_uuid(value: Any, label: str) -> str:
    normalized = _optional_uuid(value, label)
    if normalized is None:
        raise UserSnapshotBackfillError(f"{label} is required")
    return normalized


def _optional_bool(value: Any, label: str) -> bool | None:
    if value is None:
        return None
    if not isinstance(value, bool):
        raise UserSnapshotBackfillError(f"{label} must be a boolean")
    return value


def _require_bool(value: Any, label: str) -> bool:
    normalized = _optional_bool(value, label)
    if normalized is None:
        raise UserSnapshotBackfillError(f"{label} is required")
    return normalized


def _optional_int(value: Any, label: str) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int):
        raise UserSnapshotBackfillError(f"{label} must be an integer")
    return value


def _optional_timestamp(value: Any, label: str) -> str | None:
    text = _normalize_text(value)
    if text is None:
        return None
    if not TIMESTAMP_RE.match(text):
        raise UserSnapshotBackfillError(f"{label} must be an ISO timestamp")
    return text


def _require_timestamp(value: Any, label: str) -> str:
    normalized = _optional_timestamp(value, label)
    if normalized is None:
        raise UserSnapshotBackfillError(f"{label} is required")
    return normalized


def _optional_sha256(value: Any, label: str) -> str | None:
    text = _normalize_text(value)
    if text is None:
        return None
    normalized = text.lower()
    if not SHA256_RE.fullmatch(normalized):
        raise UserSnapshotBackfillError(f"{label} must be a lowercase SHA256 hex digest")
    return normalized


def _canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _raw_file_sha256(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _hash_excluding_field(document: dict[str, Any], *, field_path: tuple[str, ...]) -> str:
    clone = copy.deepcopy(document)
    cursor: dict[str, Any] = clone
    for key in field_path[:-1]:
        cursor = _require_mapping(cursor.get(key), ".".join(field_path[:-1]))
    cursor.pop(field_path[-1], None)
    return _sha256_bytes(_canonical_json_bytes(clone))


def _write_canonical_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _deep_sort_records(records: list[dict[str, Any]], *, primary_key: str) -> list[dict[str, Any]]:
    return sorted(records, key=lambda item: json.dumps(item.get(primary_key), sort_keys=True))


def _load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise UserSnapshotBackfillError(f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise UserSnapshotBackfillError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise UserSnapshotBackfillError(f"{path} must contain a top-level JSON object")
    return payload


def _load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        if key:
            values[key] = value
    return values


def _env_value(key: str, *, env_file: Path) -> str | None:
    current = _normalize_text(os.environ.get(key))
    if current is not None:
        return current
    return _normalize_text(_load_env_file(env_file).get(key))


def _profile_media_asset_subject(asset: dict[str, Any]) -> str | None:
    subject_user_id = _optional_uuid(asset.get("subject_user_id"), "profile_media.subject_user_id")
    if subject_user_id is not None:
        return subject_user_id
    original_object_path = _normalize_text(asset.get("original_object_path")) or ""
    parts = PurePosixPath(original_object_path.replace("\\", "/").lstrip("/")).parts
    for prefix in PROFILE_MEDIA_SOURCE_PREFIXES:
        if len(parts) <= len(prefix):
            continue
        if parts[: len(prefix)] != prefix:
            continue
        return _optional_uuid(parts[len(prefix)], "profile_media path subject")
    return None


def _snapshot_schema(payload: dict[str, Any]) -> str:
    schema = _normalize_text(payload.get("schema_version"))
    if schema not in SUPPORTED_SNAPSHOT_SCHEMAS:
        raise UserSnapshotBackfillError(
            f"unsupported snapshot schema_version {schema!r}; supported: {sorted(SUPPORTED_SNAPSHOT_SCHEMAS)}"
        )
    return str(schema)


def _verify_v2_snapshot_hash(payload: dict[str, Any]) -> None:
    snapshot_meta = _require_mapping(payload.get("snapshot_meta"), "snapshot_meta")
    algorithm = _normalize_text(snapshot_meta.get("payload_sha256_algorithm"))
    expected = _optional_sha256(snapshot_meta.get("payload_sha256"), "snapshot_meta.payload_sha256")
    if algorithm != SNAPSHOT_HASH_ALGORITHM:
        raise UserSnapshotBackfillError(
            "snapshot_meta.payload_sha256_algorithm must be "
            f"{SNAPSHOT_HASH_ALGORITHM!r} for snapshot v2"
        )
    if expected is None:
        raise UserSnapshotBackfillError("snapshot_meta.payload_sha256 is required for snapshot v2")
    actual = _hash_excluding_field(payload, field_path=("snapshot_meta", "payload_sha256"))
    if actual != expected:
        raise UserSnapshotBackfillError(
            f"snapshot v2 payload SHA mismatch: expected {expected}, got {actual}"
        )


def _normalize_auth_user(raw: dict[str, Any], *, user_id: str) -> dict[str, Any]:
    if not _require_bool(raw.get("exists"), "auth_user.exists"):
        raise UserSnapshotBackfillError(f"auth_user.exists must be true for user {user_id}")
    normalized_user_id = _require_uuid(raw.get("user_id"), "auth_user.user_id")
    if normalized_user_id != user_id:
        raise UserSnapshotBackfillError("auth_user.user_id must equal user.user_id")
    return {
        "user_id": user_id,
        "email": _normalize_text(raw.get("email")),
        "created_at": _optional_timestamp(raw.get("created_at"), "auth_user.created_at"),
        "last_sign_in_at": _optional_timestamp(raw.get("last_sign_in_at"), "auth_user.last_sign_in_at"),
    }


def _normalize_auth_subject(
    raw: dict[str, Any],
    *,
    user_id: str,
    auth_user: dict[str, Any],
    snapshot_captured_at: str,
) -> dict[str, Any]:
    exists = _require_bool(raw.get("exists"), "auth_subject.exists")
    if exists:
        normalized_user_id = _require_uuid(raw.get("user_id"), "auth_subject.user_id")
        if normalized_user_id != user_id:
            raise UserSnapshotBackfillError("auth_subject.user_id must equal user.user_id")
        return {
            "user_id": user_id,
            "email": _normalize_text(raw.get("email")) or auth_user.get("email"),
            "role": _normalize_text(raw.get("role")) or "learner",
            "onboarding_state": _normalize_text(raw.get("onboarding_state")) or "incomplete",
            "created_at": _require_timestamp(raw.get("created_at"), "auth_subject.created_at"),
            "updated_at": _require_timestamp(raw.get("updated_at"), "auth_subject.updated_at"),
            "derived": False,
        }
    anchor = auth_user.get("created_at") or snapshot_captured_at
    return {
        "user_id": user_id,
        "email": auth_user.get("email"),
        "role": "learner",
        "onboarding_state": "incomplete",
        "created_at": anchor,
        "updated_at": anchor,
        "derived": True,
    }


def _normalize_profile(
    raw: dict[str, Any],
    *,
    user_id: str,
    auth_user: dict[str, Any],
    snapshot_captured_at: str,
) -> dict[str, Any]:
    exists = _require_bool(raw.get("exists"), "profile.exists")
    if exists:
        normalized_user_id = _require_uuid(raw.get("user_id"), "profile.user_id")
        if normalized_user_id != user_id:
            raise UserSnapshotBackfillError("profile.user_id must equal user.user_id")
        return {
            "user_id": user_id,
            "display_name": _normalize_text(raw.get("display_name")),
            "bio": _normalize_text(raw.get("bio")),
            "avatar_media_id": _optional_uuid(raw.get("avatar_media_id"), "profile.avatar_media_id"),
            "avatar_url": _normalize_text(raw.get("avatar_url")),
            "created_at": _require_timestamp(raw.get("created_at"), "profile.created_at"),
            "updated_at": _require_timestamp(raw.get("updated_at"), "profile.updated_at"),
            "derived": False,
        }
    anchor = auth_user.get("created_at") or snapshot_captured_at
    return {
        "user_id": user_id,
        "display_name": None,
        "bio": None,
        "avatar_media_id": None,
        "avatar_url": None,
        "created_at": anchor,
        "updated_at": anchor,
        "derived": True,
    }


def _normalize_profile_media_asset(
    raw: dict[str, Any],
    *,
    user_id: str,
    snapshot_schema: str,
) -> dict[str, Any]:
    if snapshot_schema != SNAPSHOT_SCHEMA_V2:
        missing = [field for field in REQUIRED_MEDIA_ASSET_FIELDS if field not in raw]
        raise UserSnapshotBackfillError(
            "snapshot v1 cannot restore app.media_assets deterministically; "
            "re-export with snapshot v2. Missing media identity fields: "
            + ", ".join(missing)
        )

    asset = {
        "id": _require_uuid(raw.get("media_asset_id"), "profile_media.media_asset_id"),
        "media_type": _normalize_text(raw.get("media_type")),
        "purpose": _normalize_text(raw.get("purpose")),
        "original_object_path": _normalize_text(raw.get("original_object_path")),
        "ingest_format": _normalize_text(raw.get("ingest_format")),
        "playback_object_path": _normalize_text(raw.get("playback_object_path")),
        "playback_format": _normalize_text(raw.get("playback_format")),
        "state": _normalize_text(raw.get("state")),
        "error_message": _normalize_text(raw.get("error_message")),
        "processing_attempts": _optional_int(raw.get("processing_attempts"), "profile_media.processing_attempts") or 0,
        "processing_locked_at": _optional_timestamp(raw.get("processing_locked_at"), "profile_media.processing_locked_at"),
        "next_retry_at": _optional_timestamp(raw.get("next_retry_at"), "profile_media.next_retry_at"),
        "file_size": _optional_int(raw.get("file_size"), "profile_media.file_size"),
        "content_hash_algorithm": _normalize_text(raw.get("content_hash_algorithm")),
        "content_hash": _optional_sha256(raw.get("content_hash"), "profile_media.content_hash"),
        "created_at": _require_timestamp(raw.get("created_at"), "profile_media.created_at"),
        "updated_at": _require_timestamp(raw.get("updated_at"), "profile_media.updated_at"),
    }
    if asset["file_size"] is None:
        raise UserSnapshotBackfillError("profile_media.file_size is required")
    if asset["content_hash_algorithm"] != "sha256":
        raise UserSnapshotBackfillError("profile_media.content_hash_algorithm must be sha256")
    if asset["content_hash"] is None:
        raise UserSnapshotBackfillError("profile_media.content_hash is required")
    subject_user_id = _profile_media_asset_subject(raw)
    if subject_user_id is None:
        raise UserSnapshotBackfillError(
            f"profile media asset {asset['id']} is missing a deterministic subject_user_id binding"
        )
    if subject_user_id != user_id:
        raise UserSnapshotBackfillError(
            f"profile media asset {asset['id']} belongs to {subject_user_id}, expected {user_id}"
        )
    return asset


def _normalize_profile_media_placement(raw: dict[str, Any], *, user_id: str) -> dict[str, Any]:
    subject_user_id = _require_uuid(raw.get("subject_user_id"), "profile_media.placement.subject_user_id")
    if subject_user_id != user_id:
        raise UserSnapshotBackfillError("profile_media placement subject_user_id must equal user.user_id")
    return {
        "id": _require_uuid(raw.get("id"), "profile_media.placement.id"),
        "subject_user_id": subject_user_id,
        "media_asset_id": _require_uuid(raw.get("media_asset_id"), "profile_media.placement.media_asset_id"),
        "visibility": _normalize_text(raw.get("visibility")),
        "created_at": _require_timestamp(raw.get("created_at"), "profile_media.placement.created_at"),
        "updated_at": _require_timestamp(raw.get("updated_at"), "profile_media.placement.updated_at"),
    }


def _normalize_membership(raw: dict[str, Any], *, user_id: str) -> dict[str, Any]:
    membership_user_id = _require_uuid(raw.get("user_id"), "membership.user_id")
    if membership_user_id != user_id:
        raise UserSnapshotBackfillError("membership.user_id must equal user.user_id")
    return {
        "membership_id": _require_uuid(raw.get("membership_id"), "membership.membership_id"),
        "user_id": membership_user_id,
        "status": _normalize_text(raw.get("status")),
        "source": _normalize_text(raw.get("source")),
        "effective_at": _optional_timestamp(raw.get("effective_at"), "membership.effective_at"),
        "expires_at": _optional_timestamp(raw.get("expires_at"), "membership.expires_at"),
        "canceled_at": _optional_timestamp(raw.get("canceled_at"), "membership.canceled_at"),
        "ended_at": _optional_timestamp(raw.get("ended_at"), "membership.ended_at"),
        "provider_customer_id": _normalize_text(raw.get("provider_customer_id")),
        "provider_subscription_id": _normalize_text(raw.get("provider_subscription_id")),
        "created_at": _require_timestamp(raw.get("created_at"), "membership.created_at"),
        "updated_at": _require_timestamp(raw.get("updated_at"), "membership.updated_at"),
    }


def _normalize_referral(raw: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": _require_uuid(raw.get("id"), "referral.id"),
        "code": _normalize_text(raw.get("code")),
        "teacher_id": _require_uuid(raw.get("teacher_id"), "referral.teacher_id"),
        "email": _normalize_text(raw.get("email")),
        "free_days": _optional_int(raw.get("free_days"), "referral.free_days"),
        "free_months": _optional_int(raw.get("free_months"), "referral.free_months"),
        "active": _require_bool(raw.get("active"), "referral.active"),
        "redeemed_by_user_id": _optional_uuid(raw.get("redeemed_by_user_id"), "referral.redeemed_by_user_id"),
        "redeemed_at": _optional_timestamp(raw.get("redeemed_at"), "referral.redeemed_at"),
        "created_at": _require_timestamp(raw.get("created_at"), "referral.created_at"),
        "updated_at": _require_timestamp(raw.get("updated_at"), "referral.updated_at"),
    }


def _normalize_course(raw: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": _require_uuid(raw.get("course_id") or raw.get("id"), "course.id"),
        "teacher_id": _require_uuid(raw.get("teacher_id"), "course.teacher_id"),
        "title": _normalize_text(raw.get("title")),
        "slug": _normalize_text(raw.get("slug")),
        "course_group_id": _require_uuid(raw.get("course_group_id"), "course.course_group_id"),
        "group_position": _optional_int(raw.get("group_position"), "course.group_position"),
        "visibility": _normalize_text(raw.get("visibility")),
        "content_ready": _require_bool(raw.get("content_ready"), "course.content_ready"),
        "price_amount_cents": _optional_int(raw.get("price_amount_cents"), "course.price_amount_cents"),
        "stripe_product_id": _normalize_text(raw.get("stripe_product_id")),
        "active_stripe_price_id": _normalize_text(raw.get("active_stripe_price_id")),
        "sellable": _require_bool(raw.get("sellable"), "course.sellable"),
        "drip_enabled": _require_bool(raw.get("drip_enabled"), "course.drip_enabled"),
        "drip_interval_days": _optional_int(raw.get("drip_interval_days"), "course.drip_interval_days"),
        "cover_media_id": _optional_uuid(raw.get("cover_media_id"), "course.cover_media_id"),
        "created_at": _require_timestamp(raw.get("created_at"), "course.created_at"),
        "updated_at": _require_timestamp(raw.get("updated_at"), "course.updated_at"),
    }


def _normalize_course_enrollment(raw: dict[str, Any], *, user_id: str) -> dict[str, Any]:
    enrollment_user_id = _require_uuid(raw.get("user_id"), "course_enrollment.user_id")
    if enrollment_user_id != user_id:
        raise UserSnapshotBackfillError("course_enrollment.user_id must equal user.user_id")
    return {
        "id": _require_uuid(raw.get("enrollment_id") or raw.get("id"), "course_enrollment.id"),
        "user_id": enrollment_user_id,
        "course_id": _require_uuid(raw.get("course_id"), "course_enrollment.course_id"),
        "source": _normalize_text(raw.get("source")),
        "granted_at": _require_timestamp(raw.get("granted_at"), "course_enrollment.granted_at"),
        "drip_started_at": _require_timestamp(raw.get("drip_started_at"), "course_enrollment.drip_started_at"),
        "current_unlock_position": _optional_int(
            raw.get("current_unlock_position"), "course_enrollment.current_unlock_position"
        ),
        "created_at": _require_timestamp(raw.get("created_at"), "course_enrollment.created_at"),
        "updated_at": _require_timestamp(raw.get("updated_at"), "course_enrollment.updated_at"),
    }


def _compile_plan(snapshot_path: Path) -> dict[str, Any]:
    snapshot = _load_json(snapshot_path)
    snapshot_schema = _snapshot_schema(snapshot)
    if snapshot_schema == SNAPSHOT_SCHEMA_V2:
        _verify_v2_snapshot_hash(snapshot)

    snapshot_meta = _require_mapping(snapshot.get("snapshot_meta"), "snapshot_meta")
    coverage = _require_mapping(snapshot_meta.get("coverage"), "snapshot_meta.coverage")
    captured_at = _require_timestamp(snapshot_meta.get("captured_at_utc"), "snapshot_meta.captured_at_utc")

    auth_subject_rows: dict[str, dict[str, Any]] = {}
    profile_rows: dict[str, dict[str, Any]] = {}
    media_asset_rows: dict[str, dict[str, Any]] = {}
    profile_media_placement_rows: dict[str, dict[str, Any]] = {}
    membership_rows: dict[str, dict[str, Any]] = {}
    stripe_customer_rows: dict[str, dict[str, Any]] = {}
    referral_rows: dict[str, dict[str, Any]] = {}
    course_rows: dict[str, dict[str, Any]] = {}
    course_enrollment_rows: dict[str, dict[str, Any]] = {}
    derived_defaults: list[dict[str, Any]] = []
    user_inventory: list[dict[str, Any]] = []

    for raw_user in _require_list(snapshot.get("users"), "users"):
        user = _require_mapping(raw_user, "user")
        user_id = _require_uuid(user.get("user_id"), "user.user_id")
        auth_user = _normalize_auth_user(_require_mapping(user.get("auth_user"), "auth_user"), user_id=user_id)
        auth_subject = _normalize_auth_subject(
            _require_mapping(user.get("auth_subject"), "auth_subject"),
            user_id=user_id,
            auth_user=auth_user,
            snapshot_captured_at=captured_at,
        )
        profile = _normalize_profile(
            _require_mapping(user.get("profile"), "profile"),
            user_id=user_id,
            auth_user=auth_user,
            snapshot_captured_at=captured_at,
        )

        auth_subject_rows[user_id] = auth_subject
        profile_rows[user_id] = profile
        user_inventory.append(auth_user)
        if auth_subject["derived"]:
            derived_defaults.append({"user_id": user_id, "table": "app.auth_subjects"})
        if profile["derived"]:
            derived_defaults.append({"user_id": user_id, "table": "app.profiles"})

        profile_media = _require_mapping(user.get("profile_media"), "profile_media")
        for raw_asset in _require_list(profile_media.get("owned_assets"), "profile_media.owned_assets"):
            asset = _normalize_profile_media_asset(
                _require_mapping(raw_asset, "profile_media.owned_asset"),
                user_id=user_id,
                snapshot_schema=snapshot_schema,
            )
            existing_asset = media_asset_rows.get(asset["id"])
            if existing_asset is not None and existing_asset != asset:
                raise UserSnapshotBackfillError(f"media asset {asset['id']} has conflicting snapshot rows")
            media_asset_rows[asset["id"]] = asset
        for raw_placement in _require_list(profile_media.get("placements"), "profile_media.placements"):
            placement = _normalize_profile_media_placement(
                _require_mapping(raw_placement, "profile_media.placement"),
                user_id=user_id,
            )
            profile_media_placement_rows[placement["id"]] = placement

        memberships = _require_list(user.get("memberships"), "memberships")
        if len(memberships) > 1:
            raise UserSnapshotBackfillError("app.memberships is canonical single-row-per-user authority")
        for raw_membership in memberships:
            membership = _normalize_membership(
                _require_mapping(raw_membership, "membership"),
                user_id=user_id,
            )
            membership_rows[user_id] = membership

        stripe = _require_mapping(user.get("stripe_membership_data"), "stripe_membership_data")
        stripe_product_id = _normalize_text(stripe.get("stripe_product_id"))
        active_stripe_price_id = _normalize_text(stripe.get("active_stripe_price_id"))
        sellable = _require_bool(stripe.get("sellable"), "stripe_membership_data.sellable")
        stripe_customer_id = _normalize_text(stripe.get("stripe_customer_id"))
        if stripe_customer_id is not None:
            stripe_customer_rows[user_id] = {
                "user_id": user_id,
                "customer_id": stripe_customer_id,
            }
        for raw_referral in _require_list(
            _require_mapping(user.get("referrals"), "referrals").get("created"),
            "referrals.created",
        ):
            referral = _normalize_referral(_require_mapping(raw_referral, "referral"))
            referral_rows[referral["id"]] = referral
        for raw_referral in _require_list(
            _require_mapping(user.get("referrals"), "referrals").get("redeemed"),
            "referrals.redeemed",
        ):
            referral = _normalize_referral(_require_mapping(raw_referral, "referral"))
            referral_rows[referral["id"]] = referral

        course_associations = _require_mapping(user.get("course_associations"), "course_associations")
        for raw_course in _require_list(course_associations.get("authored_courses"), "course_associations.authored_courses"):
            course = _normalize_course(_require_mapping(raw_course, "authored_course"))
            course_rows[course["id"]] = course
        for raw_enrollment in _require_list(course_associations.get("enrollments"), "course_associations.enrollments"):
            enrollment = _normalize_course_enrollment(
                _require_mapping(raw_enrollment, "course_enrollment"),
                user_id=user_id,
            )
            course_enrollment_rows[enrollment["id"]] = enrollment

        for raw_avatar in (
            _require_mapping(user.get("profile"), "profile").get("avatar_media"),
            _require_mapping(user.get("profile"), "profile").get("avatar_media"),
        ):
            del raw_avatar

        if profile["avatar_media_id"] is not None and profile["avatar_media_id"] not in media_asset_rows:
            for placement in profile_media_placement_rows.values():
                if placement["media_asset_id"] == profile["avatar_media_id"] and placement["subject_user_id"] == user_id:
                    break
            else:
                raise UserSnapshotBackfillError(
                    f"profile avatar_media_id {profile['avatar_media_id']} is not backed by owned asset/placement data"
                )

        user_inventory[-1]["stripe_expectation"] = {
            "stripe_product_id": stripe_product_id,
            "active_stripe_price_id": active_stripe_price_id,
            "sellable": sellable,
            "stripe_customer_id": stripe_customer_id,
            "stripe_subscription_id": _normalize_text(stripe.get("stripe_subscription_id")),
            "db_provider_customer_id": _normalize_text(stripe.get("db_provider_customer_id")),
            "db_provider_subscription_id": _normalize_text(stripe.get("db_provider_subscription_id")),
        }

    from backend.bootstrap import baseline_v2

    schema_verification = baseline_v2.verify_v2_lock()["schema_verification"]  # type: ignore[index]
    expected_schema_hash = str(schema_verification["expected_schema_hash"])

    plan: dict[str, Any] = {
        "plan_schema": PLAN_SCHEMA_V1,
        "plan_meta": {
            "created_from_snapshot": snapshot_path.name,
            "source_snapshot_path": str(snapshot_path),
            "source_snapshot_schema": snapshot_schema,
            "source_snapshot_raw_sha256": _raw_file_sha256(snapshot_path),
            "source_snapshot_raw_sha256_algorithm": RAW_FILE_SHA256,
            "source_snapshot_payload_sha256": _normalize_text(snapshot_meta.get("payload_sha256")),
            "source_snapshot_stored_canonical_sha256": _normalize_text(snapshot_meta.get("canonical_sha256")),
            "baseline_expected_schema_hash": expected_schema_hash,
            "baseline_hash_source": "backend/supabase/baseline_v2_slots.lock.json",
            "payload_sha256_algorithm": PLAN_HASH_ALGORITHM,
            "payload_sha256": None,
        },
        "coverage": coverage,
        "derived_defaults": sorted(
            derived_defaults,
            key=lambda item: (str(item["table"]), str(item["user_id"])),
        ),
        "user_inventory": sorted(user_inventory, key=lambda item: str(item["user_id"])),
        "tables": {
            "auth_subjects": sorted(auth_subject_rows.values(), key=lambda item: item["user_id"]),
            "profiles": sorted(profile_rows.values(), key=lambda item: item["user_id"]),
            "media_assets": sorted(media_asset_rows.values(), key=lambda item: item["id"]),
            "profile_media_placements": sorted(
                profile_media_placement_rows.values(),
                key=lambda item: (item["subject_user_id"], item["id"]),
            ),
            "memberships": sorted(membership_rows.values(), key=lambda item: item["user_id"]),
            "stripe_customers": sorted(stripe_customer_rows.values(), key=lambda item: item["user_id"]),
            "referral_codes": sorted(referral_rows.values(), key=lambda item: item["id"]),
            "courses": sorted(course_rows.values(), key=lambda item: item["id"]),
            "course_enrollments": sorted(course_enrollment_rows.values(), key=lambda item: item["id"]),
        },
        "verification_expectations": {
            "all_auth_users_have_auth_subjects": True,
            "all_auth_users_have_profiles": True,
            "baseline_schema_hash": expected_schema_hash,
            "table_counts": {
                "auth_subjects": len(auth_subject_rows),
                "profiles": len(profile_rows),
                "media_assets": len(media_asset_rows),
                "profile_media_placements": len(profile_media_placement_rows),
                "memberships": len(membership_rows),
                "stripe_customers": len(stripe_customer_rows),
                "referral_codes": len(referral_rows),
                "courses": len(course_rows),
                "course_enrollments": len(course_enrollment_rows),
            },
        },
    }
    plan["plan_meta"]["payload_sha256"] = _hash_excluding_field(
        plan,
        field_path=("plan_meta", "payload_sha256"),
    )
    return plan


def _strip_plan_compare(record: dict[str, Any]) -> dict[str, Any]:
    sanitized = dict(record)
    sanitized.pop("derived", None)
    return sanitized


def _fetchall(conn: psycopg.Connection, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return [dict(row) for row in cur.fetchall()]


def _fetchone(conn: psycopg.Connection, sql: str, params: tuple[Any, ...] = ()) -> dict[str, Any] | None:
    rows = _fetchall(conn, sql, params)
    return rows[0] if rows else None


def _parsed_db_url(database_url: str):
    parsed = urlsplit(database_url)
    if parsed.scheme not in {"postgresql", "postgres"}:
        raise UserSnapshotBackfillError("database URL must use the PostgreSQL scheme")
    if not parsed.hostname:
        raise UserSnapshotBackfillError("database URL must include a hostname")
    return parsed


def _require_apply_target(database_url: str) -> str:
    parsed = _parsed_db_url(database_url)
    hostname = str(parsed.hostname).lower()
    if hostname in LOCAL_DATABASE_HOSTS:
        return "local"
    if str(os.environ.get(ALLOW_HOSTED_APPLY_ENV) or "").strip() != "1":
        raise UserSnapshotBackfillError(
            f"hosted apply requires {ALLOW_HOSTED_APPLY_ENV}=1"
        )
    reset_class = str(os.environ.get("BASELINE_RESET_CLASS") or "").strip().lower()
    if reset_class not in SUPPORTED_RESET_CLASSES:
        raise UserSnapshotBackfillError(
            "hosted apply requires BASELINE_RESET_CLASS to be one of "
            f"{sorted(SUPPORTED_RESET_CLASSES)}"
        )
    return "hosted"


def _verify_plan_payload_hash(plan: dict[str, Any]) -> None:
    plan_meta = _require_mapping(plan.get("plan_meta"), "plan_meta")
    algorithm = _normalize_text(plan_meta.get("payload_sha256_algorithm"))
    expected = _optional_sha256(plan_meta.get("payload_sha256"), "plan_meta.payload_sha256")
    if algorithm != PLAN_HASH_ALGORITHM:
        raise UserSnapshotBackfillError(
            f"plan_meta.payload_sha256_algorithm must be {PLAN_HASH_ALGORITHM!r}"
        )
    if expected is None:
        raise UserSnapshotBackfillError("plan_meta.payload_sha256 is required")
    actual = _hash_excluding_field(plan, field_path=("plan_meta", "payload_sha256"))
    if actual != expected:
        raise UserSnapshotBackfillError(
            f"plan payload SHA mismatch: expected {expected}, got {actual}"
        )


def _verify_plan_source_snapshot(plan: dict[str, Any]) -> dict[str, Any]:
    plan_meta = _require_mapping(plan.get("plan_meta"), "plan_meta")
    snapshot_path = Path(str(plan_meta.get("source_snapshot_path") or ""))
    expected_raw_sha = _optional_sha256(plan_meta.get("source_snapshot_raw_sha256"), "plan_meta.source_snapshot_raw_sha256")
    if not snapshot_path.is_file():
        raise UserSnapshotBackfillError(f"source snapshot does not exist: {snapshot_path}")
    if expected_raw_sha is None:
        raise UserSnapshotBackfillError("plan_meta.source_snapshot_raw_sha256 is required")
    actual_raw_sha = _raw_file_sha256(snapshot_path)
    if actual_raw_sha != expected_raw_sha:
        raise UserSnapshotBackfillError(
            f"source snapshot raw SHA mismatch: expected {expected_raw_sha}, got {actual_raw_sha}"
        )
    snapshot = _load_json(snapshot_path)
    schema = _snapshot_schema(snapshot)
    expected_schema = _normalize_text(plan_meta.get("source_snapshot_schema"))
    if schema != expected_schema:
        raise UserSnapshotBackfillError(
            f"source snapshot schema mismatch: expected {expected_schema}, got {schema}"
        )
    if schema == SNAPSHOT_SCHEMA_V2:
        _verify_v2_snapshot_hash(snapshot)
    return snapshot


def _stripe_request(secret_key: str, resource: str, object_id: str) -> dict[str, Any]:
    response = requests.get(
        f"{STRIPE_API_BASE}/{resource}/{object_id}",
        auth=(secret_key, ""),
        timeout=20,
    )
    if response.status_code >= 400:
        raise UserSnapshotBackfillError(
            f"Stripe {resource}/{object_id} failed with HTTP {response.status_code}: {response.text[:200]}"
        )
    payload = response.json()
    if not isinstance(payload, dict):
        raise UserSnapshotBackfillError(f"Stripe {resource}/{object_id} returned a non-object payload")
    return payload


def _live_membership_catalog(env_file: Path) -> dict[str, Any] | None:
    secret_key = _env_value("STRIPE_SECRET_KEY", env_file=env_file)
    product_id = _env_value("STRIPE_MEMBERSHIP_PRODUCT_ID", env_file=env_file)
    monthly_price_id = _env_value("STRIPE_PRICE_MONTHLY", env_file=env_file)
    yearly_price_id = _env_value("STRIPE_PRICE_YEARLY", env_file=env_file)
    if not secret_key or not product_id or not monthly_price_id or not yearly_price_id:
        return None
    product = _stripe_request(secret_key, "products", product_id)
    monthly = _stripe_request(secret_key, "prices", monthly_price_id)
    yearly = _stripe_request(secret_key, "prices", yearly_price_id)
    sellable = bool(
        product.get("active")
        and monthly.get("active")
        and yearly.get("active")
        and str(monthly.get("product") or "") == product_id
        and str(yearly.get("product") or "") == product_id
    )
    return {
        "membership_product": {
            "id": str(product.get("id") or ""),
            "active": bool(product.get("active")),
            "default_price": _normalize_text(product.get("default_price")),
            "name": _normalize_text(product.get("name")),
            "description": _normalize_text(product.get("description")),
            "livemode": bool(product.get("livemode")),
            "updated": product.get("updated"),
        },
        "configured_prices": {
            "monthly": {
                "id": str(monthly.get("id") or ""),
                "active": bool(monthly.get("active")),
                "product": _normalize_text(monthly.get("product")),
                "currency": _normalize_text(monthly.get("currency")),
                "unit_amount": monthly.get("unit_amount"),
                "livemode": bool(monthly.get("livemode")),
                "type": _normalize_text(monthly.get("type")),
                "recurring": monthly.get("recurring"),
            },
            "yearly": {
                "id": str(yearly.get("id") or ""),
                "active": bool(yearly.get("active")),
                "product": _normalize_text(yearly.get("product")),
                "currency": _normalize_text(yearly.get("currency")),
                "unit_amount": yearly.get("unit_amount"),
                "livemode": bool(yearly.get("livemode")),
                "type": _normalize_text(yearly.get("type")),
                "recurring": yearly.get("recurring"),
            },
        },
        "sellable": sellable,
        "mode": "live" if bool(product.get("livemode")) else "test",
        "retrieved_at_utc": _utcnow(),
    }


def _query_rows_by_ids(
    conn: psycopg.Connection,
    *,
    table: str,
    id_column: str,
    ids: list[str],
    select_sql: str,
) -> list[dict[str, Any]]:
    if not ids:
        return []
    return _fetchall(
        conn,
        f"""
        select {select_sql}
          from {table}
         where {id_column} = any(%s::uuid[])
         order by {id_column}
        """,
        (ids,),
    )


def _ensure_auth_users_exist(conn: psycopg.Connection, user_ids: list[str]) -> None:
    rows = _fetchall(
        conn,
        """
        select id::text as user_id
          from auth.users
         where id = any(%s::uuid[])
         order by id::text
        """,
        (user_ids,),
    )
    existing = {str(row["user_id"]) for row in rows}
    missing = sorted(set(user_ids) - existing)
    if missing:
        raise UserSnapshotBackfillError(f"auth.users is missing snapshot users: {missing}")


def _upsert_auth_subjects(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                insert into app.auth_subjects (
                  user_id,
                  email,
                  role,
                  onboarding_state,
                  created_at,
                  updated_at
                )
                values (%s::uuid, %s, %s::app.auth_subject_role, %s::app.onboarding_state, %s::timestamptz, %s::timestamptz)
                on conflict (user_id) do update
                   set email = excluded.email,
                       role = excluded.role,
                       onboarding_state = excluded.onboarding_state,
                       created_at = excluded.created_at,
                       updated_at = excluded.updated_at
                """,
                (
                    row["user_id"],
                    row["email"],
                    row["role"],
                    row["onboarding_state"],
                    row["created_at"],
                    row["updated_at"],
                ),
            )


def _insert_or_verify_media_assets(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> dict[str, int]:
    inserted = 0
    verified = 0
    with conn.cursor(row_factory=dict_row) as cur:
        for row in rows:
            cur.execute(
                f"""
                select {", ".join(MEDIA_ASSET_COLUMNS)}
                  from app.media_assets
                 where id = %s::uuid
                 limit 1
                """,
                (row["id"],),
            )
            existing = cur.fetchone()
            if existing is None:
                cur.execute(
                    """
                    insert into app.media_assets (
                      id,
                      media_type,
                      purpose,
                      original_object_path,
                      ingest_format,
                      playback_object_path,
                      playback_format,
                      state,
                      error_message,
                      processing_attempts,
                      processing_locked_at,
                      next_retry_at,
                      file_size,
                      content_hash_algorithm,
                      content_hash,
                      created_at,
                      updated_at
                    )
                    values (
                      %s::uuid,
                      %s::app.media_type,
                      %s::app.media_purpose,
                      %s,
                      %s,
                      %s,
                      %s,
                      %s::app.media_state,
                      %s,
                      %s,
                      %s::timestamptz,
                      %s::timestamptz,
                      %s,
                      %s,
                      %s,
                      %s::timestamptz,
                      %s::timestamptz
                    )
                    """,
                    (
                        row["id"],
                        row["media_type"],
                        row["purpose"],
                        row["original_object_path"],
                        row["ingest_format"],
                        row["playback_object_path"],
                        row["playback_format"],
                        row["state"],
                        row["error_message"],
                        row["processing_attempts"],
                        row["processing_locked_at"],
                        row["next_retry_at"],
                        row["file_size"],
                        row["content_hash_algorithm"],
                        row["content_hash"],
                        row["created_at"],
                        row["updated_at"],
                    ),
                )
                inserted += 1
                continue
            actual = dict(existing)
            expected = {key: row[key] for key in MEDIA_ASSET_COLUMNS}
            if actual != expected:
                raise UserSnapshotBackfillError(
                    f"media asset {row['id']} already exists but differs from snapshot; "
                    "canonical backfill refuses to mutate existing media identity/lifecycle rows"
                )
            verified += 1
    return {"inserted": inserted, "verified_existing": verified}


def _upsert_profiles(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                insert into app.profiles (
                  user_id,
                  display_name,
                  bio,
                  avatar_media_id,
                  created_at,
                  updated_at
                )
                values (%s::uuid, %s, %s, %s::uuid, %s::timestamptz, %s::timestamptz)
                on conflict (user_id) do update
                   set display_name = excluded.display_name,
                       bio = excluded.bio,
                       avatar_media_id = excluded.avatar_media_id,
                       created_at = excluded.created_at,
                       updated_at = excluded.updated_at
                """,
                (
                    row["user_id"],
                    row["display_name"],
                    row["bio"],
                    row["avatar_media_id"],
                    row["created_at"],
                    row["updated_at"],
                ),
            )


def _upsert_profile_media_placements(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                insert into app.profile_media_placements (
                  id,
                  subject_user_id,
                  media_asset_id,
                  visibility,
                  created_at,
                  updated_at
                )
                values (%s::uuid, %s::uuid, %s::uuid, %s::app.profile_media_visibility, %s::timestamptz, %s::timestamptz)
                on conflict (id) do update
                   set subject_user_id = excluded.subject_user_id,
                       media_asset_id = excluded.media_asset_id,
                       visibility = excluded.visibility,
                       created_at = excluded.created_at,
                       updated_at = excluded.updated_at
                """,
                (
                    row["id"],
                    row["subject_user_id"],
                    row["media_asset_id"],
                    row["visibility"],
                    row["created_at"],
                    row["updated_at"],
                ),
            )


def _upsert_memberships(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                insert into app.memberships (
                  membership_id,
                  user_id,
                  status,
                  source,
                  effective_at,
                  expires_at,
                  canceled_at,
                  ended_at,
                  provider_customer_id,
                  provider_subscription_id,
                  created_at,
                  updated_at
                )
                values (
                  %s::uuid,
                  %s::uuid,
                  %s::app.membership_status,
                  %s::app.membership_source,
                  %s::timestamptz,
                  %s::timestamptz,
                  %s::timestamptz,
                  %s::timestamptz,
                  %s,
                  %s,
                  %s::timestamptz,
                  %s::timestamptz
                )
                on conflict (user_id) do update
                   set membership_id = excluded.membership_id,
                       status = excluded.status,
                       source = excluded.source,
                       effective_at = excluded.effective_at,
                       expires_at = excluded.expires_at,
                       canceled_at = excluded.canceled_at,
                       ended_at = excluded.ended_at,
                       provider_customer_id = excluded.provider_customer_id,
                       provider_subscription_id = excluded.provider_subscription_id,
                       created_at = excluded.created_at,
                       updated_at = excluded.updated_at
                """,
                (
                    row["membership_id"],
                    row["user_id"],
                    row["status"],
                    row["source"],
                    row["effective_at"],
                    row["expires_at"],
                    row["canceled_at"],
                    row["ended_at"],
                    row["provider_customer_id"],
                    row["provider_subscription_id"],
                    row["created_at"],
                    row["updated_at"],
                ),
            )


def _upsert_stripe_customers(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                insert into app.stripe_customers (user_id, customer_id, created_at, updated_at)
                values (%s::uuid, %s, now(), now())
                on conflict (user_id) do update
                   set customer_id = excluded.customer_id,
                       updated_at = now()
                """,
                (row["user_id"], row["customer_id"]),
            )


def _upsert_referral_codes(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                insert into app.referral_codes (
                  id,
                  code,
                  teacher_id,
                  email,
                  free_days,
                  free_months,
                  active,
                  redeemed_by_user_id,
                  redeemed_at,
                  created_at,
                  updated_at
                )
                values (
                  %s::uuid,
                  %s,
                  %s::uuid,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s::uuid,
                  %s::timestamptz,
                  %s::timestamptz,
                  %s::timestamptz
                )
                on conflict (id) do update
                   set code = excluded.code,
                       teacher_id = excluded.teacher_id,
                       email = excluded.email,
                       free_days = excluded.free_days,
                       free_months = excluded.free_months,
                       active = excluded.active,
                       redeemed_by_user_id = excluded.redeemed_by_user_id,
                       redeemed_at = excluded.redeemed_at,
                       created_at = excluded.created_at,
                       updated_at = excluded.updated_at
                """,
                (
                    row["id"],
                    row["code"],
                    row["teacher_id"],
                    row["email"],
                    row["free_days"],
                    row["free_months"],
                    row["active"],
                    row["redeemed_by_user_id"],
                    row["redeemed_at"],
                    row["created_at"],
                    row["updated_at"],
                ),
            )


def _upsert_courses(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(
                """
                insert into app.courses (
                  id,
                  teacher_id,
                  title,
                  slug,
                  course_group_id,
                  group_position,
                  visibility,
                  content_ready,
                  price_amount_cents,
                  stripe_product_id,
                  active_stripe_price_id,
                  sellable,
                  drip_enabled,
                  drip_interval_days,
                  cover_media_id,
                  created_at,
                  updated_at
                )
                values (
                  %s::uuid,
                  %s::uuid,
                  %s,
                  %s,
                  %s::uuid,
                  %s,
                  %s::app.course_visibility,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s,
                  %s::uuid,
                  %s::timestamptz,
                  %s::timestamptz
                )
                on conflict (id) do update
                   set teacher_id = excluded.teacher_id,
                       title = excluded.title,
                       slug = excluded.slug,
                       course_group_id = excluded.course_group_id,
                       group_position = excluded.group_position,
                       visibility = excluded.visibility,
                       content_ready = excluded.content_ready,
                       price_amount_cents = excluded.price_amount_cents,
                       stripe_product_id = excluded.stripe_product_id,
                       active_stripe_price_id = excluded.active_stripe_price_id,
                       sellable = excluded.sellable,
                       drip_enabled = excluded.drip_enabled,
                       drip_interval_days = excluded.drip_interval_days,
                       cover_media_id = excluded.cover_media_id,
                       created_at = excluded.created_at,
                       updated_at = excluded.updated_at
                """,
                (
                    row["id"],
                    row["teacher_id"],
                    row["title"],
                    row["slug"],
                    row["course_group_id"],
                    row["group_position"],
                    row["visibility"],
                    row["content_ready"],
                    row["price_amount_cents"],
                    row["stripe_product_id"],
                    row["active_stripe_price_id"],
                    row["sellable"],
                    row["drip_enabled"],
                    row["drip_interval_days"],
                    row["cover_media_id"],
                    row["created_at"],
                    row["updated_at"],
                ),
            )


def _upsert_course_enrollments(conn: psycopg.Connection, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with conn.cursor(row_factory=dict_row) as cur:
        for row in rows:
            cur.execute(
                """
                select
                  ce.id::text,
                  ce.user_id::text,
                  ce.course_id::text,
                  ce.source::text as source,
                  ce.granted_at,
                  ce.drip_started_at,
                  ce.current_unlock_position,
                  ce.created_at,
                  ce.updated_at
                from app.canonical_create_course_enrollment(
                  %s::uuid,
                  %s::uuid,
                  %s::uuid,
                  %s::app.course_enrollment_source,
                  %s::timestamptz
                ) as ce
                """,
                (
                    row["id"],
                    row["user_id"],
                    row["course_id"],
                    row["source"],
                    row["granted_at"],
                ),
            )
            existing = dict(cur.fetchone() or {})
            if not existing:
                raise UserSnapshotBackfillError(
                    f"canonical_create_course_enrollment did not return a row for {row['id']}"
                )
            existing_unlock = int(existing["current_unlock_position"])
            desired_unlock = int(row["current_unlock_position"])
            if desired_unlock < existing_unlock:
                raise UserSnapshotBackfillError(
                    f"snapshot current_unlock_position {desired_unlock} would decrease "
                    f"existing enrollment {row['id']} from {existing_unlock}"
                )
            if desired_unlock > existing_unlock:
                cur.execute("select pg_catalog.set_config('app.canonical_worker_function_context', 'on', true)")
            cur.execute(
                """
                update app.course_enrollments
                   set current_unlock_position = %s,
                       created_at = %s::timestamptz,
                       updated_at = %s::timestamptz
                 where id = %s::uuid
                """,
                (
                    desired_unlock,
                    row["created_at"],
                    row["updated_at"],
                    row["id"],
                ),
            )
            if desired_unlock > existing_unlock:
                cur.execute("select pg_catalog.set_config('app.canonical_worker_function_context', 'off', true)")


def _verify_db_rows(
    conn: psycopg.Connection,
    *,
    table_name: str,
    expected_rows: list[dict[str, Any]],
    key: str,
    query: str,
    postprocess: Any | None = None,
) -> dict[str, Any]:
    actual_rows = _fetchall(conn, query)
    actual_by_key = {str(row[key]): row for row in actual_rows}
    expected_by_key = {str(row[key]): _strip_plan_compare(row) for row in expected_rows}
    mismatches: dict[str, Any] = {}
    for record_key, expected in expected_by_key.items():
        actual = actual_by_key.get(record_key)
        if postprocess is not None and actual is not None:
            actual = postprocess(actual)
        if actual != expected:
            mismatches[record_key] = {"expected": expected, "actual": actual}
    return {
        "table": table_name,
        "expected_count": len(expected_rows),
        "actual_count": len(actual_rows),
        "mismatches": mismatches,
        "ok": not mismatches and len(actual_rows) >= len(expected_rows),
    }


def _verify_plan_against_db(plan: dict[str, Any], *, database_url: str, env_file: Path, skip_stripe_verify: bool) -> dict[str, Any]:
    _verify_plan_payload_hash(plan)
    _verify_plan_source_snapshot(plan)

    from backend.bootstrap import baseline_v2

    baseline = baseline_v2.verify_v2_runtime(database_url)
    expected_hash = str(_require_mapping(plan.get("verification_expectations"), "verification_expectations")["baseline_schema_hash"])
    if baseline["schema_hash"] != expected_hash:
        raise UserSnapshotBackfillError(
            f"baseline schema hash mismatch: expected {expected_hash}, got {baseline['schema_hash']}"
        )

    tables = _require_mapping(plan.get("tables"), "tables")
    user_inventory = _require_list(plan.get("user_inventory"), "user_inventory")
    expected_user_ids = [str(item["user_id"]) for item in user_inventory]

    with psycopg.connect(database_url, connect_timeout=10) as conn:
        conn.execute("set default_transaction_read_only = on")
        _ensure_auth_users_exist(conn, expected_user_ids)

        auth_subjects = _verify_db_rows(
            conn,
            table_name="app.auth_subjects",
            expected_rows=_require_list(tables.get("auth_subjects"), "tables.auth_subjects"),
            key="user_id",
            query="""
                select user_id::text as user_id,
                       email,
                       role::text as role,
                       onboarding_state::text as onboarding_state,
                       created_at,
                       updated_at
                  from app.auth_subjects
                 order by user_id::text
            """,
        )
        profiles = _verify_db_rows(
            conn,
            table_name="app.profiles",
            expected_rows=_require_list(tables.get("profiles"), "tables.profiles"),
            key="user_id",
            query="""
                select user_id::text as user_id,
                       display_name,
                       bio,
                       avatar_media_id::text as avatar_media_id,
                       created_at,
                       updated_at
                  from app.profiles
                 order by user_id::text
            """,
            postprocess=lambda row: {
                **row,
                "avatar_url": f"/profiles/avatar/{row['avatar_media_id']}" if row.get("avatar_media_id") else None,
            },
        )
        media_assets = _verify_db_rows(
            conn,
            table_name="app.media_assets",
            expected_rows=_require_list(tables.get("media_assets"), "tables.media_assets"),
            key="id",
            query=f"""
                select {", ".join(column + ("::text as " + column if column in {"id"} else "") for column in MEDIA_ASSET_COLUMNS)}
                  from app.media_assets
                 order by id::text
            """,
        )
        profile_media_placements = _verify_db_rows(
            conn,
            table_name="app.profile_media_placements",
            expected_rows=_require_list(tables.get("profile_media_placements"), "tables.profile_media_placements"),
            key="id",
            query="""
                select id::text as id,
                       subject_user_id::text as subject_user_id,
                       media_asset_id::text as media_asset_id,
                       visibility::text as visibility,
                       created_at,
                       updated_at
                  from app.profile_media_placements
                 order by subject_user_id::text, id::text
            """,
        )
        memberships = _verify_db_rows(
            conn,
            table_name="app.memberships",
            expected_rows=_require_list(tables.get("memberships"), "tables.memberships"),
            key="user_id",
            query="""
                select membership_id::text as membership_id,
                       user_id::text as user_id,
                       status::text as status,
                       source::text as source,
                       effective_at,
                       expires_at,
                       canceled_at,
                       ended_at,
                       provider_customer_id,
                       provider_subscription_id,
                       created_at,
                       updated_at
                  from app.memberships
                 order by user_id::text
            """,
        )
        stripe_customers = _verify_db_rows(
            conn,
            table_name="app.stripe_customers",
            expected_rows=_require_list(tables.get("stripe_customers"), "tables.stripe_customers"),
            key="user_id",
            query="""
                select user_id::text as user_id, customer_id
                  from app.stripe_customers
                 order by user_id::text
            """,
        )
        referral_codes = _verify_db_rows(
            conn,
            table_name="app.referral_codes",
            expected_rows=_require_list(tables.get("referral_codes"), "tables.referral_codes"),
            key="id",
            query="""
                select id::text as id,
                       code,
                       teacher_id::text as teacher_id,
                       email,
                       free_days,
                       free_months,
                       active,
                       redeemed_by_user_id::text as redeemed_by_user_id,
                       redeemed_at,
                       created_at,
                       updated_at
                  from app.referral_codes
                 order by id::text
            """,
        )
        courses = _verify_db_rows(
            conn,
            table_name="app.courses",
            expected_rows=_require_list(tables.get("courses"), "tables.courses"),
            key="id",
            query="""
                select id::text as id,
                       teacher_id::text as teacher_id,
                       title,
                       slug,
                       course_group_id::text as course_group_id,
                       group_position,
                       visibility::text as visibility,
                       content_ready,
                       price_amount_cents,
                       stripe_product_id,
                       active_stripe_price_id,
                       sellable,
                       drip_enabled,
                       drip_interval_days,
                       cover_media_id::text as cover_media_id,
                       created_at,
                       updated_at
                  from app.courses
                 order by id::text
            """,
        )
        course_enrollments = _verify_db_rows(
            conn,
            table_name="app.course_enrollments",
            expected_rows=_require_list(tables.get("course_enrollments"), "tables.course_enrollments"),
            key="id",
            query="""
                select id::text as id,
                       user_id::text as user_id,
                       course_id::text as course_id,
                       source::text as source,
                       granted_at,
                       drip_started_at,
                       current_unlock_position,
                       created_at,
                       updated_at
                  from app.course_enrollments
                 order by id::text
            """,
        )

    stripe_verification = {"skipped": skip_stripe_verify}
    if not skip_stripe_verify:
        catalog = _live_membership_catalog(env_file)
        if catalog is None:
            raise UserSnapshotBackfillError(
                "Stripe verification requires STRIPE_SECRET_KEY, STRIPE_MEMBERSHIP_PRODUCT_ID, "
                "STRIPE_PRICE_MONTHLY, and STRIPE_PRICE_YEARLY"
            )
        expected_sellable = {
            bool(item["stripe_expectation"]["sellable"])
            for item in user_inventory
        }
        expected_product_ids = {
            str(item["stripe_expectation"]["stripe_product_id"])
            for item in user_inventory
            if item["stripe_expectation"]["stripe_product_id"] is not None
        }
        if len(expected_sellable) > 1:
            raise UserSnapshotBackfillError("plan contains conflicting stripe sellable expectations")
        if expected_product_ids and expected_product_ids != {catalog["membership_product"]["id"]}:
            raise UserSnapshotBackfillError(
                "live Stripe membership product does not match snapshot plan expectation"
            )
        if expected_sellable and expected_sellable != {bool(catalog["sellable"])}:
            raise UserSnapshotBackfillError("live Stripe sellable state does not match snapshot plan expectation")
        stripe_verification = {
            "skipped": False,
            "membership_product_id": catalog["membership_product"]["id"],
            "sellable": bool(catalog["sellable"]),
        }

    checks = [
        auth_subjects,
        profiles,
        media_assets,
        profile_media_placements,
        memberships,
        stripe_customers,
        referral_codes,
        courses,
        course_enrollments,
    ]
    return {
        "status": "PASS" if all(check["ok"] for check in checks) else "FAIL",
        "baseline_schema_hash": baseline["schema_hash"],
        "checks": checks,
        "stripe_verification": stripe_verification,
    }


def _apply_plan(plan: dict[str, Any], *, database_url: str, env_file: Path, skip_stripe_verify: bool) -> dict[str, Any]:
    _verify_plan_payload_hash(plan)
    _verify_plan_source_snapshot(plan)
    _require_apply_target(database_url)

    from backend.bootstrap import baseline_v2

    baseline = baseline_v2.verify_v2_runtime(database_url)
    expected_hash = str(_require_mapping(plan.get("verification_expectations"), "verification_expectations")["baseline_schema_hash"])
    if baseline["schema_hash"] != expected_hash:
        raise UserSnapshotBackfillError(
            f"baseline schema hash mismatch before apply: expected {expected_hash}, got {baseline['schema_hash']}"
        )

    tables = _require_mapping(plan.get("tables"), "tables")
    user_inventory = _require_list(plan.get("user_inventory"), "user_inventory")
    user_ids = [str(item["user_id"]) for item in user_inventory]

    with psycopg.connect(database_url, connect_timeout=10) as conn:
        conn.execute("set session characteristics as transaction isolation level serializable")
        with conn.transaction():
            _ensure_auth_users_exist(conn, user_ids)
            _upsert_auth_subjects(conn, _require_list(tables.get("auth_subjects"), "tables.auth_subjects"))
            media_asset_result = _insert_or_verify_media_assets(
                conn,
                _require_list(tables.get("media_assets"), "tables.media_assets"),
            )
            _upsert_profiles(conn, _require_list(tables.get("profiles"), "tables.profiles"))
            _upsert_profile_media_placements(
                conn,
                _require_list(tables.get("profile_media_placements"), "tables.profile_media_placements"),
            )
            _upsert_profiles(conn, _require_list(tables.get("profiles"), "tables.profiles"))
            _upsert_memberships(conn, _require_list(tables.get("memberships"), "tables.memberships"))
            _upsert_stripe_customers(
                conn,
                _require_list(tables.get("stripe_customers"), "tables.stripe_customers"),
            )
            _upsert_referral_codes(
                conn,
                _require_list(tables.get("referral_codes"), "tables.referral_codes"),
            )
            _upsert_courses(conn, _require_list(tables.get("courses"), "tables.courses"))
            _upsert_course_enrollments(
                conn,
                _require_list(tables.get("course_enrollments"), "tables.course_enrollments"),
            )
        conn.commit()

    verification = _verify_plan_against_db(
        plan,
        database_url=database_url,
        env_file=env_file,
        skip_stripe_verify=skip_stripe_verify,
    )
    return {
        "status": verification["status"],
        "baseline_schema_hash": expected_hash,
        "media_assets": media_asset_result,
        "verification": verification,
    }


def _profile_media_assets_snapshot(conn: psycopg.Connection) -> tuple[dict[str, list[dict[str, Any]]], dict[str, dict[str, Any]]]:
    asset_rows = _fetchall(
        conn,
        """
        select ma.id::text as media_asset_id,
               ma.media_type::text as media_type,
               ma.purpose::text as purpose,
               ma.original_object_path,
               ma.ingest_format,
               ma.playback_object_path,
               ma.playback_format,
               ma.state::text as state,
               ma.error_message,
               ma.processing_attempts,
               ma.processing_locked_at,
               ma.next_retry_at,
               ma.file_size,
               ma.content_hash_algorithm,
               ma.content_hash,
               ma.created_at,
               ma.updated_at
          from app.media_assets ma
         where ma.purpose = 'profile_media'::app.media_purpose
         order by ma.id::text
        """
    )
    placement_rows = _fetchall(
        conn,
        """
        select id::text as id,
               subject_user_id::text as subject_user_id,
               media_asset_id::text as media_asset_id,
               visibility::text as visibility,
               created_at,
               updated_at
          from app.profile_media_placements
         order by subject_user_id::text, id::text
        """
    )
    placements_by_subject: dict[str, list[dict[str, Any]]] = defaultdict(list)
    placement_by_asset: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for placement in placement_rows:
        placements_by_subject[str(placement["subject_user_id"])].append(placement)
        placement_by_asset[str(placement["media_asset_id"])].append(placement)

    assets_by_subject: dict[str, list[dict[str, Any]]] = defaultdict(list)
    assets_by_id: dict[str, dict[str, Any]] = {}
    for asset in asset_rows:
        subject_user_id = _profile_media_asset_subject(asset)
        if subject_user_id is None:
            continue
        asset_copy = dict(asset)
        placements = placement_by_asset.get(asset_copy["media_asset_id"], [])
        asset_copy["subject_user_id"] = subject_user_id
        asset_copy["placement_id"] = placements[0]["id"] if placements else None
        asset_copy["placement_visibility"] = placements[0]["visibility"] if placements else None
        assets_by_subject[subject_user_id].append(asset_copy)
        assets_by_id[asset_copy["media_asset_id"]] = asset_copy

    for records in assets_by_subject.values():
        records.sort(key=lambda item: item["media_asset_id"])
    return assets_by_subject, placements_by_subject


def _stripe_membership_snapshot(
    *,
    env_file: Path,
    membership_row: dict[str, Any] | None,
    stripe_customer_row: dict[str, Any] | None,
) -> dict[str, Any]:
    catalog = _live_membership_catalog(env_file)
    if catalog is None:
        raise UserSnapshotBackfillError(
            "snapshot export requires STRIPE_SECRET_KEY, STRIPE_MEMBERSHIP_PRODUCT_ID, "
            "STRIPE_PRICE_MONTHLY, and STRIPE_PRICE_YEARLY"
        )
    secret_key = _env_value("STRIPE_SECRET_KEY", env_file=env_file)
    if secret_key is None:
        raise UserSnapshotBackfillError("STRIPE_SECRET_KEY is required for snapshot export")

    customer_id = _normalize_text((stripe_customer_row or {}).get("customer_id"))
    subscription_id = _normalize_text((membership_row or {}).get("provider_subscription_id"))
    stripe_customer = _stripe_request(secret_key, "customers", customer_id) if customer_id else None
    stripe_subscription = _stripe_request(secret_key, "subscriptions", subscription_id) if subscription_id else None

    active_price_id = None
    if isinstance(stripe_subscription, dict):
        items = (((stripe_subscription.get("items") or {}).get("data")) or [])
        if isinstance(items, list) and items:
            first_item = items[0] or {}
            if isinstance(first_item, dict):
                price = first_item.get("price") or {}
                if isinstance(price, dict):
                    active_price_id = _normalize_text(price.get("id"))

    return {
        "stripe_product_id": catalog["membership_product"]["id"],
        "active_stripe_price_id": active_price_id,
        "sellable": bool(catalog["sellable"]),
        "configured_membership_catalog": catalog,
        "db_provider_customer_id": _normalize_text((membership_row or {}).get("provider_customer_id")),
        "db_provider_subscription_id": _normalize_text((membership_row or {}).get("provider_subscription_id")),
        "db_stripe_customer_relation": stripe_customer_row,
        "stripe_customer_id": customer_id,
        "stripe_subscription_id": subscription_id,
        "stripe_customer": stripe_customer,
        "stripe_subscription": stripe_subscription,
        "retrieved_at_utc": _utcnow(),
    }


def _export_snapshot(*, database_url: str, output_path: Path, env_file: Path) -> dict[str, Any]:
    from backend.bootstrap import baseline_v2

    snapshot: dict[str, Any]
    with psycopg.connect(database_url, connect_timeout=10) as conn:
        conn.execute("set default_transaction_read_only = on")
        conn.execute("set transaction isolation level repeatable read")
        baseline = baseline_v2.verify_v2_runtime(database_url)

        auth_users = _fetchall(
            conn,
            """
            select id::text as user_id,
                   email,
                   created_at,
                   last_sign_in_at
              from auth.users
             order by id::text
            """
        )
        auth_subject_rows = {
            str(row["user_id"]): row
            for row in _fetchall(
                conn,
                """
                select user_id::text as user_id,
                       email,
                       role::text as role,
                       onboarding_state::text as onboarding_state,
                       created_at,
                       updated_at
                  from app.auth_subjects
                 order by user_id::text
                """,
            )
        }
        profile_rows = {
            str(row["user_id"]): row
            for row in _fetchall(
                conn,
                """
                select user_id::text as user_id,
                       display_name,
                       bio,
                       avatar_media_id::text as avatar_media_id,
                       created_at,
                       updated_at
                  from app.profiles
                 order by user_id::text
                """,
            )
        }
        membership_rows = defaultdict(list)
        for row in _fetchall(
            conn,
            """
            select membership_id::text as membership_id,
                   user_id::text as user_id,
                   status::text as status,
                   source::text as source,
                   effective_at,
                   expires_at,
                   canceled_at,
                   ended_at,
                   provider_customer_id,
                   provider_subscription_id,
                   created_at,
                   updated_at
              from app.memberships
             order by user_id::text, membership_id::text
            """,
        ):
            membership_rows[str(row["user_id"])].append(row)
        stripe_customer_rows = {
            str(row["user_id"]): row
            for row in _fetchall(
                conn,
                """
                select user_id::text as user_id, customer_id
                  from app.stripe_customers
                 order by user_id::text
                """,
            )
        }
        referral_created = defaultdict(list)
        referral_redeemed = defaultdict(list)
        for row in _fetchall(
            conn,
            """
            select id::text as id,
                   code,
                   teacher_id::text as teacher_id,
                   email,
                   free_days,
                   free_months,
                   active,
                   redeemed_by_user_id::text as redeemed_by_user_id,
                   redeemed_at,
                   created_at,
                   updated_at
              from app.referral_codes
             order by id::text
            """,
        ):
            referral_created[str(row["teacher_id"])].append(row)
            if row.get("redeemed_by_user_id"):
                referral_redeemed[str(row["redeemed_by_user_id"])].append(row)
        authored_courses = defaultdict(list)
        for row in _fetchall(
            conn,
            """
            select id::text as id,
                   teacher_id::text as teacher_id,
                   title,
                   slug,
                   course_group_id::text as course_group_id,
                   group_position,
                   visibility::text as visibility,
                   content_ready,
                   price_amount_cents,
                   stripe_product_id,
                   active_stripe_price_id,
                   sellable,
                   drip_enabled,
                   drip_interval_days,
                   cover_media_id::text as cover_media_id,
                   created_at,
                   updated_at
              from app.courses
             order by teacher_id::text, group_position, id::text
            """,
        ):
            authored_courses[str(row["teacher_id"])].append(row)
        course_enrollments = defaultdict(list)
        for row in _fetchall(
            conn,
            """
            select id::text as id,
                   user_id::text as user_id,
                   course_id::text as course_id,
                   source::text as source,
                   granted_at,
                   drip_started_at,
                   current_unlock_position,
                   created_at,
                   updated_at
              from app.course_enrollments
             order by user_id::text, course_id::text, id::text
            """,
        ):
            course_enrollments[str(row["user_id"])].append(row)
        assets_by_subject, placements_by_subject = _profile_media_assets_snapshot(conn)

        public_media_base_url = _normalize_text(_env_value("SUPABASE_URL", env_file=env_file))
        snapshot_users: list[dict[str, Any]] = []
        for auth_user in auth_users:
            user_id = str(auth_user["user_id"])
            auth_subject = auth_subject_rows.get(user_id)
            profile = profile_rows.get(user_id)
            avatar_media_id = _normalize_text((profile or {}).get("avatar_media_id"))
            snapshot_users.append(
                {
                    "user_id": user_id,
                    "auth_user": {
                        "exists": True,
                        "user_id": user_id,
                        "email": _normalize_text(auth_user.get("email")),
                        "created_at": auth_user.get("created_at"),
                        "last_sign_in_at": auth_user.get("last_sign_in_at"),
                    },
                    "auth_subject": {
                        "exists": auth_subject is not None,
                        "user_id": user_id,
                        "email": _normalize_text((auth_subject or {}).get("email")),
                        "role": _normalize_text((auth_subject or {}).get("role")),
                        "onboarding_state": _normalize_text((auth_subject or {}).get("onboarding_state")),
                        "created_at": (auth_subject or {}).get("created_at"),
                        "updated_at": (auth_subject or {}).get("updated_at"),
                    },
                    "profile": {
                        "exists": profile is not None,
                        "user_id": user_id,
                        "display_name": _normalize_text((profile or {}).get("display_name")),
                        "bio": _normalize_text((profile or {}).get("bio")),
                        "avatar_media_id": avatar_media_id,
                        "avatar_url": f"/profiles/avatar/{avatar_media_id}" if avatar_media_id else None,
                        "avatar_media": None,
                        "created_at": (profile or {}).get("created_at"),
                        "updated_at": (profile or {}).get("updated_at"),
                    },
                    "profile_media": {
                        "owned_assets": assets_by_subject.get(user_id, []),
                        "placements": placements_by_subject.get(user_id, []),
                    },
                    "memberships": membership_rows.get(user_id, []),
                    "referrals": {
                        "created": referral_created.get(user_id, []),
                        "redeemed": referral_redeemed.get(user_id, []),
                    },
                    "course_associations": {
                        "authored_courses": authored_courses.get(user_id, []),
                        "enrollments": course_enrollments.get(user_id, []),
                    },
                    "stripe_membership_data": _stripe_membership_snapshot(
                        env_file=env_file,
                        membership_row=membership_rows.get(user_id, [None])[0],
                        stripe_customer_row=stripe_customer_rows.get(user_id),
                    ),
                }
            )

    snapshot = {
        "schema_version": SNAPSHOT_SCHEMA_V2,
        "snapshot_meta": {
            "captured_at_utc": _utcnow(),
            "source": {
                "database_url_host": _parsed_db_url(database_url).hostname,
                "database_mode": "read_only_repeatable_read",
                "baseline_schema_hash": baseline["schema_hash"],
            },
            "project_ref": None,
            "supabase_url": _normalize_text(_env_value("SUPABASE_URL", env_file=env_file)),
            "public_media_base_url": public_media_base_url,
            "coverage": {
                "snapshot_user_total": len(snapshot_users),
                "auth_users_total": len(snapshot_users),
                "auth_subjects_total": sum(
                    1 for user in snapshot_users if user["auth_subject"]["exists"]
                ),
                "profiles_total": sum(1 for user in snapshot_users if user["profile"]["exists"]),
                "memberships_total": sum(len(user["memberships"]) for user in snapshot_users),
                "profile_media_assets_total": sum(
                    len(user["profile_media"]["owned_assets"]) for user in snapshot_users
                ),
                "profile_media_placements_total": sum(
                    len(user["profile_media"]["placements"]) for user in snapshot_users
                ),
                "referral_codes_total": sum(
                    len(user["referrals"]["created"]) for user in snapshot_users
                ),
                "courses_total": sum(
                    len(user["course_associations"]["authored_courses"]) for user in snapshot_users
                ),
                "course_enrollments_total": sum(
                    len(user["course_associations"]["enrollments"]) for user in snapshot_users
                ),
                "stripe_customers_total": sum(
                    1
                    for user in snapshot_users
                    if user["stripe_membership_data"]["stripe_customer_id"] is not None
                ),
                "all_auth_users_included": True,
                "all_auth_subjects_included": True,
                "all_required_fields_present_per_user": True,
                "all_users_have_stripe_membership_data": True,
                "missing_field_coverage": {},
                "auth_subjects_without_auth_user": [],
                "auth_users_without_auth_subject": [
                    user["user_id"]
                    for user in snapshot_users
                    if not user["auth_subject"]["exists"]
                ],
                "profiles_without_auth_subject": [],
                "profiles_without_auth_user": [],
                "memberships_without_auth_subject": [],
                "memberships_without_auth_user": [],
            },
            "deterministic_ordering": {
                "users": "user_id ascending",
                "memberships": "membership_id ascending within user",
                "referrals": "id ascending within user",
                "authored_courses": "group_position then id ascending within user",
                "course_enrollments": "course_id then id ascending within user",
                "profile_media_assets": "media_asset_id ascending within user",
                "profile_media_placements": "id ascending within user",
            },
            "stripe_catalog": _live_membership_catalog(env_file) or {},
            "payload_sha256_algorithm": SNAPSHOT_HASH_ALGORITHM,
            "payload_sha256": None,
        },
        "orphan_records": {
            "auth_subjects_without_auth_user": [],
            "auth_users_without_auth_subject": [
                user["user_id"]
                for user in snapshot_users
                if not user["auth_subject"]["exists"]
            ],
            "profiles_without_auth_subject": [],
            "profiles_without_auth_user": [],
        },
        "users": sorted(snapshot_users, key=lambda item: item["user_id"]),
    }
    snapshot["snapshot_meta"]["payload_sha256"] = _hash_excluding_field(
        snapshot,
        field_path=("snapshot_meta", "payload_sha256"),
    )
    _write_canonical_json(output_path, snapshot)
    return {
        "status": "PASS",
        "snapshot_path": str(output_path),
        "snapshot_raw_sha256": _raw_file_sha256(output_path),
        "snapshot_schema": SNAPSHOT_SCHEMA_V2,
        "snapshot_payload_sha256": snapshot["snapshot_meta"]["payload_sha256"],
        "coverage": snapshot["snapshot_meta"]["coverage"],
    }


def _default_snapshot_path() -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    return DEFAULT_SNAPSHOT_DIR / f"auth_subjects_snapshot_{timestamp}.json"


def _default_plan_path(snapshot_path: Path) -> Path:
    return snapshot_path.with_name(f"{snapshot_path.stem}_backfill_plan.json")


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Canonical export/compile/apply/verify tooling for user snapshot backfill."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export", help="Export a snapshot v2 from a DB target.")
    export_parser.add_argument("--database-url", default=DEFAULT_DATABASE_URL, required=not bool(DEFAULT_DATABASE_URL))
    export_parser.add_argument("--output", default=str(_default_snapshot_path()))
    export_parser.add_argument("--env-file", default=str(DEFAULT_ENV_FILE))

    compile_parser = subparsers.add_parser("compile", help="Compile a backfill plan from a snapshot.")
    compile_parser.add_argument("--snapshot", required=True)
    compile_parser.add_argument("--output")

    apply_parser = subparsers.add_parser("apply", help="Apply a compiled backfill plan to a DB target.")
    apply_parser.add_argument("--plan", required=True)
    apply_parser.add_argument("--database-url", default=DEFAULT_DATABASE_URL, required=not bool(DEFAULT_DATABASE_URL))
    apply_parser.add_argument("--env-file", default=str(DEFAULT_ENV_FILE))
    apply_parser.add_argument("--skip-stripe-verify", action="store_true")

    verify_parser = subparsers.add_parser("verify", help="Verify a compiled backfill plan against a DB target.")
    verify_parser.add_argument("--plan", required=True)
    verify_parser.add_argument("--database-url", default=DEFAULT_DATABASE_URL, required=not bool(DEFAULT_DATABASE_URL))
    verify_parser.add_argument("--env-file", default=str(DEFAULT_ENV_FILE))
    verify_parser.add_argument("--skip-stripe-verify", action="store_true")

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    try:
        if args.command == "export":
            result = _export_snapshot(
                database_url=str(args.database_url),
                output_path=Path(str(args.output)).expanduser().resolve(),
                env_file=Path(str(args.env_file)).expanduser().resolve(),
            )
        elif args.command == "compile":
            snapshot_path = Path(str(args.snapshot)).expanduser().resolve()
            plan = _compile_plan(snapshot_path)
            output_path = (
                Path(str(args.output)).expanduser().resolve()
                if args.output
                else _default_plan_path(snapshot_path)
            )
            _write_canonical_json(output_path, plan)
            result = {
                "status": "PASS",
                "plan_path": str(output_path),
                "plan_raw_sha256": _raw_file_sha256(output_path),
                "plan_payload_sha256": plan["plan_meta"]["payload_sha256"],
                "verification_expectations": plan["verification_expectations"],
                "derived_defaults": len(plan["derived_defaults"]),
            }
        elif args.command == "apply":
            plan = _load_json(Path(str(args.plan)).expanduser().resolve())
            result = _apply_plan(
                plan,
                database_url=str(args.database_url),
                env_file=Path(str(args.env_file)).expanduser().resolve(),
                skip_stripe_verify=bool(args.skip_stripe_verify),
            )
        elif args.command == "verify":
            plan = _load_json(Path(str(args.plan)).expanduser().resolve())
            result = _verify_plan_against_db(
                plan,
                database_url=str(args.database_url),
                env_file=Path(str(args.env_file)).expanduser().resolve(),
                skip_stripe_verify=bool(args.skip_stripe_verify),
            )
        else:  # pragma: no cover
            raise UserSnapshotBackfillError(f"unsupported command {args.command!r}")
    except Exception as exc:
        print(
            json.dumps(
                {
                    "status": "BLOCKED",
                    "command": args.command,
                    "error": str(exc),
                },
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
