#!/usr/bin/env python3
"""Export canonical Baseline V2 course content to a deterministic filesystem projection."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any
from urllib.parse import urlsplit

try:
    import psycopg
    from psycopg.rows import dict_row
except Exception as exc:  # pragma: no cover - surfaced in direct script usage
    raise SystemExit("psycopg is required for Baseline V2 projection export") from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local"
DEFAULT_EXPORT_ROOT = REPO_ROOT / "canonical_projection_export"
READ_CHUNK_SIZE = 1024 * 1024
PROJECTION_SCHEMA = "aveli.baseline_v2.course_projection.v1"


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


@dataclass(frozen=True)
class ExportStats:
    courses_exported: int = 0
    lessons_exported: int = 0
    content_files_written: int = 0
    media_files_written: int = 0
    course_manifests_written: int = 0
    errors: int = 0


class ProjectionError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export canonical Baseline V2 course projection from a local DB."
    )
    parser.add_argument(
        "--database-url",
        default=os.environ.get("AVELI_LOCAL_DATABASE_URL")
        or os.environ.get("DATABASE_URL")
        or DEFAULT_DATABASE_URL,
        help="Local PostgreSQL URL. Defaults to aveli_local on 127.0.0.1.",
    )
    parser.add_argument(
        "--export-root",
        default=str(DEFAULT_EXPORT_ROOT),
        help="Projection root. Output is written under <export-root>/courses/.",
    )
    parser.add_argument(
        "--media-root",
        default=str(REPO_ROOT),
        help="Root used to resolve media_assets.original_object_path.",
    )
    return parser.parse_args()


def require_local_database(database_url: str) -> str:
    parsed = urlsplit(database_url)
    if parsed.scheme not in {"postgresql", "postgres"}:
        raise ProjectionError(f"database URL must be PostgreSQL, got {parsed.scheme!r}")
    if parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise ProjectionError(f"refusing export from non-local host {parsed.hostname!r}")
    database = parsed.path.lstrip("/")
    if not database:
        raise ProjectionError("database URL must include a database name")
    return database


def resolve_root(path_value: str, *, must_exist: bool) -> Path:
    path = Path(path_value).expanduser().resolve()
    if must_exist and not path.is_dir():
        raise ProjectionError(f"required directory does not exist: {path}")
    return path


def assert_fresh_export_root(export_root: Path) -> None:
    if export_root.exists():
        raise ProjectionError(
            f"export root already exists; refusing possible collision: {export_root}"
        )


def resolve_media_path(media_root: Path, original_object_path: str) -> Path:
    raw = str(original_object_path or "").strip()
    if not raw:
        raise ProjectionError("original_object_path is blank")
    if Path(raw).is_absolute() or PureWindowsPath(raw).is_absolute():
        raise ProjectionError(f"absolute original_object_path is not allowed: {raw}")

    normalized = raw.replace("\\", "/")
    parts = PurePosixPath(normalized).parts
    if not parts or any(part == ".." for part in parts):
        raise ProjectionError(f"path traversal is not allowed: {raw}")

    candidate = (media_root / Path(*parts)).resolve(strict=False)
    common = os.path.commonpath(
        [os.path.normcase(str(media_root)), os.path.normcase(str(candidate))]
    )
    if common != os.path.normcase(str(media_root)):
        raise ProjectionError(f"media path resolves outside media root: {raw}")
    return candidate


def media_extension(ingest_format: str) -> str:
    normalized = str(ingest_format or "").strip().lower().lstrip(".")
    if normalized not in SAFE_INGEST_FORMATS:
        raise ProjectionError(f"unsafe or unsupported ingest_format: {ingest_format!r}")
    return f".{normalized}"


def course_folder_name(group_position: int, course_id: str) -> str:
    if group_position < 0:
        raise ProjectionError(f"group_position must be nonnegative: {group_position}")
    return f"course_{group_position:04d}_{course_id}"


def lesson_folder_name(position: int, lesson_id: str) -> str:
    if position < 1:
        raise ProjectionError(f"lesson position must be >= 1: {position}")
    return f"lesson_{position:04d}_{lesson_id}"


def media_file_name(position: int, media_asset_id: str, ingest_format: str) -> str:
    if position < 1:
        raise ProjectionError(f"media position must be >= 1: {position}")
    return f"media_{position:04d}_{media_asset_id}{media_extension(ingest_format)}"


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


def copy_verified_media(source: Path, target: Path, expected_size: int, expected_hash: str) -> None:
    if not source.is_file():
        raise ProjectionError(f"media source does not exist or is not a file: {source}")

    source_size, source_hash = sha256_file(source)
    if source_size != expected_size or source_hash != expected_hash:
        raise ProjectionError(
            "media source identity mismatch: "
            f"{source} expected size/hash {expected_size}/{expected_hash}, "
            f"got {source_size}/{source_hash}"
        )

    target.parent.mkdir(parents=True, exist_ok=True)
    hasher = hashlib.sha256()
    byte_count = 0
    with source.open("rb") as source_handle, target.open("xb") as target_handle:
        while True:
            chunk = source_handle.read(READ_CHUNK_SIZE)
            if not chunk:
                break
            target_handle.write(chunk)
            byte_count += len(chunk)
            hasher.update(chunk)

    if byte_count != expected_size or hasher.hexdigest() != expected_hash:
        raise ProjectionError(
            f"written media identity mismatch for {target}: {byte_count}/{hasher.hexdigest()}"
        )


def write_text_file_once(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def write_json_file_once(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def fetchall(conn: psycopg.Connection, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def scalar(conn: psycopg.Connection, sql: str) -> int:
    with conn.cursor() as cur:
        cur.execute(sql)
        value = cur.fetchone()[0]
    return int(value)


def validate_contract(conn: psycopg.Connection) -> None:
    checks = {
        "duplicate course ordering": """
            select count(*) from (
              select course_group_id, group_position
              from app.courses
              group by course_group_id, group_position
              having count(*) > 1
            ) x
        """,
        "duplicate lesson positions": """
            select count(*) from (
              select course_id, position
              from app.lessons
              group by course_id, position
              having count(*) > 1
            ) x
        """,
        "duplicate media positions": """
            select count(*) from (
              select lesson_id, position
              from app.lesson_media
              group by lesson_id, position
              having count(*) > 1
            ) x
        """,
        "missing lesson content": """
            select count(*)
            from app.lessons l
            left join app.lesson_contents lc on lc.lesson_id = l.id
            where lc.lesson_id is null
        """,
        "orphaned lesson media": """
            select count(*)
            from app.lesson_media lm
            left join app.lessons l on l.id = lm.lesson_id
            left join app.media_assets ma on ma.id = lm.media_asset_id
            where l.id is null or ma.id is null
        """,
        "wrong-purpose lesson media": """
            select count(*)
            from app.lesson_media lm
            join app.media_assets ma on ma.id = lm.media_asset_id
            where ma.purpose <> 'lesson_media'::app.media_purpose
        """,
        "invalid media identity": """
            select count(*)
            from app.media_assets
            where file_size is null
               or file_size < 0
               or content_hash_algorithm <> 'sha256'
               or content_hash is null
               or content_hash !~ '^[0-9a-f]{64}$'
        """,
        "duplicate media identity": """
            select count(*) from (
              select content_hash_algorithm, content_hash, file_size
              from app.media_assets
              group by content_hash_algorithm, content_hash, file_size
              having count(*) > 1
            ) x
        """,
        "unreferenced media assets": """
            select count(*)
            from app.media_assets ma
            where not exists (
              select 1 from app.lesson_media lm where lm.media_asset_id = ma.id
            )
        """,
    }
    failures = {name: scalar(conn, sql) for name, sql in checks.items() if scalar(conn, sql) != 0}
    if failures:
        raise ProjectionError(f"projection contract validation failed: {failures}")


def load_courses(conn: psycopg.Connection) -> list[dict[str, Any]]:
    return fetchall(
        conn,
        """
        select id::text,
               teacher_id::text,
               title,
               slug,
               course_group_id::text,
               group_position,
               visibility::text,
               content_ready,
               price_amount_cents,
               stripe_product_id,
               active_stripe_price_id,
               sellable,
               drip_enabled,
               drip_interval_days,
               cover_media_id::text,
               created_at,
               updated_at
        from app.courses
        order by course_group_id asc, group_position asc, id asc
        """,
    )


def load_lessons(conn: psycopg.Connection, course_id: str) -> list[dict[str, Any]]:
    return fetchall(
        conn,
        """
        select l.id::text,
               l.lesson_title,
               l.position,
               l.created_at,
               l.updated_at,
               lc.content_markdown
        from app.lessons l
        join app.lesson_contents lc on lc.lesson_id = l.id
        where l.course_id = %s
        order by l.position asc, l.id asc
        """,
        (course_id,),
    )


def load_lesson_media(conn: psycopg.Connection, lesson_id: str) -> list[dict[str, Any]]:
    return fetchall(
        conn,
        """
        select lm.id::text as lesson_media_id,
               lm.position,
               ma.id::text as media_asset_id,
               ma.media_type::text,
               ma.purpose::text,
               ma.original_object_path,
               ma.ingest_format,
               ma.file_size,
               ma.content_hash_algorithm,
               ma.content_hash,
               ma.created_at as media_asset_created_at,
               ma.updated_at as media_asset_updated_at
        from app.lesson_media lm
        join app.media_assets ma on ma.id = lm.media_asset_id
        where lm.lesson_id = %s
        order by lm.position asc, lm.id asc
        """,
        (lesson_id,),
    )


def iso(value: Any) -> str | None:
    return value.isoformat() if value is not None else None


def export_projection(database_url: str, export_root: Path, media_root: Path) -> dict[str, Any]:
    database_name = require_local_database(database_url)
    assert_fresh_export_root(export_root)

    written_paths: set[Path] = set()
    stats = {
        "courses_exported": 0,
        "lessons_exported": 0,
        "content_files_written": 0,
        "media_files_written": 0,
        "course_manifests_written": 0,
        "errors": 0,
    }

    try:
        courses_root = export_root / "courses"
        with psycopg.connect(database_url) as conn:
            conn.execute("set default_transaction_read_only = on")
            validate_contract(conn)
            courses = load_courses(conn)

            for course in courses:
                course_folder = course_folder_name(
                    int(course["group_position"]),
                    str(course["id"]),
                )
                course_dir = courses_root / course_folder
                lessons_dir = course_dir / "lessons"
                lessons_payload: list[dict[str, Any]] = []

                lessons = load_lessons(conn, str(course["id"]))
                for lesson in lessons:
                    lesson_folder = lesson_folder_name(int(lesson["position"]), str(lesson["id"]))
                    lesson_dir = lessons_dir / lesson_folder
                    content_path = lesson_dir / "content.md"
                    relative_content_path = content_path.relative_to(course_dir).as_posix()

                    if content_path in written_paths:
                        raise ProjectionError(f"duplicate target path: {content_path}")
                    write_text_file_once(
                        content_path,
                        str(lesson["content_markdown"] or ""),
                    )
                    written_paths.add(content_path)
                    stats["content_files_written"] += 1
                    stats["lessons_exported"] += 1

                    media_payload: list[dict[str, Any]] = []
                    media_rows = load_lesson_media(conn, str(lesson["id"]))
                    for media in media_rows:
                        expected_size = int(media["file_size"])
                        expected_hash = str(media["content_hash"])
                        source_path = resolve_media_path(media_root, str(media["original_object_path"]))
                        media_name = media_file_name(
                            int(media["position"]),
                            str(media["media_asset_id"]),
                            str(media["ingest_format"]),
                        )
                        target_path = lesson_dir / "media" / media_name
                        if target_path in written_paths:
                            raise ProjectionError(f"duplicate target path: {target_path}")
                        copy_verified_media(source_path, target_path, expected_size, expected_hash)
                        written_paths.add(target_path)
                        stats["media_files_written"] += 1

                        media_payload.append(
                            {
                                "lesson_media_id": media["lesson_media_id"],
                                "position": int(media["position"]),
                                "media_asset_id": media["media_asset_id"],
                                "file": target_path.relative_to(course_dir).as_posix(),
                                "media_type": media["media_type"],
                                "purpose": media["purpose"],
                                "original_object_path": media["original_object_path"],
                                "ingest_format": media["ingest_format"],
                                "file_size": expected_size,
                                "content_hash_algorithm": media["content_hash_algorithm"],
                                "content_hash": expected_hash,
                                "media_asset_created_at": iso(media["media_asset_created_at"]),
                                "media_asset_updated_at": iso(media["media_asset_updated_at"]),
                            }
                        )

                    lessons_payload.append(
                        {
                            "id": lesson["id"],
                            "folder": lesson_folder,
                            "title": lesson["lesson_title"],
                            "position": int(lesson["position"]),
                            "created_at": iso(lesson["created_at"]),
                            "updated_at": iso(lesson["updated_at"]),
                            "content_file": relative_content_path,
                            "media": media_payload,
                        }
                    )

                course_manifest = {
                    "schema": PROJECTION_SCHEMA,
                    "source_database": database_name,
                    "course": {
                        "id": course["id"],
                        "teacher_id": course["teacher_id"],
                        "title": course["title"],
                        "slug": course["slug"],
                        "course_group_id": course["course_group_id"],
                        "group_position": int(course["group_position"]),
                        "visibility": course["visibility"],
                        "content_ready": bool(course["content_ready"]),
                        "price_amount_cents": course["price_amount_cents"],
                        "stripe_product_id": course["stripe_product_id"],
                        "active_stripe_price_id": course["active_stripe_price_id"],
                        "sellable": bool(course["sellable"]),
                        "drip_enabled": bool(course["drip_enabled"]),
                        "drip_interval_days": course["drip_interval_days"],
                        "cover_media_id": course["cover_media_id"],
                        "created_at": iso(course["created_at"]),
                        "updated_at": iso(course["updated_at"]),
                    },
                    "lessons": lessons_payload,
                }

                manifest_path = course_dir / "course.json"
                if manifest_path in written_paths:
                    raise ProjectionError(f"duplicate target path: {manifest_path}")
                write_json_file_once(manifest_path, course_manifest)
                written_paths.add(manifest_path)
                stats["course_manifests_written"] += 1
                stats["courses_exported"] += 1
    except Exception:
        if export_root.exists():
            shutil.rmtree(export_root)
        raise

    stats["files_written_total"] = len(written_paths)
    stats["export_root"] = str(export_root)
    stats["courses_root"] = str(export_root / "courses")
    return stats


def main() -> int:
    args = parse_args()
    export_root = resolve_root(args.export_root, must_exist=False)
    media_root = resolve_root(args.media_root, must_exist=True)
    result = export_projection(args.database_url, export_root, media_root)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
