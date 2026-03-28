#!/usr/bin/env python3
"""Materialize representative local media/runtime/homeplayer substrate.

This script is intentionally local and idempotent:
- it reuses the existing course/editor substrate seed
- it materializes the missing local storage-object bytes/catalog rows
- it creates one deterministic asset-backed home-player upload sample
- it does not depend on shell activation
"""
from __future__ import annotations

import asyncio
import hashlib
import mimetypes
import os
import sys
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from psycopg.types.json import Jsonb

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
BACKEND_ROOT = ROOT / "backend"
DEFAULT_ENV_PATH = BACKEND_ROOT / ".env"
DEFAULT_ENV_LOCAL_PATH = BACKEND_ROOT / ".env.local"

if DEFAULT_ENV_PATH.exists():
    load_dotenv(DEFAULT_ENV_PATH, override=False)
if DEFAULT_ENV_LOCAL_PATH.exists():
    load_dotenv(DEFAULT_ENV_LOCAL_PATH, override=True)

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import seed_local_course_editor_substrate as course_seed  # noqa: E402

UPLOADS_ROOT = BACKEND_ROOT / "assets" / "uploads"

if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.config import settings  # noqa: E402
from app.db import get_conn, pool  # noqa: E402
from app.repositories import courses as courses_repo  # noqa: E402
from app.repositories import home_player_library as home_player_repo  # noqa: E402
from app.repositories import media_assets as media_assets_repo  # noqa: E402
from app.repositories import runtime_media as runtime_media_repo  # noqa: E402
from app.services import courses_service  # noqa: E402
from app.utils import media_paths  # noqa: E402

HOME_UPLOAD_TITLE = "Local Seed Home Audio"


def _normalize_content_type(path: Path) -> str:
    return mimetypes.guess_type(path.name)[0] or "application/octet-stream"


def _uploads_path(*, storage_bucket: str, storage_path: str) -> Path:
    normalized = media_paths.normalize_storage_path(storage_bucket, storage_path)
    return UPLOADS_ROOT / storage_bucket / normalized


async def _upsert_storage_object(
    *,
    storage_bucket: str,
    storage_path: str,
    content_type: str,
    size_bytes: int,
    payload: bytes,
) -> None:
    normalized = media_paths.normalize_storage_path(storage_bucket, storage_path)
    metadata = {
        "size": int(size_bytes),
        "mimetype": content_type,
        "eTag": hashlib.md5(payload).hexdigest(),
    }
    async with get_conn() as cur:
        await cur.execute(
            """
            INSERT INTO storage.objects (
              bucket_id,
              name,
              metadata,
              created_at,
              updated_at
            )
            VALUES (%s, %s, %s, now(), now())
            ON CONFLICT (bucket_id, name) DO UPDATE
              SET metadata = excluded.metadata,
                  updated_at = now()
            """,
            (
                storage_bucket,
                normalized,
                Jsonb(metadata),
            ),
        )


async def _materialize_storage_object(
    *,
    source_file: Path,
    storage_bucket: str,
    storage_path: str,
    content_type: str,
) -> int:
    normalized = media_paths.normalize_storage_path(storage_bucket, storage_path)
    payload = source_file.read_bytes()
    destination = _uploads_path(
        storage_bucket=storage_bucket,
        storage_path=normalized,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    await _upsert_storage_object(
        storage_bucket=storage_bucket,
        storage_path=normalized,
        content_type=content_type,
        size_bytes=len(payload),
        payload=payload,
    )
    return len(payload)


def _home_player_streaming_path(teacher_id: str, filename: str) -> str:
    safe_name = Path(filename).stem.strip() or "local-seed-home-audio"
    return media_paths.validate_new_upload_object_path(
        (
            Path("media")
            / "derived"
            / "audio"
            / "home-player"
            / teacher_id
            / f"{safe_name}.mp3"
        ).as_posix()
    )


def _first_seed_audio_path() -> Path:
    for manifest_name in course_seed.MANIFEST_ORDER:
        manifest = course_seed._load_manifest(course_seed.COURSES_ROOT / manifest_name)
        for lesson in manifest.get("lessons") or []:
            if not isinstance(lesson, dict):
                continue
            for media_entry in lesson.get("media") or []:
                media_rel = media_entry.get("path") if isinstance(media_entry, dict) else media_entry
                if not isinstance(media_rel, str) or not media_rel.strip():
                    continue
                media_path = (course_seed.COURSES_ROOT / media_rel).resolve()
                if media_path.suffix.lower() == ".mp3" and media_path.exists():
                    return media_path
    raise RuntimeError("No representative seed audio file was found in courses/*.yaml")


async def _find_home_audio_asset_id(
    *,
    teacher_id: str,
    original_object_path: str,
) -> str | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id
            FROM app.media_assets
            WHERE owner_id = %s
              AND course_id IS NULL
              AND lesson_id IS NULL
              AND purpose = 'home_player_audio'
              AND original_object_path = %s
            ORDER BY created_at ASC
            LIMIT 1
            """,
            (teacher_id, original_object_path),
        )
        row = await cur.fetchone()
    return str(row["id"]) if row else None


async def _find_home_upload(
    *,
    teacher_id: str,
    media_asset_id: str,
) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, active
            FROM app.home_player_uploads
            WHERE teacher_id = %s
              AND media_asset_id = %s
            ORDER BY created_at ASC
            LIMIT 1
            """,
            (teacher_id, media_asset_id),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def _lookup_runtime_media_id_for_home_upload(upload_id: str) -> str | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id
            FROM app.runtime_media
            WHERE home_player_upload_id = %s
            ORDER BY updated_at DESC, created_at DESC
            LIMIT 1
            """,
            (upload_id,),
        )
        row = await cur.fetchone()
    return str(row["id"]) if row else None


async def _lookup_seed_teacher_id() -> str:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT user_id
            FROM app.profiles
            WHERE lower(email) = lower(%s)
            LIMIT 1
            """,
            (course_seed.SEED_TEACHER_EMAIL,),
        )
        row = await cur.fetchone()
    if not row:
        raise RuntimeError("Seed teacher is missing after course/editor substrate seed")
    return str(row["user_id"])


async def _materialize_course_cover(
    *,
    course_id: str,
    cover_rel_path: str | None,
) -> int:
    if not cover_rel_path:
        return 0
    cover_path = (course_seed.COURSES_ROOT / cover_rel_path).resolve()
    if not cover_path.exists():
        return 0
    storage_path = course_seed._course_cover_object_path(course_id, cover_path.name)
    return await _materialize_storage_object(
        source_file=cover_path,
        storage_bucket=settings.media_public_bucket,
        storage_path=storage_path,
        content_type=_normalize_content_type(cover_path),
    )


async def _materialize_lesson_media(
    *,
    course_id: str,
    lesson_id: str,
    media_rel_path: str,
) -> int:
    media_path = (course_seed.COURSES_ROOT / media_rel_path).resolve()
    if not media_path.exists():
        return 0
    content_type = _normalize_content_type(media_path)
    detected_type = course_seed._media_type(media_path)

    if detected_type == "audio":
        source_path = course_seed._lesson_audio_source_path(course_id, lesson_id, media_path.name)
        streaming_path = course_seed._lesson_audio_streaming_path(
            course_id,
            lesson_id,
            media_path.name,
        )
        total = await _materialize_storage_object(
            source_file=media_path,
            storage_bucket=settings.media_source_bucket,
            storage_path=source_path,
            content_type=content_type,
        )
        total += await _materialize_storage_object(
            source_file=media_path,
            storage_bucket=settings.media_source_bucket,
            storage_path=streaming_path,
            content_type="audio/mpeg",
        )
        return total

    if detected_type == "image":
        storage_bucket = settings.media_public_bucket
        storage_path = course_seed._lesson_image_object_path(lesson_id, media_path.name)
    elif detected_type == "video":
        storage_bucket = settings.media_source_bucket
        storage_path = course_seed._lesson_video_object_path(
            course_id,
            lesson_id,
            media_path.name,
        )
    else:
        storage_bucket = settings.media_source_bucket
        storage_path = course_seed._lesson_document_object_path(
            course_id,
            lesson_id,
            media_path.name,
        )

    return await _materialize_storage_object(
        source_file=media_path,
        storage_bucket=storage_bucket,
        storage_path=storage_path,
        content_type=content_type,
    )


async def _ensure_home_player_upload(teacher_id: str) -> dict[str, Any]:
    audio_path = _first_seed_audio_path()
    source_path = media_paths.build_home_player_audio_source_object_path(
        teacher_id,
        audio_path.name,
    )
    streaming_path = _home_player_streaming_path(teacher_id, audio_path.name)
    content_type = _normalize_content_type(audio_path)

    media_asset_id = await _find_home_audio_asset_id(
        teacher_id=teacher_id,
        original_object_path=source_path,
    )
    asset_action = "reused"
    if media_asset_id is None:
        asset = await media_assets_repo.create_media_asset(
            owner_id=teacher_id,
            course_id=None,
            lesson_id=None,
            media_type="audio",
            purpose="home_player_audio",
            ingest_format=course_seed._ingest_format(audio_path),
            original_object_path=source_path,
            original_content_type=content_type,
            original_filename=audio_path.name,
            original_size_bytes=audio_path.stat().st_size,
            storage_bucket=settings.media_source_bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        if not asset:
            raise RuntimeError("Failed to create local seed home-player audio asset")
        media_asset_id = str(asset["id"])
        asset_action = "created"

    await media_assets_repo.mark_media_asset_ready_from_worker(
        media_id=media_asset_id,
        streaming_object_path=streaming_path,
        streaming_format="mp3",
        duration_seconds=None,
        codec="mp3",
        streaming_storage_bucket=settings.media_source_bucket,
    )

    bytes_materialized = await _materialize_storage_object(
        source_file=audio_path,
        storage_bucket=settings.media_source_bucket,
        storage_path=source_path,
        content_type=content_type,
    )
    bytes_materialized += await _materialize_storage_object(
        source_file=audio_path,
        storage_bucket=settings.media_source_bucket,
        storage_path=streaming_path,
        content_type="audio/mpeg",
    )

    upload = await _find_home_upload(
        teacher_id=teacher_id,
        media_asset_id=media_asset_id,
    )
    upload_action = "reused"
    if upload is None:
        created = await home_player_repo.create_home_player_upload(
            teacher_id=teacher_id,
            media_id=None,
            media_asset_id=media_asset_id,
            title=HOME_UPLOAD_TITLE,
            kind="audio",
            active=True,
        )
        if created is None:
            raise RuntimeError("Failed to create local seed home-player upload")
        upload_id = str(created["id"])
        upload_action = "created"
    else:
        upload_id = str(upload["id"])
        if upload.get("active") is not True:
            updated = await home_player_repo.update_home_player_upload(
                upload_id=upload_id,
                teacher_id=teacher_id,
                fields={"active": True},
            )
            if updated is None:
                raise RuntimeError("Failed to reactivate local seed home-player upload")
            upload_action = "reactivated"
        await runtime_media_repo.sync_home_player_upload_runtime_media(upload_id=upload_id)

    runtime_media_id = await _lookup_runtime_media_id_for_home_upload(upload_id)
    if runtime_media_id is None:
        raise RuntimeError("Seeded home-player upload is missing runtime_media projection")

    return {
        "media_asset_id": media_asset_id,
        "upload_id": upload_id,
        "runtime_media_id": runtime_media_id,
        "asset_action": asset_action,
        "upload_action": upload_action,
        "bytes_materialized": bytes_materialized,
    }


async def _materialize_media_runtime_homeplayer_substrate() -> dict[str, Any]:
    baseline = await course_seed.seed_substrate()
    teacher_id = baseline["summary"]["teacher_id"]

    storage_objects_materialized = 0
    for manifest_name in course_seed.MANIFEST_ORDER:
        manifest = course_seed._load_manifest(course_seed.COURSES_ROOT / manifest_name)
        course_id, _ = await course_seed._ensure_course(teacher_id, manifest)
        storage_objects_materialized += int(
            await _materialize_course_cover(
                course_id=course_id,
                cover_rel_path=manifest.get("cover_path") or manifest.get("coverFile"),
            )
            > 0
        )

        for position, lesson_data in enumerate(manifest.get("lessons") or [], start=1):
            if not isinstance(lesson_data, dict):
                continue
            lesson_id, _ = await course_seed._ensure_lesson(course_id, lesson_data, position)
            for media_entry in lesson_data.get("media") or []:
                media_rel = media_entry.get("path") if isinstance(media_entry, dict) else media_entry
                if not isinstance(media_rel, str) or not media_rel.strip():
                    continue
                storage_objects_materialized += int(
                    await _materialize_lesson_media(
                        course_id=course_id,
                        lesson_id=lesson_id,
                        media_rel_path=media_rel,
                    )
                    > 0
                )

    seed_teacher_id = await _lookup_seed_teacher_id()
    home_upload = await _ensure_home_player_upload(seed_teacher_id)
    home_items = await courses_service.list_home_audio_media(seed_teacher_id, limit=20)

    return {
        "baseline": baseline,
        "storage_objects_materialized": storage_objects_materialized,
        "seed_teacher_id": seed_teacher_id,
        "home_upload": home_upload,
        "home_feed_item_count": len(home_items),
        "home_feed_runtime_ids": [
            str(item.get("runtime_media_id") or "")
            for item in home_items
            if item.get("runtime_media_id")
        ],
    }


async def _main() -> int:
    close_pool = False
    if pool.closed:
        await pool.open(wait=True)
        close_pool = True

    try:
        result = await _materialize_media_runtime_homeplayer_substrate()
    finally:
        if close_pool:
            await pool.close()

    print("Local media/runtime/homeplayer substrate seed summary")
    print(f"- seed teacher_id: {result['seed_teacher_id']}")
    print(
        "- storage objects materialized: "
        f"{result['storage_objects_materialized']}"
    )
    print(
        "- home upload asset action: "
        f"{result['home_upload']['asset_action']}"
    )
    print(
        "- home upload row action: "
        f"{result['home_upload']['upload_action']}"
    )
    print(
        "- home upload runtime_media_id: "
        f"{result['home_upload']['runtime_media_id']}"
    )
    print(f"- home feed item count: {result['home_feed_item_count']}")
    print(
        "- baseline before: "
        f"{result['baseline']['before']}"
    )
    print(
        "- baseline after: "
        f"{result['baseline']['after']}"
    )

    if result["home_feed_item_count"] < 1:
        print("FAIL: home-player substrate is still empty.")
        return 1

    print("PASS: local media/runtime/homeplayer substrate is aligned.")
    return 0


def main() -> int:
    return asyncio.run(_main())


if __name__ == "__main__":
    raise SystemExit(main())
