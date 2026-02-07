"""Media robustness invariants and classification primitives.

This module defines the shared enums used across:
- Runtime resolvers (editor/student playback)
- Telemetry and UI flagging
- Offline audit tooling (media_doctor)

The string values are intentionally stable because they appear in reports.
"""

from __future__ import annotations

from enum import StrEnum


class MediaCategory(StrEnum):
    legacy_lesson_media = "legacy_lesson_media"
    pipeline_media_asset = "pipeline_media_asset"
    public_static = "public_static"
    orphan = "orphan"


class MediaStatus(StrEnum):
    ok = "ok"
    ok_legacy = "ok_legacy"
    needs_migration = "needs_migration"
    missing_bytes = "missing_bytes"
    manual_review = "manual_review"
    unsupported = "unsupported"
    orphaned = "orphaned"


class MediaRecommendedAction(StrEnum):
    keep = "keep"
    auto_migrate = "auto_migrate"
    manual_review = "manual_review"
    reupload_required = "reupload_required"
    safe_to_delete = "safe_to_delete"


SUPPORTED_MEDIA_KINDS: frozenset[str] = frozenset({"image", "video", "audio", "pdf"})


def normalize_media_kind(value: str | None) -> str:
    normalized = (value or "").strip().lower()
    if normalized in SUPPORTED_MEDIA_KINDS:
        return normalized
    return "other"


def is_supported_media_kind(value: str | None) -> bool:
    return normalize_media_kind(value) in SUPPORTED_MEDIA_KINDS


LESSON_MEDIA_ISSUE_TO_STATUS: dict[str, MediaStatus] = {
    "missing_object": MediaStatus.missing_bytes,
    "bucket_mismatch": MediaStatus.needs_migration,
    "key_format_drift": MediaStatus.needs_migration,
    "unsupported": MediaStatus.unsupported,
}

STATUS_TO_RECOMMENDED_ACTION: dict[MediaStatus, MediaRecommendedAction] = {
    MediaStatus.ok: MediaRecommendedAction.keep,
    MediaStatus.ok_legacy: MediaRecommendedAction.keep,
    MediaStatus.needs_migration: MediaRecommendedAction.auto_migrate,
    MediaStatus.missing_bytes: MediaRecommendedAction.reupload_required,
    MediaStatus.manual_review: MediaRecommendedAction.manual_review,
    MediaStatus.unsupported: MediaRecommendedAction.manual_review,
    MediaStatus.orphaned: MediaRecommendedAction.safe_to_delete,
}


def status_from_lesson_media_issue(
    issue: str | None,
    *,
    category: MediaCategory,
) -> MediaStatus:
    normalized = (issue or "").strip().lower()
    mapped = LESSON_MEDIA_ISSUE_TO_STATUS.get(normalized)
    if mapped is not None:
        return mapped
    if category == MediaCategory.legacy_lesson_media:
        return MediaStatus.ok_legacy
    return MediaStatus.ok


def recommended_action_for_status(status: MediaStatus) -> MediaRecommendedAction:
    return STATUS_TO_RECOMMENDED_ACTION.get(status, MediaRecommendedAction.manual_review)
