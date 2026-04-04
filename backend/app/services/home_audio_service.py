from __future__ import annotations

from typing import Any, Sequence

from fastapi import HTTPException, status

from ..repositories import home_audio_runtime as home_audio_runtime_repo
from . import courses_service, lesson_playback_service

_HOME_AUDIO_MEDIA_STATES = frozenset(
    {"pending_upload", "uploaded", "processing", "ready", "failed"}
)


def _normalized_home_audio_state(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized not in _HOME_AUDIO_MEDIA_STATES:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical home audio media state is unavailable",
        )
    return normalized


async def _compose_home_audio_media(
    *,
    media_asset_id: str,
    media_state: str,
    playback_cache: dict[str, dict[str, Any]],
) -> dict[str, Any] | None:
    cached = playback_cache.get(media_asset_id)
    if cached is not None:
        return cached

    resolved_url: str | None = None
    if media_state == "ready":
        try:
            playback = await lesson_playback_service.resolve_media_asset_playback(
                media_asset_id=media_asset_id
            )
        except HTTPException:
            return None
        resolved_url = str(playback.get("resolved_url") or "").strip() or None

    media = {
        "media_id": media_asset_id,
        "state": media_state,
        "resolved_url": resolved_url,
    }
    playback_cache[media_asset_id] = media
    return media


async def list_home_audio_media(user_id: str, *, limit: int = 12) -> Sequence[dict[str, Any]]:
    normalized_user_id = str(user_id or "").strip()
    if not normalized_user_id:
        raise ValueError("user_id is required for home audio")

    capped_limit = max(1, min(int(limit or 12), 50))
    candidate_limit = max(100, min(capped_limit * 4, 250))

    direct_rows = await home_audio_runtime_repo.list_home_audio_direct_upload_sources(
        limit=candidate_limit
    )
    course_link_rows = await home_audio_runtime_repo.list_home_audio_course_link_sources(
        limit=candidate_limit
    )

    candidates = [
        {"source_type": "direct_upload", **dict(row)} for row in direct_rows
    ] + [{"source_type": "course_link", **dict(row)} for row in course_link_rows]
    candidates.sort(
        key=lambda row: (
            row.get("created_at"),
            str(row.get("media_asset_id") or ""),
        ),
        reverse=True,
    )

    lesson_access_cache: dict[str, bool] = {}
    playback_cache: dict[str, dict[str, Any]] = {}
    items: list[dict[str, Any]] = []

    for row in candidates:
        if len(items) >= capped_limit:
            break

        source_type = str(row.get("source_type") or "").strip()
        teacher_id = str(row.get("teacher_id") or "").strip()
        media_asset_id = str(row.get("media_asset_id") or "").strip()
        if not teacher_id or not media_asset_id:
            continue

        if source_type == "direct_upload":
            if teacher_id != normalized_user_id:
                continue
        elif source_type == "course_link":
            lesson_id = str(row.get("lesson_id") or "").strip()
            if not lesson_id:
                continue
            can_access = lesson_access_cache.get(lesson_id)
            if can_access is None:
                access = await courses_service.read_canonical_lesson_access(
                    normalized_user_id, lesson_id
                )
                can_access = bool(access["can_access"])
                lesson_access_cache[lesson_id] = can_access
            if not can_access:
                continue
        else:
            continue

        media_state = _normalized_home_audio_state(row.get("media_state"))
        media = await _compose_home_audio_media(
            media_asset_id=media_asset_id,
            media_state=media_state,
            playback_cache=playback_cache,
        )
        if media is None:
            continue
        items.append(
            {
                "source_type": source_type,
                "title": str(row.get("title") or "").strip(),
                "lesson_title": (
                    None
                    if source_type == "direct_upload"
                    else str(row.get("lesson_title") or "").strip() or None
                ),
                "course_id": row.get("course_id"),
                "course_title": (
                    str(row.get("course_title") or "").strip() or None
                    if source_type == "course_link"
                    else None
                ),
                "course_slug": (
                    str(row.get("course_slug") or "").strip() or None
                    if source_type == "course_link"
                    else None
                ),
                "teacher_id": row.get("teacher_id"),
                "teacher_name": str(row.get("teacher_name") or "").strip() or None,
                "created_at": row.get("created_at"),
                "media": media,
            }
        )

    return items
