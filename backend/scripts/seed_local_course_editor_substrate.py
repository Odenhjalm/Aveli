#!/usr/bin/env python3
"""Seed representative local course/editor data for verification workflows.

This script is intentionally local and idempotent:
- it reuses existing seed courses/lessons/media when present
- it only creates missing representative substrate rows
- it does not depend on shell activation

The seed material comes from the checked-in manifests under ``courses/`` so the
local verification surface stays repo-backed and repeatable.
"""
from __future__ import annotations

import asyncio
import mimetypes
import sys
from pathlib import Path
from typing import Any
from uuid import uuid4

try:
    import yaml  # type: ignore
except Exception as exc:  # pragma: no cover - surfaced in direct script usage
    raise SystemExit("PyYAML is required to seed local course/editor substrate") from exc

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
COURSES_ROOT = REPO_ROOT / "courses"
MANIFEST_ORDER = (
    "foundations-of-soulwisdom.yaml",
    "foundations-of-soulaveli.yaml",
    "tarot-basics.yaml",
)
SEED_TEACHER_EMAIL = "local-verification-teacher@aveli.local"
SEED_TEACHER_NAME = "Aveli Local Verification"

if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.db import get_conn, pool  # noqa: E402
from app.repositories import courses as courses_repo  # noqa: E402
from app.repositories import media_assets as media_assets_repo  # noqa: E402
from app.config import settings  # noqa: E402
from app import models  # noqa: E402
from app.utils import media_paths  # noqa: E402


def _load_manifest(path: Path) -> dict[str, Any]:
    return dict(yaml.safe_load(path.read_text(encoding="utf-8")) or {})


def _course_cover_object_path(course_id: str, filename: str) -> str:
    safe_name = Path(filename).name.strip() or "cover.jpg"
    return media_paths.validate_new_upload_object_path(
        (
            Path("media")
            / "derived"
            / "cover"
            / "courses"
            / course_id
            / f"local-seed-{safe_name}"
        ).as_posix()
    )


def _lesson_image_object_path(lesson_id: str, filename: str) -> str:
    safe_name = Path(filename).name.strip() or "image"
    return media_paths.validate_new_upload_object_path(
        (Path("lessons") / lesson_id / "images" / f"local-seed-{safe_name}").as_posix()
    )


def _lesson_document_object_path(course_id: str, lesson_id: str, filename: str) -> str:
    safe_name = Path(filename).name.strip() or "document"
    return media_paths.validate_new_upload_object_path(
        (
            Path("courses")
            / course_id
            / "lessons"
            / lesson_id
            / "documents"
            / f"local-seed-{safe_name}"
        ).as_posix()
    )


def _lesson_video_object_path(course_id: str, lesson_id: str, filename: str) -> str:
    safe_name = Path(filename).name.strip() or "video"
    return media_paths.validate_new_upload_object_path(
        (
            Path("courses")
            / course_id
            / "lessons"
            / lesson_id
            / "video"
            / f"local-seed-{safe_name}"
        ).as_posix()
    )


def _lesson_audio_source_path(course_id: str, lesson_id: str, filename: str) -> str:
    return media_paths.build_lesson_audio_source_object_path(
        course_id=course_id,
        lesson_id=lesson_id,
        filename=f"local-seed-{Path(filename).name.strip() or 'audio'}",
    )


def _lesson_audio_streaming_path(course_id: str, lesson_id: str, filename: str) -> str:
    stem = Path(filename).stem.strip() or "audio"
    return media_paths.validate_new_upload_object_path(
        (
            Path("media")
            / "derived"
            / "audio"
            / "courses"
            / course_id
            / "lessons"
            / lesson_id
            / f"local-seed-{stem}.mp3"
        ).as_posix()
    )


def _ingest_format(path: Path) -> str:
    suffix = path.suffix.lower().lstrip(".")
    if suffix == "jpeg":
        return "jpg"
    return suffix or "bin"


def _media_type(path: Path) -> str:
    mime_type = (mimetypes.guess_type(path.name)[0] or "").lower()
    if mime_type.startswith("audio/"):
        return "audio"
    if mime_type.startswith("image/"):
        return "image"
    if mime_type.startswith("video/"):
        return "video"
    if mime_type == "application/pdf":
        return "document"
    raise ValueError(f"Unsupported local seed media type for {path.name}")


async def _substrate_status() -> dict[str, bool]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT
              EXISTS(
                SELECT 1
                FROM app.courses c
                WHERE app.is_test_row_visible(c.is_test, c.test_session_id)
                  AND c.is_published = true
              ) AS has_public_courses,
              EXISTS(
                SELECT 1
                FROM app.courses c
                WHERE app.is_test_row_visible(c.is_test, c.test_session_id)
                  AND c.is_published = true
                  AND c.is_free_intro = true
              ) AS has_intro_course,
              EXISTS(
                SELECT 1
                FROM app.courses c
                WHERE app.is_test_row_visible(c.is_test, c.test_session_id)
                  AND c.cover_media_id IS NOT NULL
              ) AS has_cover_case,
              EXISTS(
                SELECT 1
                FROM app.lesson_media lm
                JOIN app.lessons l ON l.id = lm.lesson_id
                JOIN app.courses c ON c.id = l.course_id
                WHERE app.is_test_row_visible(lm.is_test, lm.test_session_id)
                  AND app.is_test_row_visible(l.is_test, l.test_session_id)
                  AND app.is_test_row_visible(c.is_test, c.test_session_id)
              ) AS has_lesson_media_case
            """
        )
        row = await cur.fetchone()
    return {
        "has_public_courses": bool(row["has_public_courses"]),
        "has_intro_course": bool(row["has_intro_course"]),
        "has_cover_case": bool(row["has_cover_case"]),
        "has_lesson_media_case": bool(row["has_lesson_media_case"]),
    }


async def _ensure_seed_teacher() -> str:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT user_id
            FROM app.profiles
            WHERE lower(email) = lower(%s)
            LIMIT 1
            """,
            (SEED_TEACHER_EMAIL,),
        )
        existing = await cur.fetchone()
        if existing:
            user_id = str(existing["user_id"])
        else:
            user_id = str(uuid4())
            await cur.execute(
                """
                INSERT INTO auth.users (id)
                VALUES (%s)
                ON CONFLICT (id) DO NOTHING
                """,
                (user_id,),
            )
            await cur.execute(
                """
                INSERT INTO app.profiles (
                    user_id,
                    email,
                    display_name,
                    created_at,
                    updated_at
                )
                VALUES (
                    %s,
                    %s,
                    %s,
                    now(),
                    now()
                )
                ON CONFLICT (user_id) DO UPDATE
                  SET email = excluded.email,
                      display_name = excluded.display_name,
                      updated_at = now()
                """,
                (user_id, SEED_TEACHER_EMAIL, SEED_TEACHER_NAME),
            )
            await cur.execute(
                """
                INSERT INTO app.auth_subjects (
                    user_id,
                    onboarding_state,
                    role_v2,
                    role,
                    is_admin
                )
                VALUES (%s, 'completed', 'teacher', 'teacher', false)
                ON CONFLICT (user_id) DO UPDATE
                  SET onboarding_state = excluded.onboarding_state,
                      role_v2 = excluded.role_v2,
                      role = excluded.role,
                      is_admin = excluded.is_admin
                """,
                (user_id,),
            )
        await cur.execute(
            """
            UPDATE app.profiles
            SET display_name = %s,
                updated_at = now()
            WHERE user_id = %s
            """,
            (SEED_TEACHER_NAME, user_id),
        )
        await cur.execute(
            """
            UPDATE app.auth_subjects
               SET onboarding_state = 'completed',
                   role = 'teacher',
                   role_v2 = 'teacher',
                   is_admin = false
             WHERE user_id = %s
            """,
            (user_id,),
        )
    return user_id


async def _ensure_course(teacher_id: str, manifest: dict[str, Any]) -> tuple[str, str]:
    slug = str(manifest.get("slug") or "").strip()
    title = str(manifest.get("title") or "").strip()
    if not slug or not title:
        raise ValueError("Course manifest requires slug and title")

    existing = await courses_repo.get_course_by_slug(slug)
    if existing:
        return str(existing["id"]), "reused"

    created = await courses_repo.create_course(
        {
            "title": title,
            "slug": slug,
            "description": manifest.get("description"),
            "is_free_intro": bool(manifest.get("is_free_intro", False)),
            "is_published": True,
            "price_amount_cents": int(manifest.get("price_cents") or 0),
            "currency": "sek",
            "created_by": teacher_id,
        }
    )
    return str(created["id"]), "created"


async def _ensure_lesson(course_id: str, lesson_data: dict[str, Any], position: int) -> tuple[str, str]:
    title = str(lesson_data.get("title") or "").strip() or f"Lesson {position}"
    markdown_rel = lesson_data.get("markdown")
    markdown = None
    if isinstance(markdown_rel, str) and markdown_rel.strip():
        markdown = (COURSES_ROOT / markdown_rel).read_text(encoding="utf-8")

    existing_lessons = list(await courses_repo.list_course_lessons(course_id))
    by_position = next(
        (
            row
            for row in existing_lessons
            if int(row.get("position") or 0) == position
        ),
        None,
    )
    if by_position is not None and str(by_position.get("title") or "").strip() == title:
        return str(by_position["id"]), "reused"

    by_title = [row for row in existing_lessons if str(row.get("title") or "").strip() == title]
    if len(by_title) == 1:
        return str(by_title[0]["id"]), "reused"

    created = await courses_repo.create_lesson(
        course_id,
        title=title,
        content_markdown=markdown,
        position=position,
        is_intro=bool(lesson_data.get("is_intro", False)),
    )
    if not created:
        raise RuntimeError(f"Failed to create lesson {title!r}")
    return str(created["id"]), "created"


async def _ensure_course_cover(
    *,
    teacher_id: str,
    course_id: str,
    cover_rel_path: str | None,
) -> str:
    course_row = await courses_repo.get_course(course_id=course_id)
    if course_row and course_row.get("cover_media_id"):
        return "reused"
    if not cover_rel_path:
        return "skipped"

    cover_path = (COURSES_ROOT / cover_rel_path).resolve()
    if not cover_path.exists():
        return "skipped"

    mime_type = mimetypes.guess_type(cover_path.name)[0] or "image/jpeg"
    asset = await media_assets_repo.create_ready_public_course_cover_asset(
        owner_id=teacher_id,
        course_id=course_id,
        storage_bucket=settings.media_public_bucket,
        storage_path=_course_cover_object_path(course_id, cover_path.name),
        content_type=mime_type,
        filename=cover_path.name,
        size_bytes=cover_path.stat().st_size,
        ingest_format=_ingest_format(cover_path),
    )
    if not asset:
        raise RuntimeError(f"Failed to create course cover asset for course {course_id}")
    await courses_repo.set_course_cover_media_id_if_unset(
        course_id=course_id,
        cover_media_id=str(asset["id"]),
    )
    return "created"


async def _ensure_lesson_media(
    *,
    teacher_id: str,
    course_id: str,
    lesson_id: str,
    media_rel_path: str,
) -> str:
    media_path = (COURSES_ROOT / media_rel_path).resolve()
    if not media_path.exists():
        return "skipped"

    existing_media = list(await courses_repo.list_lesson_media(lesson_id))
    target_name = media_path.name
    if any(str(row.get("original_name") or "").strip() == target_name for row in existing_media):
        return "reused"

    detected_type = _media_type(media_path)
    if detected_type == "audio":
        asset = await media_assets_repo.create_media_asset(
            owner_id=teacher_id,
            course_id=course_id,
            lesson_id=lesson_id,
            media_type="audio",
            purpose="lesson_audio",
            ingest_format=_ingest_format(media_path),
            original_object_path=_lesson_audio_source_path(course_id, lesson_id, target_name),
            original_content_type=mimetypes.guess_type(target_name)[0] or "audio/mpeg",
            original_filename=target_name,
            original_size_bytes=media_path.stat().st_size,
            storage_bucket=settings.media_source_bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        if not asset:
            raise RuntimeError(f"Failed to create audio asset for lesson {lesson_id}")
        await media_assets_repo.mark_media_asset_ready_from_worker(
            media_id=str(asset["id"]),
            streaming_object_path=_lesson_audio_streaming_path(
                course_id, lesson_id, target_name
            ),
            streaming_format="mp3",
            duration_seconds=None,
            codec="mp3",
        )
        created = await models.add_lesson_media_entry_with_position_retry(
            lesson_id=lesson_id,
            kind="audio",
            storage_path=None,
            storage_bucket=settings.media_source_bucket,
            media_id=None,
            media_asset_id=str(asset["id"]),
            duration_seconds=None,
            max_retries=10,
        )
        if not created:
            raise RuntimeError(f"Failed to attach audio media for lesson {lesson_id}")
        return "created"

    if detected_type == "image":
        asset = await media_assets_repo.create_media_asset(
            owner_id=teacher_id,
            course_id=course_id,
            lesson_id=lesson_id,
            media_type="image",
            purpose="lesson_media",
            ingest_format=_ingest_format(media_path),
            original_object_path=_lesson_image_object_path(lesson_id, target_name),
            original_content_type=mimetypes.guess_type(target_name)[0] or "image/jpeg",
            original_filename=target_name,
            original_size_bytes=media_path.stat().st_size,
            storage_bucket=settings.media_public_bucket,
            state="pending_upload",
        )
        if not asset:
            raise RuntimeError(f"Failed to create image asset for lesson {lesson_id}")
        await media_assets_repo.mark_media_asset_ready_passthrough(
            media_id=str(asset["id"]),
            streaming_object_path=_lesson_image_object_path(lesson_id, target_name),
            storage_bucket=settings.media_public_bucket,
            streaming_format=_ingest_format(media_path),
            original_content_type=mimetypes.guess_type(target_name)[0] or "image/jpeg",
            original_size_bytes=media_path.stat().st_size,
        )
        created = await models.add_lesson_media_entry_with_position_retry(
            lesson_id=lesson_id,
            kind="image",
            storage_path=None,
            storage_bucket=settings.media_public_bucket,
            media_id=None,
            media_asset_id=str(asset["id"]),
            duration_seconds=None,
            max_retries=10,
        )
        if not created:
            raise RuntimeError(f"Failed to attach image media for lesson {lesson_id}")
        return "created"

    if detected_type == "video":
        object_path = _lesson_video_object_path(course_id, lesson_id, target_name)
        asset = await media_assets_repo.create_media_asset(
            owner_id=teacher_id,
            course_id=course_id,
            lesson_id=lesson_id,
            media_type="video",
            purpose="lesson_media",
            ingest_format=_ingest_format(media_path),
            original_object_path=object_path,
            original_content_type=mimetypes.guess_type(target_name)[0] or "video/mp4",
            original_filename=target_name,
            original_size_bytes=media_path.stat().st_size,
            storage_bucket=settings.media_source_bucket,
            state="pending_upload",
        )
        if not asset:
            raise RuntimeError(f"Failed to create video asset for lesson {lesson_id}")
        await media_assets_repo.mark_media_asset_ready_passthrough(
            media_id=str(asset["id"]),
            streaming_object_path=object_path,
            storage_bucket=settings.media_source_bucket,
            streaming_format=_ingest_format(media_path),
            original_content_type=mimetypes.guess_type(target_name)[0] or "video/mp4",
            original_size_bytes=media_path.stat().st_size,
        )
        created = await models.add_lesson_media_entry_with_position_retry(
            lesson_id=lesson_id,
            kind="video",
            storage_path=None,
            storage_bucket=settings.media_source_bucket,
            media_id=None,
            media_asset_id=str(asset["id"]),
            duration_seconds=None,
            max_retries=10,
        )
        if not created:
            raise RuntimeError(f"Failed to attach video media for lesson {lesson_id}")
        return "created"

    object_path = _lesson_document_object_path(course_id, lesson_id, target_name)
    asset = await media_assets_repo.create_media_asset(
        owner_id=teacher_id,
        course_id=course_id,
        lesson_id=lesson_id,
        media_type="document",
        purpose="lesson_media",
        ingest_format=_ingest_format(media_path),
        original_object_path=object_path,
        original_content_type="application/pdf",
        original_filename=target_name,
        original_size_bytes=media_path.stat().st_size,
        storage_bucket=settings.media_source_bucket,
        state="pending_upload",
    )
    if not asset:
        raise RuntimeError(f"Failed to create document asset for lesson {lesson_id}")
    await media_assets_repo.mark_media_asset_ready_passthrough(
        media_id=str(asset["id"]),
        streaming_object_path=object_path,
        storage_bucket=settings.media_source_bucket,
        streaming_format="pdf",
        original_content_type="application/pdf",
        original_size_bytes=media_path.stat().st_size,
    )
    created = await models.add_lesson_media_entry_with_position_retry(
        lesson_id=lesson_id,
        kind="pdf",
        storage_path=None,
        storage_bucket=settings.media_source_bucket,
        media_id=None,
        media_asset_id=str(asset["id"]),
        duration_seconds=None,
        max_retries=10,
    )
    if not created:
        raise RuntimeError(f"Failed to attach document media for lesson {lesson_id}")
    return "created"


async def seed_substrate() -> dict[str, Any]:
    before = await _substrate_status()
    teacher_id = await _ensure_seed_teacher()

    summary = {
        "teacher_id": teacher_id,
        "courses_created": 0,
        "courses_reused": 0,
        "lessons_created": 0,
        "lessons_reused": 0,
        "course_covers_created": 0,
        "lesson_media_created": 0,
        "lesson_media_reused": 0,
        "skipped_assets": 0,
    }

    for manifest_name in MANIFEST_ORDER:
        manifest_path = COURSES_ROOT / manifest_name
        manifest = _load_manifest(manifest_path)

        course_id, course_action = await _ensure_course(teacher_id, manifest)
        summary[f"courses_{course_action}"] += 1

        cover_action = await _ensure_course_cover(
            teacher_id=teacher_id,
            course_id=course_id,
            cover_rel_path=manifest.get("cover_path") or manifest.get("coverFile"),
        )
        if cover_action == "created":
            summary["course_covers_created"] += 1
        elif cover_action == "skipped":
            summary["skipped_assets"] += 1

        lessons = list(manifest.get("lessons") or [])
        for position, lesson_data in enumerate(lessons, start=1):
            if not isinstance(lesson_data, dict):
                continue
            lesson_id, lesson_action = await _ensure_lesson(course_id, lesson_data, position)
            summary[f"lessons_{lesson_action}"] += 1
            for media_entry in lesson_data.get("media") or []:
                media_rel = media_entry.get("path") if isinstance(media_entry, dict) else media_entry
                if not isinstance(media_rel, str) or not media_rel.strip():
                    continue
                media_action = await _ensure_lesson_media(
                    teacher_id=teacher_id,
                    course_id=course_id,
                    lesson_id=lesson_id,
                    media_rel_path=media_rel,
                )
                if media_action == "created":
                    summary["lesson_media_created"] += 1
                elif media_action == "reused":
                    summary["lesson_media_reused"] += 1
                else:
                    summary["skipped_assets"] += 1

    after = await _substrate_status()
    return {
        "before": before,
        "after": after,
        "summary": summary,
    }


async def _main() -> int:
    close_pool = False
    if pool.closed:
        await pool.open(wait=True)
        close_pool = True
    try:
        result = await seed_substrate()
    finally:
        if close_pool:
            await pool.close()

    print("Local course/editor substrate seed summary")
    print(f"- teacher_id: {result['summary']['teacher_id']}")
    print(f"- courses created: {result['summary']['courses_created']}")
    print(f"- courses reused: {result['summary']['courses_reused']}")
    print(f"- lessons created: {result['summary']['lessons_created']}")
    print(f"- lessons reused: {result['summary']['lessons_reused']}")
    print(f"- course covers created: {result['summary']['course_covers_created']}")
    print(f"- lesson media created: {result['summary']['lesson_media_created']}")
    print(f"- lesson media reused: {result['summary']['lesson_media_reused']}")
    print(f"- assets skipped: {result['summary']['skipped_assets']}")
    print(f"- substrate before: {result['before']}")
    print(f"- substrate after: {result['after']}")

    after = result["after"]
    if all(after.values()):
        print("PASS: local course/editor verification substrate is aligned.")
        return 0

    print("FAIL: local course/editor verification substrate is still incomplete.")
    return 1


def main() -> int:
    return asyncio.run(_main())


if __name__ == "__main__":
    raise SystemExit(main())
