#!/usr/bin/env python3
"""Read-only preflight for importing Baseline V2 Projection V2 exports."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import urlsplit

try:
    import psycopg
    from psycopg.rows import dict_row
except Exception as exc:  # pragma: no cover - surfaced in direct script usage
    raise SystemExit("psycopg is required for Projection V2 import preflight") from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local"
DEFAULT_EXPORT_ROOT = REPO_ROOT / "canonical_projection_export_v2"
PROJECTION_SCHEMA_V2 = "aveli.baseline_v2.course_projection.v2"
READ_CHUNK_SIZE = 1024 * 1024

SAFE_INGEST_FORMATS = {
    "aac",
    "doc",
    "docx",
    "flac",
    "gif",
    "jpeg",
    "jpg",
    "m4a",
    "mkv",
    "mov",
    "mp3",
    "mp4",
    "ogg",
    "pdf",
    "png",
    "rtf",
    "txt",
    "wav",
    "webm",
    "webp",
}


class ProjectionV2PreflightError(RuntimeError):
    pass


@dataclass(frozen=True)
class MediaIdentity:
    algorithm: str
    content_hash: str
    file_size: int


@dataclass
class MediaIndexEntry:
    media_asset_id: str
    identity: MediaIdentity
    ingest_format: str
    media_type: str
    purpose: str
    file_path: Path
    manifest_paths: set[str] = field(default_factory=set)
    placements: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class PreflightResult:
    courses: int
    lessons: int
    media_assets: int
    placements: int
    validation_status: str
    target_db_status: str
    target_db_counts: dict[str, int]
    global_media_files: int
    orphan_media_files: int
    duplicate_identity_conflicts: int
    id_conflicts: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate Projection V2 import preflight and build the global media index."
    )
    parser.add_argument(
        "--export-root",
        default=str(DEFAULT_EXPORT_ROOT),
        help="Projection V2 root containing courses/ and media/.",
    )
    parser.add_argument(
        "--database-url",
        default=os.environ.get("AVELI_LOCAL_DATABASE_URL")
        or os.environ.get("DATABASE_URL")
        or DEFAULT_DATABASE_URL,
        help="Local target PostgreSQL URL. Defaults to aveli_local on 127.0.0.1.",
    )
    parser.add_argument(
        "--allow-non-empty-target",
        action="store_true",
        help="Allow a non-empty target DB for read-only preflight. No writes are performed.",
    )
    return parser.parse_args()


def normalize_path(path: Path) -> str:
    return os.path.normcase(str(path.resolve(strict=False)))


def require_local_database(database_url: str) -> str:
    parsed = urlsplit(database_url)
    if parsed.scheme not in {"postgresql", "postgres"}:
        raise ProjectionV2PreflightError(f"database URL must be PostgreSQL, got {parsed.scheme!r}")
    if parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise ProjectionV2PreflightError(f"refusing non-local target DB host {parsed.hostname!r}")
    database = parsed.path.lstrip("/")
    if database != "aveli_local":
        raise ProjectionV2PreflightError(f"refusing unexpected target database {database!r}")
    return database


def resolve_export_root(path_value: str) -> Path:
    export_root = Path(path_value).expanduser().resolve()
    if not export_root.is_dir():
        raise ProjectionV2PreflightError(f"export root does not exist: {export_root}")
    courses_root = export_root / "courses"
    media_root = export_root / "media"
    if not courses_root.is_dir():
        raise ProjectionV2PreflightError(f"courses directory does not exist: {courses_root}")
    if not media_root.is_dir():
        raise ProjectionV2PreflightError(f"media directory does not exist: {media_root}")
    top_level = {path.name for path in export_root.iterdir()}
    if top_level != {"courses", "media"}:
        raise ProjectionV2PreflightError(
            f"Projection V2 root must contain only courses/ and media/, found {sorted(top_level)}"
        )
    return export_root


def media_extension(ingest_format: str) -> str:
    normalized = str(ingest_format or "").strip().lower().lstrip(".")
    if normalized not in SAFE_INGEST_FORMATS:
        raise ProjectionV2PreflightError(f"unsupported ingest_format: {ingest_format!r}")
    return f".{normalized}"


def required_text(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or not value:
        raise ProjectionV2PreflightError(f"{field_name} must be a non-empty string")
    if "/" in value or "\\" in value or ".." in value:
        raise ProjectionV2PreflightError(f"{field_name} contains unsafe path characters: {value!r}")
    return value


def required_int(value: Any, field_name: str, *, min_value: int) -> int:
    if not isinstance(value, int):
        raise ProjectionV2PreflightError(f"{field_name} must be an integer")
    if value < min_value:
        raise ProjectionV2PreflightError(f"{field_name} must be >= {min_value}")
    return value


def required_sha256(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or len(value) != 64:
        raise ProjectionV2PreflightError(f"{field_name} must be a 64-character SHA256 hex string")
    if any(char not in "0123456789abcdef" for char in value):
        raise ProjectionV2PreflightError(f"{field_name} must use lowercase SHA256 hex")
    return value


def read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ProjectionV2PreflightError(f"failed to parse JSON: {path}") from exc
    if not isinstance(payload, dict):
        raise ProjectionV2PreflightError(f"course manifest must be a JSON object: {path}")
    return payload


def sha256_file(path: Path) -> tuple[int, str]:
    hasher = hashlib.sha256()
    byte_count = 0
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(READ_CHUNK_SIZE)
            if not chunk:
                break
            byte_count += len(chunk)
            hasher.update(chunk)
    return byte_count, hasher.hexdigest()


def resolve_manifest_media_path(course_dir: Path, media_root: Path, media: dict[str, Any]) -> Path:
    raw_file = media.get("file")
    if not isinstance(raw_file, str) or not raw_file:
        raise ProjectionV2PreflightError("media.file must be a non-empty relative path")
    posix = PurePosixPath(raw_file.replace("\\", "/"))
    if posix.is_absolute() or not posix.parts:
        raise ProjectionV2PreflightError(f"media.file must be relative: {raw_file!r}")
    if any(part in {"", "."} for part in posix.parts):
        raise ProjectionV2PreflightError(f"media.file contains empty/current path part: {raw_file!r}")

    resolved = (course_dir / Path(*posix.parts)).resolve(strict=False)
    common = os.path.commonpath([normalize_path(media_root), normalize_path(resolved)])
    if common != normalize_path(media_root):
        raise ProjectionV2PreflightError(f"media.file resolves outside global media root: {raw_file!r}")

    media_asset_id = required_text(media.get("media_asset_id"), "media_asset_id")
    ingest_format = required_text(media.get("ingest_format"), "ingest_format")
    expected_name = f"{media_asset_id}{media_extension(ingest_format)}"
    if resolved.name != expected_name:
        raise ProjectionV2PreflightError(
            f"media.file name must match <media_asset_id>.<ext>: {raw_file!r} != {expected_name!r}"
        )
    return resolved


def validate_course_folder(course_dir: Path, manifest: dict[str, Any]) -> None:
    course = manifest.get("course")
    if not isinstance(course, dict):
        raise ProjectionV2PreflightError(f"course must be an object in {course_dir / 'course.json'}")
    course_id = required_text(course.get("id"), "course.id")
    group_position = required_int(course.get("group_position"), "course.group_position", min_value=0)
    expected_folder = f"course_{group_position:04d}_{course_id}"
    if course_dir.name != expected_folder:
        raise ProjectionV2PreflightError(
            f"course folder does not match deterministic rule: {course_dir.name!r} != {expected_folder!r}"
        )


def validate_lesson_folder(course_dir: Path, lesson: dict[str, Any]) -> Path:
    lesson_id = required_text(lesson.get("id"), "lesson.id")
    position = required_int(lesson.get("position"), "lesson.position", min_value=1)
    folder = lesson.get("folder")
    if not isinstance(folder, str) or not folder:
        raise ProjectionV2PreflightError("lesson.folder must be a non-empty string")
    expected_folder = f"lesson_{position:04d}_{lesson_id}"
    if folder != expected_folder:
        raise ProjectionV2PreflightError(
            f"lesson.folder does not match deterministic rule: {folder!r} != {expected_folder!r}"
        )
    lesson_dir = course_dir / "lessons" / folder
    if not lesson_dir.is_dir():
        raise ProjectionV2PreflightError(f"lesson directory is missing: {lesson_dir}")
    if (lesson_dir / "media").exists():
        raise ProjectionV2PreflightError(f"lesson-local media directory is forbidden: {lesson_dir / 'media'}")
    content_file = lesson.get("content_file")
    if content_file != f"lessons/{folder}/content.md":
        raise ProjectionV2PreflightError(
            f"lesson.content_file must be deterministic: {content_file!r}"
        )
    content_path = lesson_dir / "content.md"
    if not content_path.is_file():
        raise ProjectionV2PreflightError(f"content.md is missing: {content_path}")
    return lesson_dir


def add_media_index_entry(
    media_index: dict[str, MediaIndexEntry],
    identity_index: dict[MediaIdentity, str],
    media_asset_id: str,
    identity: MediaIdentity,
    ingest_format: str,
    media_type: str,
    purpose: str,
    file_path: Path,
    manifest_path: Path,
    placement: dict[str, Any],
) -> None:
    existing_id_for_identity = identity_index.get(identity)
    if existing_id_for_identity is not None and existing_id_for_identity != media_asset_id:
        raise ProjectionV2PreflightError(
            "same identity is assigned to multiple media_asset_id values: "
            f"{existing_id_for_identity!r} and {media_asset_id!r}"
        )
    identity_index[identity] = media_asset_id

    existing = media_index.get(media_asset_id)
    if existing is None:
        media_index[media_asset_id] = MediaIndexEntry(
            media_asset_id=media_asset_id,
            identity=identity,
            ingest_format=ingest_format,
            media_type=media_type,
            purpose=purpose,
            file_path=file_path,
            manifest_paths={str(manifest_path)},
            placements=[placement],
        )
        return

    if existing.identity != identity:
        raise ProjectionV2PreflightError(f"media_asset_id has conflicting identity: {media_asset_id}")
    if existing.ingest_format != ingest_format:
        raise ProjectionV2PreflightError(f"media_asset_id has conflicting ingest_format: {media_asset_id}")
    if existing.media_type != media_type:
        raise ProjectionV2PreflightError(f"media_asset_id has conflicting media_type: {media_asset_id}")
    if existing.purpose != purpose:
        raise ProjectionV2PreflightError(f"media_asset_id has conflicting purpose: {media_asset_id}")
    if normalize_path(existing.file_path) != normalize_path(file_path):
        raise ProjectionV2PreflightError(f"media_asset_id resolves to multiple files: {media_asset_id}")

    existing.manifest_paths.add(str(manifest_path))
    existing.placements.append(placement)


def build_global_media_index(export_root: Path) -> tuple[int, int, dict[str, MediaIndexEntry]]:
    courses_root = export_root / "courses"
    media_root = export_root / "media"
    course_manifests = sorted(courses_root.glob("*/course.json"), key=lambda path: path.as_posix())
    if not course_manifests:
        raise ProjectionV2PreflightError("no course.json files found")

    course_dirs = {manifest.parent.resolve() for manifest in course_manifests}
    unexpected_course_entries = [
        path
        for path in courses_root.iterdir()
        if path.is_dir() and path.resolve() not in course_dirs
    ]
    if unexpected_course_entries:
        raise ProjectionV2PreflightError(f"course directories without course.json: {unexpected_course_entries[:10]}")

    media_index: dict[str, MediaIndexEntry] = {}
    identity_index: dict[MediaIdentity, str] = {}
    lessons_count = 0
    placements_count = 0
    seen_course_ids: set[str] = set()
    seen_lesson_ids: set[str] = set()
    seen_lesson_media_ids: set[str] = set()

    for manifest_path in course_manifests:
        manifest = read_json(manifest_path)
        if manifest.get("schema") != PROJECTION_SCHEMA_V2:
            raise ProjectionV2PreflightError(
                f"course manifest schema must be {PROJECTION_SCHEMA_V2}: {manifest_path}"
            )
        projection = manifest.get("projection")
        if not isinstance(projection, dict) or projection.get("media_store") != "global":
            raise ProjectionV2PreflightError(f"Projection V2 manifest must declare global media store: {manifest_path}")
        if projection.get("media_file_rule") != "<media_asset_id>.<ext>":
            raise ProjectionV2PreflightError(f"Projection V2 media_file_rule mismatch: {manifest_path}")

        course_dir = manifest_path.parent
        validate_course_folder(course_dir, manifest)
        course_id = required_text((manifest["course"] or {}).get("id"), "course.id")
        if course_id in seen_course_ids:
            raise ProjectionV2PreflightError(f"duplicate course.id in manifests: {course_id}")
        seen_course_ids.add(course_id)

        lessons = manifest.get("lessons")
        if not isinstance(lessons, list):
            raise ProjectionV2PreflightError(f"lessons must be a list: {manifest_path}")
        previous_lesson_position = 0
        for lesson in lessons:
            if not isinstance(lesson, dict):
                raise ProjectionV2PreflightError(f"lesson entry must be an object: {manifest_path}")
            lesson_position = required_int(lesson.get("position"), "lesson.position", min_value=1)
            if lesson_position < previous_lesson_position:
                raise ProjectionV2PreflightError(f"lessons are not ordered by position: {manifest_path}")
            previous_lesson_position = lesson_position
            lesson_dir = validate_lesson_folder(course_dir, lesson)
            lesson_id = required_text(lesson.get("id"), "lesson.id")
            if lesson_id in seen_lesson_ids:
                raise ProjectionV2PreflightError(f"duplicate lesson.id in manifests: {lesson_id}")
            seen_lesson_ids.add(lesson_id)
            lessons_count += 1

            media_entries = lesson.get("media")
            if not isinstance(media_entries, list):
                raise ProjectionV2PreflightError(f"lesson.media must be a list: {manifest_path}")
            previous_media_position = 0
            for media in media_entries:
                if not isinstance(media, dict):
                    raise ProjectionV2PreflightError(f"media entry must be an object: {manifest_path}")
                media_position = required_int(media.get("position"), "media.position", min_value=1)
                if media_position < previous_media_position:
                    raise ProjectionV2PreflightError(f"lesson media entries are not ordered by position: {manifest_path}")
                previous_media_position = media_position
                lesson_media_id = required_text(media.get("lesson_media_id"), "lesson_media_id")
                if lesson_media_id in seen_lesson_media_ids:
                    raise ProjectionV2PreflightError(f"duplicate lesson_media_id in manifests: {lesson_media_id}")
                seen_lesson_media_ids.add(lesson_media_id)

                media_asset_id = required_text(media.get("media_asset_id"), "media_asset_id")
                ingest_format = required_text(media.get("ingest_format"), "ingest_format")
                media_type = required_text(media.get("media_type"), "media_type")
                purpose = required_text(media.get("purpose"), "purpose")
                if media.get("content_hash_algorithm") != "sha256":
                    raise ProjectionV2PreflightError(f"unsupported content_hash_algorithm for {media_asset_id}")
                identity = MediaIdentity(
                    algorithm="sha256",
                    content_hash=required_sha256(media.get("content_hash"), "content_hash"),
                    file_size=required_int(media.get("file_size"), "file_size", min_value=0),
                )
                file_path = resolve_manifest_media_path(course_dir, media_root, media)
                placement = {
                    "course_id": course_id,
                    "lesson_id": lesson_id,
                    "lesson_media_id": lesson_media_id,
                    "position": media_position,
                    "manifest": str(manifest_path),
                    "lesson_dir": str(lesson_dir),
                }
                add_media_index_entry(
                    media_index,
                    identity_index,
                    media_asset_id,
                    identity,
                    ingest_format,
                    media_type,
                    purpose,
                    file_path,
                    manifest_path,
                    placement,
                )
                placements_count += 1

    return len(course_manifests), lessons_count, media_index


def verify_global_media_files(export_root: Path, media_index: dict[str, MediaIndexEntry]) -> int:
    media_root = export_root / "media"
    expected_files = {normalize_path(entry.file_path) for entry in media_index.values()}
    actual_files = {normalize_path(path) for path in media_root.iterdir() if path.is_file()}
    actual_dirs = [path for path in media_root.iterdir() if path.is_dir()]
    if actual_dirs:
        raise ProjectionV2PreflightError(f"global media store must not contain directories: {actual_dirs[:10]}")

    missing = expected_files - actual_files
    if missing:
        raise ProjectionV2PreflightError(f"global media files missing: {sorted(missing)[:10]}")
    orphan = actual_files - expected_files
    if orphan:
        raise ProjectionV2PreflightError(f"orphan global media files found: {sorted(orphan)[:10]}")

    for entry in sorted(media_index.values(), key=lambda item: item.media_asset_id):
        if not entry.file_path.is_file():
            raise ProjectionV2PreflightError(f"global media file is missing: {entry.file_path}")
        actual_size, actual_hash = sha256_file(entry.file_path)
        if actual_size != entry.identity.file_size or actual_hash != entry.identity.content_hash:
            raise ProjectionV2PreflightError(
                f"global media identity mismatch for {entry.media_asset_id}: "
                f"expected {entry.identity.file_size}/{entry.identity.content_hash}, got {actual_size}/{actual_hash}"
            )
    return len(actual_files)


def target_db_counts(database_url: str) -> dict[str, int]:
    with psycopg.connect(database_url) as conn:
        conn.autocommit = True
        conn.execute("set default_transaction_read_only = on")
        conn.autocommit = False
        with conn.transaction():
            conn.execute("set transaction read only, isolation level repeatable read")
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    """
                    select
                      (select count(*) from app.courses) as courses,
                      (select count(*) from app.lessons) as lessons,
                      (select count(*) from app.lesson_contents) as lesson_contents,
                      (select count(*) from app.lesson_media) as lesson_media,
                      (select count(*) from app.media_assets) as media_assets
                    """
                )
                row = cur.fetchone()
    return {key: int(row[key]) for key in row.keys()}


def validate_target_db(database_url: str, allow_non_empty: bool) -> tuple[str, dict[str, int]]:
    require_local_database(database_url)
    counts = target_db_counts(database_url)
    non_empty = {name: count for name, count in counts.items() if count != 0}
    if non_empty and not allow_non_empty:
        raise ProjectionV2PreflightError(
            f"target DB is not empty; rerun with --allow-non-empty-target for validation-only mode: {non_empty}"
        )
    status = "ALLOWED_NON_EMPTY_READONLY" if non_empty else "EMPTY_TARGET_READONLY"
    return status, counts


def preflight(export_root: Path, database_url: str, allow_non_empty_target: bool) -> PreflightResult:
    export_root = resolve_export_root(str(export_root))
    course_count, lesson_count, media_index = build_global_media_index(export_root)
    global_media_files = verify_global_media_files(export_root, media_index)
    target_status, counts = validate_target_db(database_url, allow_non_empty_target)
    placement_count = sum(len(entry.placements) for entry in media_index.values())
    return PreflightResult(
        courses=course_count,
        lessons=lesson_count,
        media_assets=len(media_index),
        placements=placement_count,
        validation_status="PASS",
        target_db_status=target_status,
        target_db_counts=counts,
        global_media_files=global_media_files,
        orphan_media_files=0,
        duplicate_identity_conflicts=0,
        id_conflicts=0,
    )


def main() -> int:
    args = parse_args()
    result = preflight(
        export_root=Path(args.export_root),
        database_url=args.database_url,
        allow_non_empty_target=bool(args.allow_non_empty_target),
    )
    print(json.dumps(result.__dict__, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
