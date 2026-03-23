from __future__ import annotations

import asyncio
from typing import Any, Mapping, Sequence

from .. import logs_observability, media_control_plane_observability
from .common import (
    failure_count,
    iso,
    media_transcode_status,
    now,
    normalize_text,
    sort_inconsistencies,
    sort_violations,
    status_from_violations,
    unique_sorted_strings,
    violation,
    wrap_upstream_inconsistency,
)


def _recent_failure_violation(
    *,
    source: str,
    asset_id: str | None = None,
    lesson_id: str | None = None,
    summary: Mapping[str, Any] | None = None,
) -> dict[str, Any] | None:
    total_failures = failure_count(summary)
    if total_failures <= 0:
        return None
    subject = {
        key: value
        for key, value in {
            "asset_id": asset_id,
            "lesson_id": lesson_id,
        }.items()
        if value is not None
    }
    return violation(
        "recent_media_failures_detected",
        f"Recent media failures were observed for {'asset ' + asset_id if asset_id else 'this lesson'}",
        source=source,
        severity_value="warning",
        subject=subject,
        details={
            "failure_count": total_failures,
            "summary": dict(summary or {}),
        },
    )


def _worker_violation(worker_health_payload: Mapping[str, Any]) -> dict[str, Any] | None:
    status = media_transcode_status(worker_health_payload)
    if status in {None, "ok"}:
        return None
    return violation(
        f"media_transcode_worker_{status}",
        f"Media transcode worker status is {status}",
        source="logs.get_worker_health",
        severity_value="warning" if status == "disabled" else "error",
        details={
            "status": status,
        },
    )


def _wrap_inconsistencies(
    items: Sequence[Mapping[str, Any]],
    *,
    source: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    violations: list[dict[str, Any]] = []
    inconsistencies: list[dict[str, Any]] = []
    for item in items:
        wrapped_violation, wrapped_inconsistency = wrap_upstream_inconsistency(
            item,
            source=source,
        )
        violations.append(wrapped_violation)
        inconsistencies.append(wrapped_inconsistency)
    return violations, inconsistencies


async def _inspect_asset(asset_id: str) -> dict[str, Any]:
    asset_snapshot, media_failures, worker_health = await asyncio.gather(
        media_control_plane_observability.get_asset(asset_id),
        logs_observability.get_media_failures(asset_id=asset_id),
        logs_observability.get_worker_health(),
    )

    wrapped_violations, wrapped_inconsistencies = _wrap_inconsistencies(
        asset_snapshot.get("detected_inconsistencies") or [],
        source="media_control_plane.get_asset",
    )
    failure_violation = _recent_failure_violation(
        source="logs.get_media_failures",
        asset_id=asset_id,
        summary=media_failures.get("summary"),
    )
    if failure_violation is not None:
        wrapped_violations.append(failure_violation)
    worker_violation = _worker_violation(worker_health)
    if worker_violation is not None:
        wrapped_violations.append(worker_violation)

    sorted_violations = sort_violations(wrapped_violations)
    sorted_inconsistencies = sort_inconsistencies(wrapped_inconsistencies)
    asset = asset_snapshot.get("asset") or {}
    lesson_media_references = list(asset_snapshot.get("lesson_media_references") or [])
    runtime_projection = list(asset_snapshot.get("runtime_projection") or [])
    generated_at = iso(now())
    return {
        "generated_at": generated_at,
        "inspection": {
            "tool": "inspect_media",
            "version": "1",
        },
        "subject": {
            "mode": "asset",
            "asset_id": asset_id,
            "lesson_id": normalize_text(asset.get("lesson_id")),
        },
        "status": status_from_violations(
            sorted_violations,
            missing_subject=asset_snapshot.get("state_classification") == "missing",
        ),
        "violations": sorted_violations,
        "inconsistencies": sorted_inconsistencies,
        "state_summary": {
            "control_plane_state": asset_snapshot.get("state_classification"),
            "asset_count": 1 if asset_snapshot.get("asset") is not None else 0,
            "lesson_media_count": len(lesson_media_references),
            "runtime_media_count": len(runtime_projection),
            "recent_failure_count": failure_count(media_failures.get("summary") or {}),
            "worker_status": media_transcode_status(worker_health),
        },
        "truth_sources": {
            "media_control_plane": {
                "asset": asset_snapshot,
            },
            "logs": {
                "media_failures": media_failures,
                "worker_health": worker_health,
            },
        },
        "sources_consulted": [
            "media_control_plane.get_asset",
            "logs.get_media_failures",
            "logs.get_worker_health",
        ],
    }


async def _inspect_lesson(lesson_id: str) -> dict[str, Any]:
    projection, worker_health = await asyncio.gather(
        media_control_plane_observability.validate_runtime_projection(lesson_id),
        logs_observability.get_worker_health(),
    )
    lesson_media_items = list(projection.get("lesson_media") or [])
    asset_ids = unique_sorted_strings(
        (item.get("lesson_media") or {}).get("asset_id") for item in lesson_media_items
    )
    failure_payloads = await asyncio.gather(
        *(logs_observability.get_media_failures(asset_id=asset_id) for asset_id in asset_ids)
    )

    wrapped_violations, wrapped_inconsistencies = _wrap_inconsistencies(
        projection.get("detected_inconsistencies") or [],
        source="media_control_plane.validate_runtime_projection",
    )
    for asset_id, failure_payload in zip(asset_ids, failure_payloads, strict=False):
        failure_violation = _recent_failure_violation(
            source="logs.get_media_failures",
            asset_id=asset_id,
            lesson_id=lesson_id,
            summary=failure_payload.get("summary"),
        )
        if failure_violation is not None:
            wrapped_violations.append(failure_violation)
    worker_violation = _worker_violation(worker_health)
    if worker_violation is not None:
        wrapped_violations.append(worker_violation)

    runtime_media_count = sum(
        1 for item in lesson_media_items if (item.get("runtime_projection") or {}) != {}
    ) + len(projection.get("runtime_rows_without_lesson_media") or [])

    sorted_violations = sort_violations(wrapped_violations)
    sorted_inconsistencies = sort_inconsistencies(wrapped_inconsistencies)
    generated_at = iso(now())
    return {
        "generated_at": generated_at,
        "inspection": {
            "tool": "inspect_media",
            "version": "1",
        },
        "subject": {
            "mode": "lesson",
            "asset_id": None,
            "lesson_id": lesson_id,
        },
        "status": status_from_violations(
            sorted_violations,
            missing_subject=projection.get("state_classification") == "missing",
        ),
        "violations": sorted_violations,
        "inconsistencies": sorted_inconsistencies,
        "state_summary": {
            "control_plane_state": projection.get("state_classification"),
            "asset_count": len(asset_ids),
            "lesson_media_count": len(lesson_media_items),
            "runtime_media_count": runtime_media_count,
            "recent_failure_count": sum(
                failure_count(payload.get("summary") or {}) for payload in failure_payloads
            ),
            "worker_status": media_transcode_status(worker_health),
        },
        "truth_sources": {
            "media_control_plane": {
                "projection": projection,
            },
            "logs": {
                "asset_failures": [
                    {
                        "asset_id": asset_id,
                        "summary": dict(payload.get("summary") or {}),
                    }
                    for asset_id, payload in zip(asset_ids, failure_payloads, strict=False)
                ],
                "worker_health": worker_health,
            },
        },
        "sources_consulted": [
            "media_control_plane.validate_runtime_projection",
            "logs.get_media_failures",
            "logs.get_worker_health",
        ],
    }


async def inspect_media(
    asset_id: str | None = None,
    lesson_id: str | None = None,
) -> dict[str, Any]:
    normalized_asset_id = normalize_text(asset_id)
    normalized_lesson_id = normalize_text(lesson_id)
    if bool(normalized_asset_id) == bool(normalized_lesson_id):
        raise ValueError("Exactly one of asset_id or lesson_id is required")
    if normalized_asset_id is not None:
        return await _inspect_asset(normalized_asset_id)
    return await _inspect_lesson(normalized_lesson_id or "")
