from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Any, Mapping, Sequence

from ..media_control_plane.services.media_resolver_service import (
    RuntimeMediaResolution,
    media_resolver_service,
)
from ..repositories import courses as courses_repo
from . import courses_service, logs_observability, media_control_plane_observability

_PLAYBACK_KINDS = {"audio", "video", "image"}
_SEVERITY_RANK = {"error": 0, "warning": 1, "info": 2}
_TEST_CASE_COURSE_SCAN_LIMIT = 12
_TEST_CASE_COURSE_CASE_LIMIT = 4
_TEST_CASE_LESSON_CASE_LIMIT = 4
_TEST_CASE_LESSONS_PER_COURSE = 6
_PHASE2_LESSON_SAMPLE_LIMIT = 2
_PHASE2_COURSE_SAMPLE_LIMIT = 2
_PHASE2_RECENT_ERROR_LIMIT = 10


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _normalize_text(value: Any) -> str | None:
    normalized = str(value or "").strip()
    return normalized or None


def _severity(value: Any) -> str:
    normalized = str(value or "error").strip().lower()
    if normalized in {"error", "warning", "info"}:
        return normalized
    return "error"


def _sort_violations(items: Sequence[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        [dict(item) for item in items],
        key=lambda item: (
            _SEVERITY_RANK.get(_severity(item.get("severity")), 99),
            str(item.get("code") or ""),
            str(item.get("course_id") or ""),
            str(item.get("lesson_id") or ""),
            str(item.get("lesson_media_id") or ""),
            str(item.get("asset_id") or ""),
            str(item.get("runtime_media_id") or ""),
        ),
    )


def _error_count(items: Sequence[dict[str, Any]]) -> int:
    return sum(1 for item in items if _severity(item.get("severity")) == "error")


def _warning_count(items: Sequence[dict[str, Any]]) -> int:
    return sum(1 for item in items if _severity(item.get("severity")) == "warning")


def _verdict(items: Sequence[dict[str, Any]]) -> str:
    return "fail" if _error_count(items) > 0 else "pass"


def _confidence(
    *,
    has_logs: bool,
    has_media_truth: bool,
    has_resolver_truth: bool,
    missing_subject: bool = False,
) -> str:
    if missing_subject:
        return "low"
    evidence_count = int(has_logs) + int(has_media_truth) + int(has_resolver_truth)
    if evidence_count >= 3:
        return "high"
    if evidence_count == 2:
        return "medium"
    return "low"


def _violation(
    code: str,
    message: str,
    *,
    source: str,
    severity: str = "error",
    course_id: str | None = None,
    lesson_id: str | None = None,
    lesson_media_id: str | None = None,
    asset_id: str | None = None,
    runtime_media_id: str | None = None,
    details: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "code": code,
        "message": message,
        "severity": _severity(severity),
        "source": source,
        "course_id": course_id,
        "lesson_id": lesson_id,
        "lesson_media_id": lesson_media_id,
        "asset_id": asset_id,
        "runtime_media_id": runtime_media_id,
        "details": dict(details or {}),
    }


def _wrap_inconsistency(
    inconsistency: Mapping[str, Any],
    *,
    source: str,
    course_id: str | None = None,
) -> dict[str, Any]:
    return _violation(
        str(inconsistency.get("code") or "truth_violation"),
        str(inconsistency.get("message") or "Truth alignment violation detected"),
        source=source,
        severity=str(inconsistency.get("severity") or "error"),
        course_id=course_id,
        lesson_id=_normalize_text(inconsistency.get("lesson_id")),
        lesson_media_id=_normalize_text(inconsistency.get("lesson_media_id")),
        asset_id=_normalize_text(inconsistency.get("asset_id")),
        runtime_media_id=_normalize_text(inconsistency.get("runtime_media_id")),
        details=dict(inconsistency.get("details") or {}),
    )


def _worker_health_signal(worker_health: Mapping[str, Any]) -> dict[str, Any]:
    return dict((worker_health.get("worker_health") or {}).get("media_transcode") or {})


def _worker_environment_signals(worker_health: Mapping[str, Any]) -> dict[str, Any]:
    media_transcode = _worker_health_signal(worker_health)
    return {
        "worker_status": _normalize_text(media_transcode.get("status")) or "unknown",
        "worker_running": bool(media_transcode.get("worker_running")),
        "queue_summary": dict(media_transcode.get("queue_summary") or {}),
        "last_error": media_transcode.get("last_error"),
    }


def _worker_health_violations(
    worker_health: Mapping[str, Any],
    *,
    source: str,
    course_id: str | None = None,
    lesson_id: str | None = None,
) -> list[dict[str, Any]]:
    media_transcode = _worker_health_signal(worker_health)
    status = str(media_transcode.get("status") or "").strip().lower()
    if status in {"", "ok"}:
        return []
    severity = "warning" if status == "disabled" else "error"
    return [
        _violation(
            f"media_transcode_worker_{status}",
            f"Media transcode worker status is {status}",
            source=source,
            severity=severity,
            course_id=course_id,
            lesson_id=lesson_id,
            details={
                "status": status,
                "worker_running": bool(media_transcode.get("worker_running")),
                "queue_summary": dict(media_transcode.get("queue_summary") or {}),
            },
        )
    ]


def _asset_failure_violation(
    media_failures: Mapping[str, Any],
    *,
    source: str,
    course_id: str | None = None,
    lesson_id: str | None = None,
    asset_id: str | None = None,
) -> dict[str, Any] | None:
    summary = dict(media_failures.get("summary") or {})
    total_failures = sum(int(value or 0) for value in summary.values())
    if total_failures <= 0:
        return None
    return _violation(
        "recent_media_failures_detected",
        f"Recent media failures were observed for asset {asset_id or '<unknown>'}",
        source=source,
        severity="warning",
        course_id=course_id,
        lesson_id=lesson_id,
        asset_id=asset_id,
        details={"summary": summary, "failure_count": total_failures},
    )


def _normalize_resolution(resolution: RuntimeMediaResolution) -> dict[str, Any]:
    return {
        "runtime_media_id": resolution.runtime_media_id or None,
        "lesson_media_id": resolution.lesson_media_id,
        "lesson_id": resolution.lesson_id,
        "course_id": resolution.course_id,
        "media_asset_id": resolution.media_asset_id,
        "kind": resolution.kind,
        "content_type": resolution.content_type,
        "media_state": resolution.media_state,
        "is_playable": bool(resolution.is_playable),
        "playback_mode": resolution.playback_mode.value,
        "failure_reason": resolution.failure_reason.value,
        "failure_detail": resolution.failure_detail,
        "requires_legacy_fallback": bool(resolution.requires_legacy_fallback),
        "fallback_policy": resolution.fallback_policy,
        "active": bool(resolution.active),
        "storage_bucket": resolution.storage_bucket,
        "storage_path": resolution.storage_path,
        "duration_seconds": resolution.duration_seconds,
    }


def _lesson_media_row_from_item(item: Mapping[str, Any]) -> dict[str, Any]:
    return dict(item.get("lesson_media") or {})


def _course_summary_row(course_row: Mapping[str, Any] | None, *, course_id: str) -> dict[str, Any] | None:
    if course_row is None:
        return None
    return {
        "course_id": course_id,
        "slug": _normalize_text(course_row.get("slug")),
        "title": _normalize_text(course_row.get("title")),
        "cover_media_id": _normalize_text(course_row.get("cover_media_id")),
        "cover_url": _normalize_text(course_row.get("cover_url")),
    }


def _sample_result(
    payload: Mapping[str, Any],
    *,
    tool_name: str,
    subject_field: str,
) -> dict[str, Any]:
    subject_id = _normalize_text(payload.get(subject_field))
    return {
        "tool": tool_name,
        "subject": {subject_field: subject_id},
        "verdict": str(payload.get("verdict") or "fail"),
        "confidence": str(payload.get("confidence") or "low"),
        "violation_codes": [
            str(item.get("code"))
            for item in payload.get("violations") or []
            if item.get("code")
        ],
    }


async def verify_lesson_media_truth(lesson_id: str) -> dict[str, Any]:
    normalized_lesson_id = str(lesson_id or "").strip()
    projection = await media_control_plane_observability.validate_runtime_projection(
        normalized_lesson_id
    )
    worker_health = await logs_observability.get_worker_health()

    lesson_media_items = list(projection.get("lesson_media") or [])
    asset_ids = sorted(
        {
            _normalize_text((_lesson_media_row_from_item(item).get("asset_id")))
            for item in lesson_media_items
        }
        - {None}
    )
    playback_items = [
        item
        for item in lesson_media_items
        if str((_lesson_media_row_from_item(item).get("kind") or "")).strip().lower()
        in _PLAYBACK_KINDS
    ]

    resolver_resolutions = await asyncio.gather(
        *(
            media_resolver_service.inspect_lesson_media(
                str(_lesson_media_row_from_item(item)["lesson_media_id"])
            )
            for item in playback_items
            if _lesson_media_row_from_item(item).get("lesson_media_id")
        )
    )
    resolver_truth = [
        {
            "lesson_media_id": _normalize_text(_lesson_media_row_from_item(item).get("lesson_media_id")),
            "kind": _normalize_text(_lesson_media_row_from_item(item).get("kind")),
            "resolution": _normalize_resolution(resolution),
        }
        for item, resolution in zip(playback_items, resolver_resolutions, strict=False)
    ]

    failure_payloads = await asyncio.gather(
        *(logs_observability.get_media_failures(asset_id=asset_id) for asset_id in asset_ids)
    )
    asset_failures = [
        {
            "asset_id": asset_id,
            "summary": dict(payload.get("summary") or {}),
            "media_failures": list(payload.get("media_failures") or []),
        }
        for asset_id, payload in zip(asset_ids, failure_payloads, strict=False)
    ]

    subject_violations: list[dict[str, Any]] = [
        _wrap_inconsistency(
            inconsistency,
            source="media_control_plane.validate_runtime_projection",
            course_id=_normalize_text((projection.get("lesson") or {}).get("course_id")),
        )
        for inconsistency in projection.get("detected_inconsistencies") or []
    ]
    for asset_id, payload in zip(asset_ids, failure_payloads, strict=False):
        asset_violation = _asset_failure_violation(
            payload,
            source="logs.get_media_failures",
            lesson_id=normalized_lesson_id,
            asset_id=asset_id,
        )
        if asset_violation is not None:
            subject_violations.append(asset_violation)

    lesson_missing = projection.get("lesson") is None
    sorted_subject_violations = _sort_violations(subject_violations)
    environment_signals = _worker_environment_signals(worker_health)
    evaluated_at = _iso(_now())
    return {
        "generated_at": evaluated_at,
        "verification": {
            "tool": "verify_lesson_media_truth",
            "version": "1",
        },
        "lesson_id": normalized_lesson_id,
        "verdict": _verdict(sorted_subject_violations),
        "confidence": _confidence(
            has_logs=True,
            has_media_truth=True,
            has_resolver_truth=bool(playback_items),
            missing_subject=lesson_missing,
        ),
        "violations": sorted_subject_violations,
        "subject_violations": sorted_subject_violations,
        "environment_signals": environment_signals,
        "summary": {
            "lesson_media_count": int(len(lesson_media_items)),
            "asset_count": int(len(asset_ids)),
            "resolver_checks": int(len(resolver_truth)),
            "error_count": _error_count(sorted_subject_violations),
            "warning_count": _warning_count(sorted_subject_violations),
            "control_plane_state_classification": projection.get("state_classification"),
            "media_transcode_worker_status": environment_signals.get("worker_status"),
        },
        "truth_sources": {
            "media_control_plane": projection,
            "resolver": {"lesson_media": resolver_truth},
            "logs": {
                "worker_health": worker_health,
                "asset_failures": asset_failures,
            },
        },
        "sources_consulted": [
            "media_control_plane.validate_runtime_projection",
            "media_resolver_service.inspect_lesson_media",
            "logs.get_media_failures",
            "logs.get_worker_health",
        ],
    }


async def verify_course_cover_truth(course_id: str) -> dict[str, Any]:
    normalized_course_id = str(course_id or "").strip()
    course_row = await courses_repo.get_course(course_id=normalized_course_id)
    worker_health = await logs_observability.get_worker_health()

    if course_row is None:
        evaluated_at = _iso(_now())
        subject_violations = [
            _violation(
                "course_missing",
                "Course was not found",
                source="courses.get_course",
                severity="error",
                course_id=normalized_course_id,
            ),
        ]
        sorted_subject_violations = _sort_violations(subject_violations)
        environment_signals = _worker_environment_signals(worker_health)
        return {
            "generated_at": evaluated_at,
            "verification": {
                "tool": "verify_course_cover_truth",
                "version": "1",
            },
            "course_id": normalized_course_id,
            "verdict": _verdict(sorted_subject_violations),
            "confidence": "low",
            "violations": sorted_subject_violations,
            "subject_violations": sorted_subject_violations,
            "environment_signals": environment_signals,
            "summary": {
                "error_count": _error_count(sorted_subject_violations),
                "warning_count": _warning_count(sorted_subject_violations),
                "resolved_state": "missing",
                "resolved_source": "missing",
                "media_transcode_worker_status": environment_signals.get("worker_status"),
            },
            "course": None,
            "truth_sources": {
                "resolver": None,
                "media_control_plane": None,
                "logs": {"worker_health": worker_health, "asset_failures": []},
            },
            "sources_consulted": [
                "courses.get_course",
                "courses_service.resolve_course_cover",
                "media_control_plane.get_asset",
                "logs.get_media_failures",
                "logs.get_worker_health",
            ],
        }

    resolved_course = _course_summary_row(course_row, course_id=normalized_course_id)
    cover_media_id = _normalize_text(course_row.get("cover_media_id"))
    cover_url = _normalize_text(course_row.get("cover_url"))
    null_cover_control_state = cover_media_id is None and cover_url is None
    if null_cover_control_state:
        resolver_truth = {
            "course_id": normalized_course_id,
            "media_id": None,
            "resolved_url": None,
            "source": "no_cover_control_state",
            "state": "no_cover_control_state",
        }
        asset_truth = None
        asset_failures_payload = {"summary": {}, "media_failures": [], "asset_id": None}
    else:
        resolver_truth = await courses_service.resolve_course_cover(
            course_id=normalized_course_id,
            cover_media_id=cover_media_id,
            cover_url=cover_url,
        )
        asset_truth = (
            await media_control_plane_observability.get_asset(cover_media_id)
            if cover_media_id
            else None
        )
        asset_failures_payload = (
            await logs_observability.get_media_failures(asset_id=cover_media_id)
            if cover_media_id
            else {"summary": {}, "media_failures": [], "asset_id": None}
        )

    subject_violations: list[dict[str, Any]] = []
    if not null_cover_control_state and (
        resolver_truth.get("state") != "ready"
        or resolver_truth.get("source") != "control_plane"
    ):
        subject_violations.append(
            _violation(
                "course_cover_not_control_plane_ready",
                "Course cover did not resolve to a ready control-plane asset",
                source="courses_service.resolve_course_cover",
                severity="error",
                course_id=normalized_course_id,
                asset_id=cover_media_id,
                details={
                    "state": resolver_truth.get("state"),
                    "source": resolver_truth.get("source"),
                    "resolved_url": resolver_truth.get("resolved_url"),
                },
            )
        )

    if asset_truth is not None:
        subject_violations.extend(
            _wrap_inconsistency(
                inconsistency,
                source="media_control_plane.get_asset",
                course_id=normalized_course_id,
            )
            for inconsistency in asset_truth.get("detected_inconsistencies") or []
        )

    asset_failure_violation = _asset_failure_violation(
        asset_failures_payload,
        source="logs.get_media_failures",
        course_id=normalized_course_id,
        asset_id=cover_media_id,
    )
    if asset_failure_violation is not None:
        subject_violations.append(asset_failure_violation)

    sorted_subject_violations = _sort_violations(subject_violations)
    environment_signals = _worker_environment_signals(worker_health)
    evaluated_at = _iso(_now())
    return {
        "generated_at": evaluated_at,
        "verification": {
            "tool": "verify_course_cover_truth",
            "version": "1",
        },
        "course_id": normalized_course_id,
        "verdict": _verdict(sorted_subject_violations),
        "confidence": _confidence(
            has_logs=True,
            has_media_truth=cover_media_id is not None,
            has_resolver_truth=True,
            missing_subject=False,
        ),
        "violations": sorted_subject_violations,
        "subject_violations": sorted_subject_violations,
        "environment_signals": environment_signals,
        "summary": {
            "error_count": _error_count(sorted_subject_violations),
            "warning_count": _warning_count(sorted_subject_violations),
            "resolved_state": resolver_truth.get("state"),
            "resolved_source": resolver_truth.get("source"),
            "asset_state_classification": (
                asset_truth.get("state_classification")
                if asset_truth is not None
                else (
                    "no_cover_control_state" if null_cover_control_state else "missing"
                )
            ),
            "media_transcode_worker_status": environment_signals.get("worker_status"),
        },
        "course": resolved_course,
        "truth_sources": {
            "resolver": resolver_truth,
            "media_control_plane": asset_truth,
            "logs": {
                "worker_health": worker_health,
                "asset_failures": [
                    {
                        "asset_id": cover_media_id,
                        "summary": dict(asset_failures_payload.get("summary") or {}),
                        "media_failures": list(asset_failures_payload.get("media_failures") or []),
                    }
                ]
                if cover_media_id
                else [],
            },
        },
        "sources_consulted": [
            "courses.get_course",
            "courses_service.resolve_course_cover",
            "media_control_plane.get_asset",
            "logs.get_media_failures",
            "logs.get_worker_health",
        ],
    }


async def get_test_cases() -> dict[str, Any]:
    courses = list(await courses_repo.list_courses(limit=_TEST_CASE_COURSE_SCAN_LIMIT))
    course_cover_cases: list[dict[str, Any]] = []
    lesson_media_cases: list[dict[str, Any]] = []

    for course in courses:
        course_id = _normalize_text(course.get("id"))
        if course_id is None:
            continue

        if (
            len(course_cover_cases) < _TEST_CASE_COURSE_CASE_LIMIT
            and (
                _normalize_text(course.get("cover_media_id")) is not None
                or _normalize_text(course.get("cover_url")) is not None
            )
        ):
            course_cover_cases.append(
                {
                    "course_id": course_id,
                    "slug": _normalize_text(course.get("slug")),
                    "title": _normalize_text(course.get("title")),
                    "why": (
                        "course has cover_media_id"
                        if _normalize_text(course.get("cover_media_id")) is not None
                        else "course has legacy cover_url"
                    ),
                }
            )

        if len(lesson_media_cases) < _TEST_CASE_LESSON_CASE_LIMIT:
            lessons = list(await courses_repo.list_course_lessons(course_id))
            for lesson in lessons[:_TEST_CASE_LESSONS_PER_COURSE]:
                lesson_id = _normalize_text(lesson.get("id"))
                if lesson_id is None:
                    continue
                lesson_media = list(await courses_repo.list_lesson_media(lesson_id, limit=1))
                if not lesson_media:
                    continue
                first_media = dict(lesson_media[0])
                lesson_media_cases.append(
                    {
                        "lesson_id": lesson_id,
                        "course_id": course_id,
                        "course_title": _normalize_text(course.get("title")),
                        "lesson_title": _normalize_text(lesson.get("title")),
                        "why": f"lesson has lesson_media kind={_normalize_text(first_media.get('kind')) or 'unknown'}",
                    }
                )
                if len(lesson_media_cases) >= _TEST_CASE_LESSON_CASE_LIMIT:
                    break

        if (
            len(course_cover_cases) >= _TEST_CASE_COURSE_CASE_LIMIT
            and len(lesson_media_cases) >= _TEST_CASE_LESSON_CASE_LIMIT
        ):
            break

    violations: list[dict[str, Any]] = []
    if not course_cover_cases:
        violations.append(
            _violation(
                "no_course_cover_cases_found",
                "No candidate courses with cover verification inputs were found",
                source="courses.list_courses",
                severity="warning",
            )
        )
    if not lesson_media_cases:
        violations.append(
            _violation(
                "no_lesson_media_cases_found",
                "No candidate lessons with lesson_media rows were found",
                source="courses.list_courses",
                severity="warning",
            )
        )

    recommended_calls = [
        {
            "tool": "verify_lesson_media_truth",
            "arguments": {"lesson_id": case["lesson_id"]},
        }
        for case in lesson_media_cases
    ] + [
        {
            "tool": "verify_course_cover_truth",
            "arguments": {"course_id": case["course_id"]},
        }
        for case in course_cover_cases
    ]

    sorted_violations = _sort_violations(violations)
    evaluated_at = _iso(_now())
    return {
        "generated_at": evaluated_at,
        "verification": {
            "tool": "get_test_cases",
            "version": "1",
        },
        "verdict": "pass" if recommended_calls else "fail",
        "confidence": (
            "high"
            if course_cover_cases and lesson_media_cases
            else "medium"
            if recommended_calls
            else "low"
        ),
        "violations": sorted_violations,
        "scan_limits": {
            "course_scan_limit": _TEST_CASE_COURSE_SCAN_LIMIT,
            "course_case_limit": _TEST_CASE_COURSE_CASE_LIMIT,
            "lesson_case_limit": _TEST_CASE_LESSON_CASE_LIMIT,
            "lessons_per_course": _TEST_CASE_LESSONS_PER_COURSE,
        },
        "course_cover_cases": course_cover_cases,
        "lesson_media_cases": lesson_media_cases,
        "recommended_calls": recommended_calls,
        "summary": {
            "course_cover_case_count": int(len(course_cover_cases)),
            "lesson_media_case_count": int(len(lesson_media_cases)),
            "error_count": _error_count(sorted_violations),
            "warning_count": _warning_count(sorted_violations),
        },
        "sources_consulted": [
            "courses.list_courses",
            "courses.list_course_lessons",
            "courses.list_lesson_media",
        ],
    }


async def verify_phase2_truth_alignment() -> dict[str, Any]:
    test_cases = await get_test_cases()
    worker_health = await logs_observability.get_worker_health()
    recent_errors = await logs_observability.get_recent_errors(limit=_PHASE2_RECENT_ERROR_LIMIT)

    lesson_cases = list(test_cases.get("lesson_media_cases") or [])[:_PHASE2_LESSON_SAMPLE_LIMIT]
    course_cases = list(test_cases.get("course_cover_cases") or [])[:_PHASE2_COURSE_SAMPLE_LIMIT]

    lesson_results = await asyncio.gather(
        *(verify_lesson_media_truth(str(case["lesson_id"])) for case in lesson_cases)
    )
    course_results = await asyncio.gather(
        *(verify_course_cover_truth(str(case["course_id"])) for case in course_cases)
    )

    subject_violations: list[dict[str, Any]] = []
    if not lesson_cases:
        subject_violations.append(
            _violation(
                "no_phase2_lesson_sample",
                "Phase 2 verification could not find a lesson sample to validate",
                source="verification.get_test_cases",
                severity="error",
            )
        )
    if not course_cases:
        subject_violations.append(
            _violation(
                "no_phase2_course_cover_sample",
                "Phase 2 verification could not find a course cover sample to validate",
                source="verification.get_test_cases",
                severity="warning",
            )
        )

    recent_error_count = len(recent_errors.get("recent_errors") or [])
    for payload in lesson_results:
        if payload.get("verdict") == "fail":
            subject_violations.append(
                _violation(
                    "lesson_truth_sample_failed",
                    "A sampled lesson truth verification failed",
                    source="verify_lesson_media_truth",
                    severity="error",
                    lesson_id=_normalize_text(payload.get("lesson_id")),
                    details={
                        "confidence": payload.get("confidence"),
                        "violation_codes": [
                            str(item.get("code"))
                            for item in payload.get("violations") or []
                            if item.get("code")
                        ],
                    },
                )
            )

    for payload in course_results:
        if payload.get("verdict") == "fail":
            subject_violations.append(
                _violation(
                    "course_cover_truth_sample_failed",
                    "A sampled course cover truth verification failed",
                    source="verify_course_cover_truth",
                    severity="error",
                    course_id=_normalize_text(payload.get("course_id")),
                    details={
                        "confidence": payload.get("confidence"),
                        "violation_codes": [
                            str(item.get("code"))
                            for item in payload.get("violations") or []
                            if item.get("code")
                        ],
                    },
                )
            )

    sorted_subject_violations = _sort_violations(subject_violations)
    environment_signals = {
        **_worker_environment_signals(worker_health),
        "recent_error_count": recent_error_count,
        "recent_errors": list(recent_errors.get("recent_errors") or []),
        "recent_error_limit_applied": recent_errors.get("limit_applied"),
    }
    evaluated_at = _iso(_now())
    return {
        "generated_at": evaluated_at,
        "verification": {
            "tool": "verify_phase2_truth_alignment",
            "version": "1",
        },
        "verdict": _verdict(sorted_subject_violations),
        "confidence": (
            "high"
            if lesson_cases and course_cases
            else "medium"
            if lesson_cases or course_cases
            else "low"
        ),
        "violations": sorted_subject_violations,
        "subject_violations": sorted_subject_violations,
        "environment_signals": environment_signals,
        "summary": {
            "lesson_samples_checked": int(len(lesson_results)),
            "course_cover_samples_checked": int(len(course_results)),
            "recent_error_count": recent_error_count,
            "error_count": _error_count(sorted_subject_violations),
            "warning_count": _warning_count(sorted_subject_violations),
            "media_transcode_worker_status": environment_signals.get("worker_status"),
        },
        "truth_sources": {
            "test_cases": test_cases,
            "logs": {
                "worker_health": worker_health,
                "recent_errors": recent_errors,
            },
            "samples": {
                "lesson_media_truth": [
                    _sample_result(
                        payload,
                        tool_name="verify_lesson_media_truth",
                        subject_field="lesson_id",
                    )
                    for payload in lesson_results
                ],
                "course_cover_truth": [
                    _sample_result(
                        payload,
                        tool_name="verify_course_cover_truth",
                        subject_field="course_id",
                    )
                    for payload in course_results
                ],
            },
        },
        "sources_consulted": [
            "verification.get_test_cases",
            "verify_lesson_media_truth",
            "verify_course_cover_truth",
            "logs.get_recent_errors",
            "logs.get_worker_health",
        ],
    }
