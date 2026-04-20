from __future__ import annotations

from collections import Counter
from datetime import datetime, timezone
from typing import Any

from ..media_control_plane.services.media_resolver_service import (
    RuntimeMediaResolution,
    media_resolver_service,
)
from ..observability import log_buffer
from ..repositories import (
    courses as courses_repo,
    home_audio_sources as home_audio_sources_repo,
    media_assets as media_assets_repo,
    media_resolution_failures as media_resolution_failures_repo,
    runtime_media as runtime_media_repo,
    storage_objects,
)

_ASSET_REFERENCE_LIMIT = 25
_TRACE_LOG_LIMIT = 25
_TRACE_FAILURE_LIMIT = 25
_ORPHANED_ASSET_LIMIT = 100
_RUNTIME_VALIDATION_LIMIT = 100
_UNLINKED_ASSET_GRACE_SECONDS = 1800
_CONTROL_PLANE_ASSET_PURPOSES = {
    "lesson_audio",
    "lesson_media",
    "home_player_audio",
}
_LESSON_LINKED_PURPOSES = {"lesson_audio", "lesson_media"}
_PLAYBACK_KINDS = {"audio", "video", "image"}
_SEVERITY_RANK = {"error": 0, "warning": 1, "info": 2}
_RELATED_LOGGERS = {
    "app.media_control_plane.services.media_resolver_service",
    "app.routes.api_media",
    "app.services.media_transcode_worker",
}
_RUNTIME_CONTRACT_FIELDS = (
    "reference_type",
    "auth_scope",
    "course_id",
    "lesson_id",
    "media_asset_id",
    "kind",
    "active",
)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _parse_timestamp(value: str | None) -> datetime:
    if not value:
        return datetime.min.replace(tzinfo=timezone.utc)
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _normalize_text(value: Any) -> str | None:
    normalized = str(value or "").strip()
    return normalized or None


def _normalize_path(value: Any) -> str | None:
    normalized = _normalize_text(value)
    if normalized is None:
        return None
    return normalized.replace("\\", "/").lstrip("/")


def _normalize_kind(value: Any) -> str | None:
    normalized = (_normalize_text(value) or "").lower()
    if not normalized:
        return None
    if normalized == "pdf":
        return "document"
    if normalized in {"audio", "video", "image", "document", "other"}:
        return normalized
    return normalized


def _normalize_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _dedupe_strings(values: list[str | None]) -> list[str]:
    seen: set[str] = set()
    items: list[str] = []
    for value in values:
        normalized = str(value or "").strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        items.append(normalized)
    return items


def _sorted_dedupe_strings(values: list[str | None]) -> list[str]:
    return sorted(_dedupe_strings(values))


def _playback_kind(kind: str | None) -> bool:
    return str(kind or "").strip().lower() in _PLAYBACK_KINDS


def _initial_state_for_purpose(purpose: str | None) -> str | None:
    normalized = str(purpose or "").strip().lower()
    if normalized in {"lesson_audio", "lesson_media"}:
        return "pending_upload"
    if normalized in {"home_player_audio", "course_cover"}:
        return "uploaded"
    return None


def _normalize_asset_row(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if not row:
        return None
    return {
        "asset_id": str(row["id"]),
        "course_id": _normalize_text(row.get("course_id")),
        "lesson_id": _normalize_text(row.get("lesson_id")),
        "media_type": _normalize_kind(row.get("media_type")),
        "purpose": _normalize_text(row.get("purpose")),
        "ingest_format": _normalize_text(row.get("ingest_format")),
        "state": _normalize_text(row.get("state")),
        "content_type": _normalize_text(row.get("original_content_type")),
        "size_bytes": _normalize_int(row.get("original_size_bytes")),
        "duration_seconds": _normalize_int(row.get("duration_seconds")),
        "codec": _normalize_text(row.get("codec")),
        "error_message": (
            log_buffer.sanitize_string(str(row.get("error_message")))
            if row.get("error_message")
            else None
        ),
        "processing_attempts": int(row.get("processing_attempts") or 0),
        "processing_locked_at": _iso(row.get("processing_locked_at")),
        "next_retry_at": _iso(row.get("next_retry_at")),
        "created_at": _iso(row.get("created_at")),
        "updated_at": _iso(row.get("updated_at")),
        "storage": {
            "source_bucket": _normalize_text(row.get("storage_bucket")),
            "source_path": _normalize_path(row.get("original_object_path")),
            "playback_bucket": _normalize_text(row.get("storage_bucket")),
            "playback_path": _normalize_path(row.get("playback_object_path")),
            "playback_format": _normalize_text(row.get("playback_format")),
        },
    }


def _normalize_lesson_media_row(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "lesson_media_id": str(row["id"]),
        "lesson_id": _normalize_text(row.get("lesson_id")),
        "kind": _normalize_kind(row.get("kind")),
        "position": _normalize_int(row.get("position")),
        "asset_id": _normalize_text(row.get("media_asset_id")),
        "media_state": _normalize_text(row.get("media_state")),
        "content_type": _normalize_text(row.get("content_type")),
        "duration_seconds": _normalize_int(row.get("duration_seconds")),
        "error_message": (
            log_buffer.sanitize_string(str(row.get("error_message")))
            if row.get("error_message")
            else None
        ),
        "issue_reason": _normalize_text(row.get("issue_reason")),
        "issue_details": log_buffer.sanitize_value(row.get("issue_details") or {}),
        "issue_updated_at": _iso(row.get("issue_updated_at")),
        "created_at": _iso(row.get("created_at")),
        "storage": {
            "bucket": _normalize_text(row.get("storage_bucket")),
            "path": _normalize_path(row.get("storage_path")),
        },
    }


def _runtime_contract_kind(value: Any) -> str:
    normalized = (_normalize_text(value) or "other").lower()
    if normalized in {"audio", "video", "image", "document", "other"}:
        return normalized
    if normalized == "pdf":
        return "document"
    return "other"


def _expected_runtime_contract(
    *,
    lesson_row: dict[str, Any],
    lesson_media_row: dict[str, Any],
) -> dict[str, Any]:
    return {
        "reference_type": "lesson_media",
        "auth_scope": "lesson_course",
        "course_id": _normalize_text(lesson_row.get("course_id")),
        "lesson_id": _normalize_text(lesson_media_row.get("lesson_id")),
        "media_asset_id": _normalize_text(lesson_media_row.get("media_asset_id")),
        "kind": _runtime_contract_kind(lesson_media_row.get("kind")),
        "active": True,
    }


def _actual_runtime_contract(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "reference_type": _normalize_text(row.get("reference_type")),
        "auth_scope": _normalize_text(row.get("auth_scope")),
        "course_id": _normalize_text(row.get("course_id")),
        "lesson_id": _normalize_text(row.get("lesson_id")),
        "media_asset_id": _normalize_text(row.get("media_asset_id")),
        "kind": _runtime_contract_kind(row.get("kind")),
        "active": bool(row.get("active")),
    }


def _runtime_contract_diffs(
    *,
    expected: dict[str, Any],
    actual: dict[str, Any] | None,
) -> list[dict[str, Any]]:
    if actual is None:
        return []

    diffs: list[dict[str, Any]] = []
    for field in _RUNTIME_CONTRACT_FIELDS:
        expected_value = expected.get(field)
        actual_value = actual.get(field)
        if expected_value == actual_value:
            continue
        diffs.append(
            {
                "field": field,
                "expected": log_buffer.sanitize_value(expected_value),
                "actual": log_buffer.sanitize_value(actual_value),
            }
        )
    return diffs


def _normalize_runtime_row(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "runtime_media_id": str(row["id"]),
        "reference_type": _normalize_text(row.get("reference_type")),
        "auth_scope": _normalize_text(row.get("auth_scope")),
        "lesson_media_id": _normalize_text(row.get("lesson_media_id")),
        "home_player_upload_id": _normalize_text(row.get("home_player_upload_id")),
        "course_id": _normalize_text(row.get("course_id")),
        "lesson_id": _normalize_text(row.get("lesson_id")),
        "asset_id": _normalize_text(row.get("media_asset_id")),
        "kind": _normalize_kind(row.get("kind")),
        "active": bool(row.get("active")),
        "created_at": _iso(row.get("created_at")),
        "updated_at": _iso(row.get("updated_at")),
    }


def _projection_state_classification(
    row: dict[str, Any],
    resolution: RuntimeMediaResolution | None,
) -> str:
    kind = _normalize_kind(row.get("kind"))
    if kind == "document" and not bool(row.get("active")):
        return "inactive_non_playback"
    if resolution is None:
        return "inactive" if not bool(row.get("active")) else "unvalidated"
    if resolution.is_playable:
        return "playable"
    if not bool(row.get("active")):
        return "inactive"
    return "unplayable"


def _normalize_runtime_resolution(
    row: dict[str, Any],
    resolution: RuntimeMediaResolution | None,
) -> dict[str, Any]:
    normalized_row = _normalize_runtime_row(row)
    normalized_row["state_classification"] = _projection_state_classification(
        row,
        resolution,
    )
    if resolution is None:
        normalized_row["resolution"] = None
        return normalized_row

    normalized_row["resolution"] = {
        "runtime_media_id": resolution.runtime_media_id or normalized_row["runtime_media_id"],
        "lesson_media_id": resolution.lesson_media_id,
        "lesson_id": resolution.lesson_id,
        "asset_id": resolution.media_asset_id,
        "media_type": resolution.media_type,
        "content_type": resolution.content_type,
        "media_state": resolution.media_state,
        "is_playable": bool(resolution.is_playable),
        "playback_mode": resolution.playback_mode.value,
        "failure_reason": resolution.failure_reason.value,
        "failure_detail": (
            log_buffer.sanitize_string(str(resolution.failure_detail))
            if resolution.failure_detail
            else None
        ),
        "duration_seconds": resolution.duration_seconds,
        "resolved_storage": {
            "bucket": resolution.storage_bucket,
            "path": _normalize_path(resolution.storage_path),
        },
    }
    return normalized_row


def _normalize_storage_check(
    *,
    label: str,
    bucket: str | None,
    storage_path: str | None,
    detail: dict[str, Any] | None,
    storage_catalog_available: bool,
) -> dict[str, Any]:
    normalized = {
        "label": label,
        "bucket": bucket,
        "storage_path": storage_path,
        "exists": None if not storage_catalog_available else bool(detail),
        "content_type": None,
        "size_bytes": None,
        "public": None,
        "updated_at": None,
    }
    if detail is None:
        return normalized
    normalized["exists"] = True
    normalized["content_type"] = _normalize_text(detail.get("content_type"))
    normalized["size_bytes"] = _normalize_int(detail.get("size_bytes"))
    normalized["public"] = bool(detail.get("public"))
    normalized["updated_at"] = _iso(detail.get("updated_at"))
    return normalized


def _storage_verification_confidence(
    *,
    checks: list[dict[str, Any]],
    storage_catalog_available: bool,
) -> str:
    if not storage_catalog_available:
        return "unavailable"

    identity_checks = [
        check
        for check in checks
        if check.get("bucket") is not None or check.get("storage_path") is not None
    ]
    if not identity_checks:
        return "partial"
    if any(
        check.get("bucket") is None or check.get("storage_path") is None
        for check in identity_checks
    ):
        return "partial"
    return "full"


def _empty_storage_verification(*, include_checks: bool = True) -> dict[str, Any]:
    verification = {
        "storage_catalog_available": False,
        "confidence": "unavailable",
    }
    if include_checks:
        verification["checks"] = []
    return verification


def _asset_storage_targets(asset_row: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "label": "source",
            "bucket": _normalize_text(asset_row.get("storage_bucket")),
            "storage_path": _normalize_path(asset_row.get("original_object_path")),
        },
        {
            "label": "playback",
            "bucket": _normalize_text(asset_row.get("storage_bucket")),
            "storage_path": _normalize_path(asset_row.get("playback_object_path")),
        },
    ]


def _storage_pairs_from_targets(targets: list[dict[str, Any]]) -> list[tuple[str, str]]:
    return sorted(
        {
            (str(target["bucket"]), str(target["storage_path"]))
            for target in targets
            if target.get("bucket") is not None and target.get("storage_path") is not None
        }
    )


def _storage_verification_with_checks(
    *,
    targets: list[dict[str, Any]],
    details: dict[tuple[str, str], dict[str, Any] | None],
    storage_catalog_available: bool,
) -> dict[str, Any]:
    checks = [
        _normalize_storage_check(
            label=str(target["label"]),
            bucket=target.get("bucket"),
            storage_path=target.get("storage_path"),
            detail=details.get((str(target["bucket"]), str(target["storage_path"])))
            if target.get("bucket") is not None and target.get("storage_path") is not None
            else None,
            storage_catalog_available=storage_catalog_available,
        )
        for target in targets
    ]
    return {
        "storage_catalog_available": bool(storage_catalog_available),
        "confidence": _storage_verification_confidence(
            checks=checks,
            storage_catalog_available=bool(storage_catalog_available),
        ),
        "checks": checks,
    }


async def _asset_storage_verification(asset_row: dict[str, Any]) -> dict[str, Any]:
    targets = _asset_storage_targets(asset_row)
    pairs = _storage_pairs_from_targets(targets)
    details, storage_catalog_available = await storage_objects.fetch_storage_object_details(pairs)
    return _storage_verification_with_checks(
        targets=targets,
        details=details,
        storage_catalog_available=bool(storage_catalog_available),
    )


async def _aggregate_storage_verification(
    asset_rows: list[dict[str, Any]],
) -> dict[str, Any]:
    normalized_rows = [row for row in asset_rows if row]
    if not normalized_rows:
        return _empty_storage_verification(include_checks=False)

    targets: list[dict[str, Any]] = []
    for row in sorted(normalized_rows, key=_asset_sort_key):
        targets.extend(_asset_storage_targets(row))

    pairs = _storage_pairs_from_targets(targets)
    details, storage_catalog_available = await storage_objects.fetch_storage_object_details(pairs)
    checks = _storage_verification_with_checks(
        targets=targets,
        details=details,
        storage_catalog_available=bool(storage_catalog_available),
    )["checks"]
    return {
        "storage_catalog_available": bool(storage_catalog_available),
        "confidence": _storage_verification_confidence(
            checks=checks,
            storage_catalog_available=bool(storage_catalog_available),
        ),
    }


def _validation_metadata(evaluated_at: str | None) -> dict[str, Any]:
    return {
        "validation_mode": "strict_contract",
        "evaluated_at": evaluated_at,
        "data_freshness": "snapshot",
    }


def _inconsistency(
    code: str,
    message: str,
    *,
    severity: str = "warning",
    asset_id: str | None = None,
    lesson_id: str | None = None,
    lesson_media_id: str | None = None,
    runtime_media_id: str | None = None,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "code": code,
        "severity": severity,
        "message": log_buffer.sanitize_string(message),
        "asset_id": asset_id,
        "lesson_id": lesson_id,
        "lesson_media_id": lesson_media_id,
        "runtime_media_id": runtime_media_id,
        "details": log_buffer.sanitize_value(details or {}),
    }


def _sort_inconsistencies(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        items,
        key=lambda item: (
            _SEVERITY_RANK.get(str(item.get("severity") or "warning"), 99),
            str(item.get("code") or ""),
            str(item.get("asset_id") or ""),
            str(item.get("lesson_media_id") or ""),
            str(item.get("runtime_media_id") or ""),
        ),
    )


def _timestamp_marker(
    *,
    label: str,
    timestamp: str | None,
    asset_id: str | None = None,
    lesson_id: str | None = None,
    lesson_media_id: str | None = None,
    runtime_media_id: str | None = None,
) -> dict[str, Any] | None:
    if not timestamp:
        return None
    return {
        "label": label,
        "timestamp": timestamp,
        "asset_id": asset_id,
        "lesson_id": lesson_id,
        "lesson_media_id": lesson_media_id,
        "runtime_media_id": runtime_media_id,
    }


def _state_transition(
    *,
    timestamp: str | None,
    transition: str,
    source: str,
    asset_id: str | None = None,
    lesson_id: str | None = None,
    lesson_media_id: str | None = None,
    runtime_media_id: str | None = None,
    state: str | None = None,
    certainty: str = "observed",
    details: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    if not timestamp:
        return None
    return {
        "timestamp": timestamp,
        "transition": transition,
        "source": source,
        "asset_id": asset_id,
        "lesson_id": lesson_id,
        "lesson_media_id": lesson_media_id,
        "runtime_media_id": runtime_media_id,
        "state": state,
        "certainty": certainty,
        "details": log_buffer.sanitize_value(details or {}),
    }


def _sort_timestamps(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        items,
        key=lambda item: (
            _parse_timestamp(item.get("timestamp")),
            str(item.get("label") or ""),
            str(item.get("asset_id") or ""),
            str(item.get("lesson_media_id") or ""),
            str(item.get("runtime_media_id") or ""),
        ),
    )


def _sort_transitions(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        items,
        key=lambda item: (
            _parse_timestamp(item.get("timestamp")),
            str(item.get("transition") or ""),
            str(item.get("asset_id") or ""),
            str(item.get("lesson_media_id") or ""),
            str(item.get("runtime_media_id") or ""),
        ),
    )


def _asset_sort_key(row: dict[str, Any]) -> tuple[str, datetime, datetime]:
    return (
        str(row.get("id") or ""),
        _parse_timestamp(_iso(row.get("created_at"))),
        _parse_timestamp(_iso(row.get("updated_at"))),
    )


def _runtime_sort_key(row: dict[str, Any]) -> tuple[datetime, datetime, str]:
    return (
        _parse_timestamp(_iso(row.get("updated_at"))),
        _parse_timestamp(_iso(row.get("created_at"))),
        str(row.get("id") or ""),
    )


def _asset_unlinked_age_seconds(row: dict[str, Any]) -> int | None:
    updated_at = row.get("updated_at")
    created_at = row.get("created_at")
    if updated_at is None and created_at is None:
        return None
    latest = updated_at or created_at
    if latest is None:
        return None
    if latest.tzinfo is None:
        latest = latest.replace(tzinfo=timezone.utc)
    age_seconds = int((_now() - latest).total_seconds())
    return max(age_seconds, 0)


def _unlinked_asset_state_classification(row: dict[str, Any], *, runtime_gap: bool) -> str:
    if runtime_gap:
        return "runtime_projection_gap"

    state = _normalize_text(row.get("state"))
    if state in {"pending_upload", "uploaded", "processing"}:
        age_seconds = _asset_unlinked_age_seconds(row)
        if age_seconds is None or age_seconds <= _UNLINKED_ASSET_GRACE_SECONDS:
            return "awaiting_link"
        return "unlinked_stalled"
    if state == "failed":
        return "failed_unlinked"
    return "strict_orphan"


def _build_correlation(
    *,
    asset_rows: list[dict[str, Any]],
    lesson_media_rows: list[dict[str, Any]],
    runtime_rows: list[dict[str, Any]],
    extra_transitions: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    asset_ids = _sorted_dedupe_strings(
        [str(row.get("id")) for row in asset_rows if row.get("id")]
    )
    lesson_ids = _sorted_dedupe_strings(
        [str(row.get("lesson_id")) for row in asset_rows if row.get("lesson_id")]
        + [str(row.get("lesson_id")) for row in lesson_media_rows if row.get("lesson_id")]
        + [str(row.get("lesson_id")) for row in runtime_rows if row.get("lesson_id")]
    )
    lesson_media_ids = _sorted_dedupe_strings(
        [str(row.get("id")) for row in lesson_media_rows if row.get("id")]
        + [
            str(row.get("lesson_media_id"))
            for row in runtime_rows
            if row.get("lesson_media_id")
        ]
    )
    runtime_media_ids = _sorted_dedupe_strings(
        [str(row.get("id")) for row in runtime_rows if row.get("id")]
    )

    timestamps: list[dict[str, Any]] = []
    transitions: list[dict[str, Any]] = []

    for row in asset_rows:
        asset_id = str(row.get("id")) if row.get("id") else None
        lesson_id = _normalize_text(row.get("lesson_id"))
        purpose = _normalize_text(row.get("purpose"))
        state = _normalize_text(row.get("state"))
        created_at = _iso(row.get("created_at"))
        updated_at = _iso(row.get("updated_at"))
        processing_locked_at = _iso(row.get("processing_locked_at"))
        next_retry_at = _iso(row.get("next_retry_at"))

        for marker in (
            _timestamp_marker(
                label="asset_created_at",
                timestamp=created_at,
                asset_id=asset_id,
                lesson_id=lesson_id,
            ),
            _timestamp_marker(
                label="asset_updated_at",
                timestamp=updated_at,
                asset_id=asset_id,
                lesson_id=lesson_id,
            ),
            _timestamp_marker(
                label="asset_processing_locked_at",
                timestamp=processing_locked_at,
                asset_id=asset_id,
                lesson_id=lesson_id,
            ),
            _timestamp_marker(
                label="asset_next_retry_at",
                timestamp=next_retry_at,
                asset_id=asset_id,
                lesson_id=lesson_id,
            ),
        ):
            if marker is not None:
                timestamps.append(marker)

        initial_state = _initial_state_for_purpose(purpose) or state
        created_certainty = "inferred" if initial_state != state else "reconstructed"
        for transition in (
            _state_transition(
                timestamp=created_at,
                transition="asset_record_created",
                source="media_assets",
                asset_id=asset_id,
                lesson_id=lesson_id,
                state=initial_state,
                certainty=created_certainty,
                details={"purpose": purpose},
            ),
            _state_transition(
                timestamp=processing_locked_at,
                transition="asset_processing_locked",
                source="media_assets",
                asset_id=asset_id,
                lesson_id=lesson_id,
                state="processing",
                certainty="reconstructed",
            ),
            _state_transition(
                timestamp=next_retry_at,
                transition="asset_retry_scheduled",
                source="media_assets",
                asset_id=asset_id,
                lesson_id=lesson_id,
                state=state,
                certainty="reconstructed",
            ),
            _state_transition(
                timestamp=updated_at,
                transition="asset_state_observed",
                source="media_assets",
                asset_id=asset_id,
                lesson_id=lesson_id,
                state=state,
                certainty="reconstructed",
            ),
        ):
            if transition is not None:
                transitions.append(transition)

    for row in lesson_media_rows:
        lesson_media_id = str(row.get("id")) if row.get("id") else None
        lesson_id = _normalize_text(row.get("lesson_id"))
        asset_id = _normalize_text(row.get("media_asset_id"))
        created_at = _iso(row.get("created_at"))
        issue_updated_at = _iso(row.get("issue_updated_at"))
        media_state = _normalize_text(row.get("media_state"))
        issue_reason = _normalize_text(row.get("issue_reason"))

        for marker in (
            _timestamp_marker(
                label="lesson_media_created_at",
                timestamp=created_at,
                asset_id=asset_id,
                lesson_id=lesson_id,
                lesson_media_id=lesson_media_id,
            ),
            _timestamp_marker(
                label="lesson_media_issue_updated_at",
                timestamp=issue_updated_at,
                asset_id=asset_id,
                lesson_id=lesson_id,
                lesson_media_id=lesson_media_id,
            ),
        ):
            if marker is not None:
                timestamps.append(marker)

        for transition in (
            _state_transition(
                timestamp=created_at,
                transition="lesson_media_linked",
                source="lesson_media",
                asset_id=asset_id,
                lesson_id=lesson_id,
                lesson_media_id=lesson_media_id,
                state=media_state,
                details={"kind": _normalize_kind(row.get("kind"))},
                certainty="reconstructed",
            ),
            _state_transition(
                timestamp=issue_updated_at,
                transition="lesson_media_issue_reported",
                source="lesson_media",
                asset_id=asset_id,
                lesson_id=lesson_id,
                lesson_media_id=lesson_media_id,
                state=media_state,
                details={"issue_reason": issue_reason},
                certainty="reconstructed",
            ),
        ):
            if transition is not None:
                transitions.append(transition)

    for row in runtime_rows:
        runtime_media_id = str(row.get("id")) if row.get("id") else None
        lesson_media_id = _normalize_text(row.get("lesson_media_id"))
        lesson_id = _normalize_text(row.get("lesson_id"))
        asset_id = _normalize_text(row.get("media_asset_id"))
        created_at = _iso(row.get("created_at"))
        updated_at = _iso(row.get("updated_at"))
        state = "active" if bool(row.get("active")) else "inactive"

        for marker in (
            _timestamp_marker(
                label="runtime_media_created_at",
                timestamp=created_at,
                asset_id=asset_id,
                lesson_id=lesson_id,
                lesson_media_id=lesson_media_id,
                runtime_media_id=runtime_media_id,
            ),
            _timestamp_marker(
                label="runtime_media_updated_at",
                timestamp=updated_at,
                asset_id=asset_id,
                lesson_id=lesson_id,
                lesson_media_id=lesson_media_id,
                runtime_media_id=runtime_media_id,
            ),
        ):
            if marker is not None:
                timestamps.append(marker)

        for transition in (
            _state_transition(
                timestamp=created_at,
                transition="runtime_projection_created",
                source="runtime_media",
                asset_id=asset_id,
                lesson_id=lesson_id,
                lesson_media_id=lesson_media_id,
                runtime_media_id=runtime_media_id,
                state=state,
                details={"kind": _normalize_kind(row.get("kind"))},
                certainty="reconstructed",
            ),
            _state_transition(
                timestamp=updated_at,
                transition="runtime_projection_observed",
                source="runtime_media",
                asset_id=asset_id,
                lesson_id=lesson_id,
                lesson_media_id=lesson_media_id,
                runtime_media_id=runtime_media_id,
                state=state,
                details={"active": bool(row.get("active"))},
                certainty="reconstructed",
            ),
        ):
            if transition is not None:
                transitions.append(transition)

    for transition in extra_transitions or []:
        transitions.append(transition)

    return {
        "asset_ids": asset_ids,
        "lesson_ids": lesson_ids,
        "lesson_media_ids": lesson_media_ids,
        "runtime_media_ids": runtime_media_ids,
        "timestamps": _sort_timestamps(timestamps),
        "state_transitions": _sort_transitions(transitions),
    }


def _asset_snapshot_classification(
    *,
    asset_row: dict[str, Any],
    purpose: str | None,
    inconsistencies: list[dict[str, Any]],
    lesson_media_rows: list[dict[str, Any]],
    runtime_rows: list[dict[str, Any]],
    has_home_audio_source: bool,
) -> str:
    if purpose not in _CONTROL_PLANE_ASSET_PURPOSES:
        return "out_of_scope"
    if inconsistencies:
        return "inconsistent"
    if purpose == "home_player_audio" and has_home_audio_source:
        state = _normalize_text(asset_row.get("state"))
        if state == "failed":
            return "asset_failed"
        if state in {"pending_upload", "uploaded", "processing"}:
            return "asset_in_progress"
        if state == "ready":
            return "projected_ready"
        return "observed"
    if not lesson_media_rows and not runtime_rows:
        return _unlinked_asset_state_classification(asset_row, runtime_gap=False)
    state = _normalize_text(asset_row.get("state"))
    if state == "failed":
        return "asset_failed"
    if state in {"pending_upload", "uploaded", "processing"}:
        return "asset_in_progress"
    if state == "ready":
        return "projected_ready"
    return "observed"


async def _collect_asset_snapshot(asset_id: str) -> dict[str, Any]:
    normalized_asset_id = str(asset_id or "").strip()
    asset_row = await media_assets_repo.get_media_asset(normalized_asset_id)
    if asset_row is None:
        return {
            "asset_id": normalized_asset_id,
            "asset": None,
            "lesson_media_references": [],
            "runtime_projection": [],
            "storage_verification": _empty_storage_verification(),
            "state_classification": "missing",
            "detected_inconsistencies": [
                _inconsistency(
                    "asset_missing",
                    "Media asset was not found",
                    severity="error",
                    asset_id=normalized_asset_id,
                )
            ],
            "truncation": {
                "lesson_media_references_truncated": False,
                "runtime_projection_truncated": False,
            },
            "correlation": {
                "asset_ids": [normalized_asset_id],
                "lesson_ids": [],
                "lesson_media_ids": [],
                "runtime_media_ids": [],
                "timestamps": [],
                "state_transitions": [],
            },
            "raw": {
                "asset_rows": [],
                "lesson_media_rows": [],
                "runtime_rows": [],
            },
        }

    lesson_media_rows_raw = list(
        await courses_repo.list_lesson_media_for_asset(
            normalized_asset_id,
            limit=_ASSET_REFERENCE_LIMIT + 1,
        )
    )
    purpose = _normalize_text(asset_row.get("purpose"))
    runtime_rows_raw = (
        []
        if purpose == "home_player_audio"
        else await runtime_media_repo.list_runtime_media_for_asset(
            normalized_asset_id,
            limit=_ASSET_REFERENCE_LIMIT + 1,
        )
    )

    lesson_media_truncated = len(lesson_media_rows_raw) > _ASSET_REFERENCE_LIMIT
    runtime_projection_truncated = len(runtime_rows_raw) > _ASSET_REFERENCE_LIMIT
    lesson_media_rows = lesson_media_rows_raw[:_ASSET_REFERENCE_LIMIT]
    runtime_rows = runtime_rows_raw[:_ASSET_REFERENCE_LIMIT]

    storage_verification = await _asset_storage_verification(asset_row)

    runtime_projection: list[dict[str, Any]] = []
    runtime_by_lesson_media_id: dict[str, list[dict[str, Any]]] = {}
    for row in runtime_rows:
        lesson_media_id = _normalize_text(row.get("lesson_media_id"))
        if lesson_media_id:
            runtime_by_lesson_media_id.setdefault(lesson_media_id, []).append(row)

    inconsistencies: list[dict[str, Any]] = []
    normalized_asset = _normalize_asset_row(asset_row)
    state = _normalize_text(asset_row.get("state"))
    active_home_upload = (
        await home_audio_sources_repo.get_active_home_upload_by_media_asset_id(
            normalized_asset_id
        )
        if purpose == "home_player_audio"
        else None
    )

    if normalized_asset is None:
        raise RuntimeError("asset normalization failed")

    for row in runtime_rows:
        resolution: RuntimeMediaResolution | None = None
        kind = _normalize_kind(row.get("kind"))
        if _playback_kind(kind) and bool(row.get("active")):
            resolution = await media_resolver_service.inspect_runtime_media(str(row["id"]))

        runtime_projection.append(_normalize_runtime_resolution(row, resolution))

        runtime_asset_id = _normalize_text(row.get("media_asset_id"))
        if runtime_asset_id and runtime_asset_id != normalized_asset["asset_id"]:
            inconsistencies.append(
                _inconsistency(
                    "runtime_asset_link_mismatch",
                    "Runtime projection points at a different media asset",
                    severity="error",
                    asset_id=normalized_asset["asset_id"],
                    lesson_id=_normalize_text(row.get("lesson_id")),
                    lesson_media_id=_normalize_text(row.get("lesson_media_id")),
                    runtime_media_id=str(row["id"]),
                    details={"runtime_asset_id": runtime_asset_id},
                )
            )

        if purpose in _LESSON_LINKED_PURPOSES and not _normalize_text(row.get("lesson_media_id")):
            inconsistencies.append(
                _inconsistency(
                    "runtime_missing_lesson_media_link",
                    "Lesson-bound asset has a runtime row without lesson_media_id",
                    severity="error",
                    asset_id=normalized_asset["asset_id"],
                    lesson_id=_normalize_text(row.get("lesson_id")),
                    runtime_media_id=str(row["id"]),
                )
            )

        if kind == "document" and bool(row.get("active")):
            inconsistencies.append(
                _inconsistency(
                    "document_projection_should_be_inactive",
                    "Document runtime projections should remain inactive",
                    severity="error",
                    asset_id=normalized_asset["asset_id"],
                    lesson_id=_normalize_text(row.get("lesson_id")),
                    lesson_media_id=_normalize_text(row.get("lesson_media_id")),
                    runtime_media_id=str(row["id"]),
                )
            )

        if resolution is not None and state == "ready" and not resolution.is_playable:
            inconsistencies.append(
                _inconsistency(
                    "ready_asset_unplayable_projection",
                    "Ready asset resolved to an unplayable runtime projection",
                    severity="error",
                    asset_id=normalized_asset["asset_id"],
                    lesson_id=resolution.lesson_id,
                    lesson_media_id=resolution.lesson_media_id,
                    runtime_media_id=resolution.runtime_media_id,
                    details={"failure_reason": resolution.failure_reason.value},
                )
            )

    lesson_media_references: list[dict[str, Any]] = []
    for row in lesson_media_rows:
        normalized_row = _normalize_lesson_media_row(row)
        lesson_media_references.append(normalized_row)
        lesson_media_id = normalized_row["lesson_media_id"]
        runtime_matches = runtime_by_lesson_media_id.get(lesson_media_id) or []
        expected_kind = normalized_asset["media_type"]
        row_kind = normalized_row["kind"]

        if normalized_row["asset_id"] != normalized_asset["asset_id"]:
            inconsistencies.append(
                _inconsistency(
                    "lesson_media_asset_link_mismatch",
                    "lesson_media row points at a different asset than requested",
                    severity="error",
                    asset_id=normalized_asset["asset_id"],
                    lesson_id=normalized_row["lesson_id"],
                    lesson_media_id=lesson_media_id,
                    details={"lesson_media_asset_id": normalized_row["asset_id"]},
                )
            )

        if (
            expected_kind
            and row_kind
            and expected_kind != row_kind
            and not {expected_kind, row_kind} <= {"document", "other"}
        ):
            inconsistencies.append(
                _inconsistency(
                    "lesson_media_kind_mismatch",
                    "lesson_media kind does not match the asset media_type",
                    severity="error",
                    asset_id=normalized_asset["asset_id"],
                    lesson_id=normalized_row["lesson_id"],
                    lesson_media_id=lesson_media_id,
                    details={
                        "asset_media_type": expected_kind,
                        "lesson_media_kind": row_kind,
                    },
                )
            )

        if purpose in _LESSON_LINKED_PURPOSES and not runtime_matches:
            inconsistencies.append(
                _inconsistency(
                    "runtime_projection_missing",
                    "lesson_media row has no runtime projection",
                    severity="error",
                    asset_id=normalized_asset["asset_id"],
                    lesson_id=normalized_row["lesson_id"],
                    lesson_media_id=lesson_media_id,
                )
            )

        if normalized_row["issue_reason"]:
            inconsistencies.append(
                _inconsistency(
                    "lesson_media_issue_reported",
                    "lesson_media has an active issue record",
                    severity="warning",
                    asset_id=normalized_asset["asset_id"],
                    lesson_id=normalized_row["lesson_id"],
                    lesson_media_id=lesson_media_id,
                    details={"issue_reason": normalized_row["issue_reason"]},
                )
            )

    storage_checks = {
        item.get("label"): item for item in storage_verification.get("checks") or []
    }
    playback_check = storage_checks.get("playback") or {}
    if state == "ready" and playback_check.get("storage_path") and playback_check.get("exists") is False:
        inconsistencies.append(
            _inconsistency(
                "playback_object_missing",
                "Ready asset playback object is missing from storage catalog",
                severity="error",
                asset_id=normalized_asset["asset_id"],
                lesson_id=normalized_asset["lesson_id"],
                details={"bucket": playback_check.get("bucket"), "path": playback_check.get("storage_path")},
            )
        )

    if state == "failed" and not normalized_asset.get("error_message"):
        inconsistencies.append(
            _inconsistency(
                "failed_asset_missing_error_message",
                "Failed asset has no error_message recorded",
                severity="warning",
                asset_id=normalized_asset["asset_id"],
                lesson_id=normalized_asset["lesson_id"],
            )
        )

    if purpose in _LESSON_LINKED_PURPOSES and state in {"ready", "failed"} and not lesson_media_rows:
        inconsistencies.append(
            _inconsistency(
                "lesson_media_link_missing",
                "Lesson-scoped asset has no lesson_media reference",
                severity="error",
                asset_id=normalized_asset["asset_id"],
                lesson_id=normalized_asset["lesson_id"],
            )
        )

    if lesson_media_truncated:
        inconsistencies.append(
            _inconsistency(
                "lesson_media_reference_scan_truncated",
                "Lesson media reference scan was truncated",
                severity="warning",
                asset_id=normalized_asset["asset_id"],
                lesson_id=normalized_asset["lesson_id"],
                details={"limit_applied": _ASSET_REFERENCE_LIMIT},
            )
        )
    if runtime_projection_truncated:
        inconsistencies.append(
            _inconsistency(
                "runtime_projection_scan_truncated",
                "Runtime projection scan was truncated",
                severity="warning",
                asset_id=normalized_asset["asset_id"],
                lesson_id=normalized_asset["lesson_id"],
                details={"limit_applied": _ASSET_REFERENCE_LIMIT},
            )
        )

    sorted_inconsistencies = _sort_inconsistencies(inconsistencies)

    return {
        "asset_id": normalized_asset["asset_id"],
        "asset": normalized_asset,
        "lesson_media_references": lesson_media_references,
        "runtime_projection": runtime_projection,
        "storage_verification": storage_verification,
        "state_classification": _asset_snapshot_classification(
            asset_row=asset_row,
            purpose=purpose,
            inconsistencies=sorted_inconsistencies,
            lesson_media_rows=lesson_media_rows,
            runtime_rows=runtime_rows,
            has_home_audio_source=active_home_upload is not None,
        ),
        "detected_inconsistencies": sorted_inconsistencies,
        "truncation": {
            "lesson_media_references_truncated": lesson_media_truncated,
            "runtime_projection_truncated": runtime_projection_truncated,
        },
        "correlation": _build_correlation(
            asset_rows=[asset_row],
            lesson_media_rows=lesson_media_rows,
            runtime_rows=runtime_rows,
        ),
        "raw": {
            "asset_rows": [asset_row],
            "lesson_media_rows": lesson_media_rows,
            "runtime_rows": runtime_rows,
        },
    }


def _normalize_log_event(event: dict[str, Any]) -> dict[str, Any]:
    return {
        "timestamp": event.get("timestamp"),
        "level": event.get("level"),
        "logger": event.get("logger"),
        "component": event.get("component"),
        "event": event.get("event"),
        "message": event.get("message"),
        "fields": log_buffer.sanitize_value(event.get("fields") or {}),
    }


def _sort_log_events(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        items,
        key=lambda item: (
            _parse_timestamp(item.get("timestamp")),
            str(item.get("logger") or ""),
            str(item.get("event") or ""),
            str(item.get("message") or ""),
        ),
    )


def _event_matches_asset(event: dict[str, Any], asset_id: str) -> bool:
    fields = event.get("fields") or {}
    for key in ("asset_id", "media_asset_id", "media_id"):
        if str(fields.get(key) or "").strip() == asset_id:
            return True
    return asset_id in str(event.get("message") or "")


def _resolution_failure_transition(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "timestamp": _iso(row.get("created_at")),
        "transition": "resolution_failure_recorded",
        "source": "media_resolution_failures",
        "asset_id": _normalize_text(row.get("media_asset_id")),
        "lesson_id": _normalize_text(row.get("lesson_id")),
        "lesson_media_id": _normalize_text(row.get("lesson_media_id")),
        "runtime_media_id": None,
        "state": "resolution_failed",
        "certainty": "observed",
        "details": {
            "mode": _normalize_text(row.get("mode")),
            "reason": _normalize_text(row.get("reason")),
        },
    }


async def get_asset(asset_id: str) -> dict[str, Any]:
    snapshot = await _collect_asset_snapshot(asset_id)
    evaluated_at = _iso(_now())
    return {
        "generated_at": evaluated_at,
        "validation": _validation_metadata(evaluated_at),
        "asset_id": snapshot["asset_id"],
        "state_classification": snapshot["state_classification"],
        "detected_inconsistencies": snapshot["detected_inconsistencies"],
        "asset": snapshot["asset"],
        "lesson_media_references": snapshot["lesson_media_references"],
        "runtime_projection": snapshot["runtime_projection"],
        "storage_verification": snapshot["storage_verification"],
        "correlation": snapshot["correlation"],
        "truncation": snapshot["truncation"],
    }


async def trace_asset_lifecycle(asset_id: str) -> dict[str, Any]:
    snapshot = await _collect_asset_snapshot(asset_id)
    normalized_asset_id = snapshot["asset_id"]
    resolution_failures = await media_resolution_failures_repo.list_recent_media_resolution_failures(
        limit=_TRACE_FAILURE_LIMIT,
        media_asset_id=normalized_asset_id,
    )
    related_logs = [
        _normalize_log_event(event)
        for event in log_buffer.list_events(
            limit=_TRACE_LOG_LIMIT * 3,
            logger_names=_RELATED_LOGGERS,
        )
        if _event_matches_asset(event, normalized_asset_id)
    ]
    related_logs = _sort_log_events(related_logs)[:_TRACE_LOG_LIMIT]

    failure_transitions = [
        _resolution_failure_transition(row)
        for row in resolution_failures
    ]
    correlation = _build_correlation(
        asset_rows=snapshot["raw"]["asset_rows"],
        lesson_media_rows=snapshot["raw"]["lesson_media_rows"],
        runtime_rows=snapshot["raw"]["runtime_rows"],
        extra_transitions=failure_transitions,
    )

    state_classification = snapshot["state_classification"]
    if snapshot["asset"] is None:
        state_classification = "missing"
    elif snapshot["asset"].get("state") == "failed":
        state_classification = "failed"
    elif snapshot["asset"].get("state") in {"pending_upload", "uploaded", "processing"}:
        state_classification = "in_progress"
    elif snapshot["detected_inconsistencies"]:
        state_classification = "inconsistent"
    else:
        state_classification = "ready"

    evaluated_at = _iso(_now())
    return {
        "generated_at": evaluated_at,
        "validation": _validation_metadata(evaluated_at),
        "asset_id": normalized_asset_id,
        "storage_verification": snapshot["storage_verification"],
        "timeline_mode": "reconstructed_snapshot_timeline",
        "state_classification": state_classification,
        "detected_inconsistencies": snapshot["detected_inconsistencies"],
        "asset": snapshot["asset"],
        "state_transitions": correlation["state_transitions"],
        "related_resolution_failures": [
            {
                "timestamp": _iso(row.get("created_at")),
                "lesson_media_id": _normalize_text(row.get("lesson_media_id")),
                "lesson_id": _normalize_text(row.get("lesson_id")),
                "asset_id": _normalize_text(row.get("media_asset_id")),
                "mode": _normalize_text(row.get("mode")),
                "reason": _normalize_text(row.get("reason")),
                "details": log_buffer.sanitize_value(row.get("details") or {}),
            }
            for row in resolution_failures
        ],
        "related_log_events": related_logs,
        "correlation": correlation,
    }


async def list_orphaned_assets() -> dict[str, Any]:
    rows = await media_assets_repo.list_orphaned_control_plane_assets(
        limit=_ORPHANED_ASSET_LIMIT + 1
    )
    truncated = len(rows) > _ORPHANED_ASSET_LIMIT
    rows = rows[:_ORPHANED_ASSET_LIMIT]

    orphaned_assets: list[dict[str, Any]] = []
    inconsistencies: list[dict[str, Any]] = []
    evaluated_at = _iso(_now())
    for row in rows:
        normalized_asset = _normalize_asset_row(row)
        if normalized_asset is None:
            continue
        age_seconds = _asset_unlinked_age_seconds(row)
        item_classification = _unlinked_asset_state_classification(
            row,
            runtime_gap=False,
        )
        item_inconsistencies: list[dict[str, Any]] = []
        if normalized_asset.get("state") == "failed" and not normalized_asset.get("error_message"):
            item_inconsistencies.append(
                _inconsistency(
                    "failed_asset_missing_error_message",
                    "Failed asset has no error_message recorded",
                    severity="warning",
                    asset_id=normalized_asset["asset_id"],
                )
            )

        correlation = _build_correlation(
            asset_rows=[row],
            lesson_media_rows=[],
            runtime_rows=[],
        )
        sorted_item_inconsistencies = _sort_inconsistencies(item_inconsistencies)
        orphaned_assets.append(
            {
                "asset": normalized_asset,
                "state_classification": item_classification,
                "detected_inconsistencies": sorted_item_inconsistencies,
                "reference_counts": {
                    "lesson_media": int(row.get("lesson_media_count") or 0),
                    "runtime_media": int(row.get("runtime_media_count") or 0),
                    "home_player_uploads": int(row.get("home_player_upload_count") or 0),
                },
                "linkage_timing": {
                    "evaluated_at": evaluated_at,
                    "age_seconds": age_seconds,
                    "grace_window_seconds": (
                        _UNLINKED_ASSET_GRACE_SECONDS
                        if normalized_asset.get("state")
                        in {"pending_upload", "uploaded", "processing"}
                        else None
                    ),
                    "within_grace_window": (
                        None
                        if normalized_asset.get("state")
                        not in {"pending_upload", "uploaded", "processing"}
                        else age_seconds is None
                        or age_seconds <= _UNLINKED_ASSET_GRACE_SECONDS
                    ),
                },
                "correlation": correlation,
            }
        )
        inconsistencies.extend(sorted_item_inconsistencies)

    if truncated:
        inconsistencies.append(
            _inconsistency(
                "orphaned_asset_scan_truncated",
                "Orphaned asset scan was truncated",
                severity="warning",
                details={"limit_applied": _ORPHANED_ASSET_LIMIT},
            )
        )

    summary = Counter(item["state_classification"] for item in orphaned_assets)
    state_classification = "healthy"
    if any(
        item["state_classification"]
        in {"runtime_projection_gap", "unlinked_stalled", "failed_unlinked"}
        for item in orphaned_assets
    ):
        state_classification = "inconsistent"
    elif orphaned_assets:
        state_classification = "warning"

    return {
        "generated_at": evaluated_at,
        "validation": _validation_metadata(evaluated_at),
        "inspection_scope": "unlinked_control_plane_assets",
        "state_classification": state_classification,
        "detected_inconsistencies": _sort_inconsistencies(inconsistencies),
        "orphaned_assets": orphaned_assets,
        "summary": {
            "limit_applied": _ORPHANED_ASSET_LIMIT,
            "truncated": truncated,
            "total_assets": len(orphaned_assets),
            "grace_window_seconds": _UNLINKED_ASSET_GRACE_SECONDS,
            "classification_counts": dict(sorted(summary.items())),
        },
    }


def _projection_item_classification(
    *,
    media_type: str | None,
    media_state: str | None,
    expects_asset: bool,
    has_asset: bool,
    resolution: RuntimeMediaResolution | None,
    runtime_row: dict[str, Any] | None,
    inconsistencies: list[dict[str, Any]],
) -> str:
    if expects_asset and not has_asset:
        return "asset_missing"
    if inconsistencies:
        return "inconsistent"
    if media_type == "document":
        return "non_playback"
    if resolution is not None and resolution.is_playable:
        return "consistent"
    if runtime_row is None:
        return "runtime_missing"
    if media_state in {"pending_upload", "uploaded", "processing"}:
        return "in_progress"
    return "unresolved"


async def validate_runtime_projection(lesson_id: str) -> dict[str, Any]:
    normalized_lesson_id = str(lesson_id or "").strip()
    lesson_row = await courses_repo.get_lesson(normalized_lesson_id)
    evaluated_at = _iso(_now())
    if lesson_row is None:
        return {
            "generated_at": evaluated_at,
            "validation": _validation_metadata(evaluated_at),
            "lesson_id": normalized_lesson_id,
            "storage_verification": _empty_storage_verification(include_checks=False),
            "state_classification": "missing",
            "detected_inconsistencies": [
                _inconsistency(
                    "lesson_missing",
                    "Lesson was not found",
                    severity="error",
                    lesson_id=normalized_lesson_id,
                )
            ],
            "lesson": None,
            "lesson_media": [],
            "runtime_rows_without_lesson_media": [],
            "summary": {
                "limit_applied": _RUNTIME_VALIDATION_LIMIT,
                "truncated": False,
                "lesson_media_count": 0,
                "runtime_row_count": 0,
                "runtime_rows_without_lesson_media_count": 0,
                "classification_counts": {},
            },
            "correlation": {
                "asset_ids": [],
                "lesson_ids": [normalized_lesson_id],
                "lesson_media_ids": [],
                "runtime_media_ids": [],
                "timestamps": [],
                "state_transitions": [],
            },
        }

    lesson_media_rows_raw = list(
        await courses_repo.list_lesson_media(
            normalized_lesson_id,
            limit=_RUNTIME_VALIDATION_LIMIT + 1,
        )
    )
    runtime_rows_raw = await runtime_media_repo.list_runtime_media_for_lesson(
        normalized_lesson_id,
        limit=_RUNTIME_VALIDATION_LIMIT + 1,
    )
    lesson_media_truncated = len(lesson_media_rows_raw) > _RUNTIME_VALIDATION_LIMIT
    runtime_rows_truncated = len(runtime_rows_raw) > _RUNTIME_VALIDATION_LIMIT
    lesson_media_rows = lesson_media_rows_raw[:_RUNTIME_VALIDATION_LIMIT]
    runtime_rows = runtime_rows_raw[:_RUNTIME_VALIDATION_LIMIT]

    asset_ids = _sorted_dedupe_strings(
        [_normalize_text(row.get("media_asset_id")) for row in lesson_media_rows]
    )
    asset_map = await media_assets_repo.get_media_assets(asset_ids)

    runtime_by_lesson_media_id: dict[str, list[dict[str, Any]]] = {}
    for row in runtime_rows:
        lesson_media_id = _normalize_text(row.get("lesson_media_id"))
        if lesson_media_id:
            runtime_by_lesson_media_id.setdefault(lesson_media_id, []).append(row)
    for lesson_media_id, runtime_matches in runtime_by_lesson_media_id.items():
        runtime_by_lesson_media_id[lesson_media_id] = sorted(
            runtime_matches,
            key=_runtime_sort_key,
            reverse=True,
        )

    known_lesson_media_ids = {
        str(row.get("id"))
        for row in lesson_media_rows
        if row.get("id")
    }
    extra_runtime_rows = [
        row
        for row in runtime_rows
        if _normalize_text(row.get("lesson_media_id")) not in known_lesson_media_ids
    ]

    lesson_media_items: list[dict[str, Any]] = []
    all_inconsistencies: list[dict[str, Any]] = []
    for row in lesson_media_rows:
        lesson_media_id = str(row["id"])
        normalized_lesson_media = _normalize_lesson_media_row(row)
        asset_id = normalized_lesson_media["asset_id"]
        asset_row = asset_map.get(asset_id or "")
        normalized_asset = _normalize_asset_row(asset_row)
        expected_runtime_contract = _expected_runtime_contract(
            lesson_row=lesson_row,
            lesson_media_row=row,
        )
        runtime_matches = runtime_by_lesson_media_id.get(lesson_media_id) or []
        runtime_row = runtime_matches[0] if runtime_matches else None
        actual_runtime_contract = (
            _actual_runtime_contract(runtime_row)
            if runtime_row is not None
            else None
        )
        resolution: RuntimeMediaResolution | None = None
        item_inconsistencies: list[dict[str, Any]] = []
        contract_diffs: list[dict[str, Any]] = []
        kind = normalized_lesson_media["kind"]
        media_state = normalized_lesson_media["media_state"]

        if len(runtime_matches) > 1:
            item_inconsistencies.append(
                _inconsistency(
                    "duplicate_runtime_rows",
                    "Multiple runtime rows point at the same lesson_media id",
                    severity="error",
                    asset_id=asset_id,
                    lesson_id=normalized_lesson_id,
                    lesson_media_id=lesson_media_id,
                    details={"runtime_media_ids": [str(item["id"]) for item in runtime_matches]},
                )
            )

        if asset_id is not None and asset_row is None:
            item_inconsistencies.append(
                _inconsistency(
                    "asset_missing",
                    "lesson_media references a media_asset that does not exist",
                    severity="error",
                    asset_id=asset_id,
                    lesson_id=normalized_lesson_id,
                    lesson_media_id=lesson_media_id,
                )
            )
        elif asset_row is not None and _normalize_text(asset_row.get("lesson_id")) not in {
            None,
            normalized_lesson_id,
        }:
            item_inconsistencies.append(
                _inconsistency(
                    "asset_lesson_scope_mismatch",
                    "media_asset.lesson_id does not match the lesson being validated",
                    severity="error",
                    asset_id=asset_id,
                    lesson_id=normalized_lesson_id,
                    lesson_media_id=lesson_media_id,
                    details={"asset_lesson_id": _normalize_text(asset_row.get("lesson_id"))},
                )
            )

        if runtime_row is None:
            item_inconsistencies.append(
                _inconsistency(
                    "runtime_media_missing",
                    "lesson_media has no runtime_media projection",
                    severity="error",
                    asset_id=asset_id,
                    lesson_id=normalized_lesson_id,
                    lesson_media_id=lesson_media_id,
                )
            )
        else:
            contract_diffs = _runtime_contract_diffs(
                expected=expected_runtime_contract,
                actual=actual_runtime_contract,
            )
            if contract_diffs:
                item_inconsistencies.append(
                    _inconsistency(
                        "runtime_contract_mismatch",
                        "runtime_media row does not match the expected lesson_media contract",
                        severity="error",
                        asset_id=asset_id,
                        lesson_id=normalized_lesson_id,
                        lesson_media_id=lesson_media_id,
                        runtime_media_id=str(runtime_row["id"]),
                        details={"diffs": contract_diffs},
                    )
                )

            if _normalize_text(runtime_row.get("media_asset_id")) != asset_id:
                item_inconsistencies.append(
                    _inconsistency(
                        "runtime_asset_link_mismatch",
                        "runtime_media points at a different asset than lesson_media",
                        severity="error",
                        asset_id=asset_id,
                        lesson_id=normalized_lesson_id,
                        lesson_media_id=lesson_media_id,
                        runtime_media_id=str(runtime_row["id"]),
                        details={"runtime_asset_id": _normalize_text(runtime_row.get("media_asset_id"))},
                    )
                )

            if kind == "document":
                if bool(runtime_row.get("active")):
                    item_inconsistencies.append(
                        _inconsistency(
                            "document_projection_should_be_inactive",
                            "Document runtime projections should remain inactive",
                            severity="error",
                            asset_id=asset_id,
                            lesson_id=normalized_lesson_id,
                            lesson_media_id=lesson_media_id,
                            runtime_media_id=str(runtime_row["id"]),
                        )
                    )
            elif _playback_kind(kind):
                resolution = await media_resolver_service.inspect_runtime_media(str(runtime_row["id"]))
                if resolution.lesson_media_id != lesson_media_id:
                    item_inconsistencies.append(
                        _inconsistency(
                            "resolver_lesson_media_mismatch",
                            "Resolver returned a different lesson_media id than requested",
                            severity="error",
                            asset_id=asset_id,
                            lesson_id=normalized_lesson_id,
                            lesson_media_id=lesson_media_id,
                            runtime_media_id=str(runtime_row["id"]),
                            details={"resolved_lesson_media_id": resolution.lesson_media_id},
                        )
                    )
                if resolution.lesson_id not in {None, normalized_lesson_id}:
                    item_inconsistencies.append(
                        _inconsistency(
                            "resolver_lesson_scope_mismatch",
                            "Resolver returned a different lesson id than requested",
                            severity="error",
                            asset_id=asset_id,
                            lesson_id=normalized_lesson_id,
                            lesson_media_id=lesson_media_id,
                            runtime_media_id=str(runtime_row["id"]),
                            details={"resolved_lesson_id": resolution.lesson_id},
                        )
                    )
                if resolution.media_asset_id not in {None, asset_id}:
                    item_inconsistencies.append(
                        _inconsistency(
                            "resolver_asset_mismatch",
                            "Resolver returned a different asset id than lesson_media",
                            severity="error",
                            asset_id=asset_id,
                            lesson_id=normalized_lesson_id,
                            lesson_media_id=lesson_media_id,
                            runtime_media_id=str(runtime_row["id"]),
                            details={"resolved_asset_id": resolution.media_asset_id},
                        )
                    )
                if not resolution.is_playable and media_state == "ready":
                    item_inconsistencies.append(
                        _inconsistency(
                            "ready_lesson_media_unplayable",
                            "Ready lesson_media resolved to an unplayable runtime projection",
                            severity="error",
                            asset_id=asset_id,
                            lesson_id=normalized_lesson_id,
                            lesson_media_id=lesson_media_id,
                            runtime_media_id=str(runtime_row["id"]),
                            details={"failure_reason": resolution.failure_reason.value},
                        )
                    )

        if normalized_lesson_media["issue_reason"]:
            item_inconsistencies.append(
                _inconsistency(
                    "lesson_media_issue_reported",
                    "lesson_media has an active issue record",
                    severity="warning",
                    asset_id=asset_id,
                    lesson_id=normalized_lesson_id,
                    lesson_media_id=lesson_media_id,
                    details={"issue_reason": normalized_lesson_media["issue_reason"]},
                )
            )

        sorted_item_inconsistencies = _sort_inconsistencies(item_inconsistencies)
        normalized_runtime = (
            _normalize_runtime_resolution(runtime_row, resolution)
            if runtime_row is not None
            else None
        )
        item_correlation = _build_correlation(
            asset_rows=[asset_row] if asset_row is not None else [],
            lesson_media_rows=[row],
            runtime_rows=[runtime_row] if runtime_row is not None else [],
        )
        lesson_media_items.append(
            {
                "lesson_media": normalized_lesson_media,
                "asset": normalized_asset,
                "runtime_projection": normalized_runtime,
                "expected_runtime_contract": expected_runtime_contract,
                "actual_runtime_contract": actual_runtime_contract,
                "contract_diffs": contract_diffs,
                "state_classification": _projection_item_classification(
                    media_type=kind,
                    media_state=media_state,
                    expects_asset=asset_id is not None,
                    has_asset=asset_row is not None,
                    resolution=resolution,
                    runtime_row=runtime_row,
                    inconsistencies=sorted_item_inconsistencies,
                ),
                "detected_inconsistencies": sorted_item_inconsistencies,
                "correlation": item_correlation,
            }
        )
        all_inconsistencies.extend(sorted_item_inconsistencies)

    extra_runtime_items = [
        {
            "runtime_projection": _normalize_runtime_row(row),
            "state_classification": "unexpected_runtime_row",
            "detected_inconsistencies": [
                _inconsistency(
                    "unexpected_runtime_row",
                    "runtime_media row does not map to any lesson_media in this lesson snapshot",
                    severity="error",
                    asset_id=_normalize_text(row.get("media_asset_id")),
                    lesson_id=normalized_lesson_id,
                    lesson_media_id=_normalize_text(row.get("lesson_media_id")),
                    runtime_media_id=str(row["id"]),
                )
            ],
        }
        for row in extra_runtime_rows
    ]
    for item in extra_runtime_items:
        all_inconsistencies.extend(item["detected_inconsistencies"])

    non_truncation_inconsistencies = list(all_inconsistencies)
    if lesson_media_truncated or runtime_rows_truncated:
        all_inconsistencies.append(
            _inconsistency(
                "projection_validation_truncated",
                "Projection validation scan was truncated",
                severity="warning",
                lesson_id=normalized_lesson_id,
                details={"limit_applied": _RUNTIME_VALIDATION_LIMIT},
            )
        )

    overall_classification = "consistent"
    if non_truncation_inconsistencies:
        overall_classification = "inconsistent"
    elif lesson_media_truncated or runtime_rows_truncated:
        overall_classification = "partial"

    classification_counts = Counter(
        item["state_classification"] for item in lesson_media_items
    )
    lesson_normalized = {
        "lesson_id": str(lesson_row["id"]),
        "course_id": _normalize_text(lesson_row.get("course_id")),
        "lesson_title": _normalize_text(lesson_row.get("lesson_title")),
        "position": _normalize_int(lesson_row.get("position")),
        "created_at": _iso(lesson_row.get("created_at")),
        "updated_at": _iso(lesson_row.get("updated_at")),
    }

    correlation = _build_correlation(
        asset_rows=sorted(
            [
                asset
                for asset in asset_map.values()
                if asset is not None
                and _normalize_text(asset.get("lesson_id")) == normalized_lesson_id
            ],
            key=_asset_sort_key,
        ),
        lesson_media_rows=lesson_media_rows,
        runtime_rows=runtime_rows,
    )
    storage_verification = await _aggregate_storage_verification(
        [
            asset
            for asset in asset_map.values()
            if asset is not None
            and _normalize_text(asset.get("lesson_id")) == normalized_lesson_id
        ]
    )

    return {
        "generated_at": evaluated_at,
        "validation": _validation_metadata(evaluated_at),
        "lesson_id": normalized_lesson_id,
        "storage_verification": storage_verification,
        "state_classification": overall_classification,
        "detected_inconsistencies": _sort_inconsistencies(all_inconsistencies),
        "lesson": lesson_normalized,
        "lesson_media": lesson_media_items,
        "runtime_rows_without_lesson_media": extra_runtime_items,
        "summary": {
            "limit_applied": _RUNTIME_VALIDATION_LIMIT,
            "truncated": bool(lesson_media_truncated or runtime_rows_truncated),
            "lesson_media_count": len(lesson_media_items),
            "runtime_row_count": len(runtime_rows),
            "runtime_rows_without_lesson_media_count": len(extra_runtime_items),
            "classification_counts": dict(sorted(classification_counts.items())),
        },
        "correlation": correlation,
    }
