#!/usr/bin/env python3
"""Export Baseline V2 course content using Projection V2 global media storage."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any
from urllib.parse import urlsplit

try:
    import psycopg
    from psycopg.rows import dict_row
except Exception as exc:  # pragma: no cover - surfaced in direct script usage
    raise SystemExit("psycopg is required for Baseline V2 Projection V2 export") from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local"
DEFAULT_EXPORT_ROOT = REPO_ROOT / "canonical_projection_export_v2"
PROJECTION_SCHEMA = "aveli.baseline_v2.course_projection.v2"
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

RELATIVE_GLOBAL_MEDIA_PREFIX = PurePosixPath("..") / ".." / "media"


class ProjectionV2Error(RuntimeError):
    pass


@dataclass(frozen=True)
class MediaAsset:
    id: str
    media_type: str
    purpose: str
    original_object_path: str
    ingest_format: str
    file_size: int
    content_hash_algorithm: str
    content_hash: str
    created_at: Any
    updated_at: Any


@dataclass(frozen=True)
class LessonMedia:
    id: str
    lesson_id: str
    position: int
    media_asset_id: str


@dataclass(frozen=True)
class Lesson:
    id: str
    course_id: str
    title: str
    position: int
    created_at: Any
    updated_at: Any
    content_markdown: str


@dataclass(frozen=True)
class Course:
    id: str
    teacher_id: str | None
    title: str
    slug: str | None
    course_group_id: str | None
    group_position: int
    visibility: str
    content_ready: bool
    price_amount_cents: int | None
    stripe_product_id: str | None
    active_stripe_price_id: str | None
    sellable: bool
    drip_enabled: bool
    drip_interval_days: int | None
    cover_media_id: str | None
    created_at: Any
    updated_at: Any


@dataclass
class Snapshot:
    basis_counts: dict[str, int]
    schema_column_counts: dict[str, int]
    courses: list[Course]
    lessons_by_course: dict[str, list[Lesson]]
    lesson_media_by_lesson: dict[str, list[LessonMedia]]
    media_assets_by_id: dict[str, MediaAsset]


@dataclass
class ExportState:
    export_root: Path
    courses_root: Path
    global_media_root: Path
    allow_existing: bool
    expected_files: set[str] = field(default_factory=set)
    expected_dirs: set[str] = field(default_factory=set)
    written_or_verified_targets: set[str] = field(default_factory=set)
    written_global_media: set[str] = field(default_factory=set)
    manifest_media_references: int = 0
    duplicate_target_path_conflicts: int = 0
    content_files_written: int = 0
    content_files_verified_existing: int = 0
    course_manifests_written: int = 0
    course_manifests_verified_existing: int = 0
    global_media_files_written: int = 0
    global_media_files_verified_existing: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export Baseline V2 Projection V2 with a global media store."
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
        help="Projection root. Output is written under <export-root>/courses and <export-root>/media.",
    )
    parser.add_argument(
        "--media-root",
        default=str(REPO_ROOT),
        help="Root used to resolve media_assets.original_object_path for source bytes.",
    )
    parser.add_argument(
        "--allow-existing",
        action="store_true",
        help="Verify identical existing target files instead of failing when the export root exists.",
    )
    return parser.parse_args()


def normalize_path(path: Path) -> str:
    return os.path.normcase(str(path.resolve(strict=False)))


def require_local_database(database_url: str) -> str:
    parsed = urlsplit(database_url)
    if parsed.scheme not in {"postgresql", "postgres"}:
        raise ProjectionV2Error(f"database URL must be PostgreSQL, got {parsed.scheme!r}")
    if parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise ProjectionV2Error(f"refusing export from non-local host {parsed.hostname!r}")
    database = parsed.path.lstrip("/")
    if not database:
        raise ProjectionV2Error("database URL must include a database name")
    return database


def resolve_root(path_value: str, *, must_exist: bool) -> Path:
    path = Path(path_value).expanduser().resolve()
    if must_exist and not path.is_dir():
        raise ProjectionV2Error(f"required directory does not exist: {path}")
    return path


def prepare_export_root(export_root: Path, allow_existing: bool) -> None:
    if export_root.exists() and not export_root.is_dir():
        raise ProjectionV2Error(f"export root exists but is not a directory: {export_root}")
    if export_root.exists() and not allow_existing:
        raise ProjectionV2Error(
            f"export root already exists; use --allow-existing only for idempotent verification: {export_root}"
        )


def assert_safe_identifier(value: str, field_name: str) -> None:
    if not value:
        raise ProjectionV2Error(f"{field_name} is blank")
    if any(part in value for part in ("/", "\\", "..")):
        raise ProjectionV2Error(f"{field_name} contains unsafe path characters: {value!r}")


def media_extension(ingest_format: str) -> str:
    normalized = str(ingest_format or "").strip().lower().lstrip(".")
    if normalized not in SAFE_INGEST_FORMATS:
        raise ProjectionV2Error(f"unsafe or unsupported ingest_format: {ingest_format!r}")
    return f".{normalized}"


def course_folder_name(group_position: int, course_id: str) -> str:
    if group_position < 0:
        raise ProjectionV2Error(f"group_position must be nonnegative: {group_position}")
    assert_safe_identifier(course_id, "course_id")
    return f"course_{group_position:04d}_{course_id}"


def lesson_folder_name(position: int, lesson_id: str) -> str:
    if position < 1:
        raise ProjectionV2Error(f"lesson position must be >= 1: {position}")
    assert_safe_identifier(lesson_id, "lesson_id")
    return f"lesson_{position:04d}_{lesson_id}"


def global_media_file_name(media_asset_id: str, ingest_format: str) -> str:
    assert_safe_identifier(media_asset_id, "media_asset_id")
    return f"{media_asset_id}{media_extension(ingest_format)}"


def resolve_media_path(media_root: Path, original_object_path: str) -> Path:
    raw = str(original_object_path or "").strip()
    if not raw:
        raise ProjectionV2Error("original_object_path is blank")
    if Path(raw).is_absolute() or PureWindowsPath(raw).is_absolute():
        raise ProjectionV2Error(f"absolute original_object_path is not allowed: {raw}")

    normalized = raw.replace("\\", "/")
    parts = PurePosixPath(normalized).parts
    if not parts or any(part == ".." for part in parts):
        raise ProjectionV2Error(f"path traversal is not allowed: {raw}")

    candidate = (media_root / Path(*parts)).resolve(strict=False)
    common = os.path.commonpath([normalize_path(media_root), normalize_path(candidate)])
    if common != normalize_path(media_root):
        raise ProjectionV2Error(f"media path resolves outside media root: {raw}")
    return candidate


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


def verify_file_identity(path: Path, expected_size: int, expected_hash: str, label: str) -> None:
    if not path.is_file():
        raise ProjectionV2Error(f"{label} does not exist or is not a file: {path}")
    actual_size, actual_hash = sha256_file(path)
    if actual_size != expected_size or actual_hash != expected_hash:
        raise ProjectionV2Error(
            f"{label} identity mismatch for {path}: "
            f"expected {expected_size}/{expected_hash}, got {actual_size}/{actual_hash}"
        )


def stream_copy_with_identity(source: Path, target: Path) -> tuple[int, str]:
    hasher = hashlib.sha256()
    byte_count = 0
    target.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as source_handle, target.open("xb") as target_handle:
        while True:
            chunk = source_handle.read(READ_CHUNK_SIZE)
            if not chunk:
                break
            target_handle.write(chunk)
            byte_count += len(chunk)
            hasher.update(chunk)
    return byte_count, hasher.hexdigest()


def add_expected_dir(state: ExportState, path: Path) -> None:
    state.expected_dirs.add(normalize_path(path))


def add_expected_file(state: ExportState, path: Path) -> None:
    state.expected_files.add(normalize_path(path))


def register_target_once(state: ExportState, path: Path) -> None:
    normalized = normalize_path(path)
    if normalized in state.written_or_verified_targets:
        state.duplicate_target_path_conflicts += 1
        raise ProjectionV2Error(f"duplicate deterministic target path collision: {path}")
    state.written_or_verified_targets.add(normalized)
    add_expected_file(state, path)


def write_text_expected(state: ExportState, path: Path, content: str, kind: str) -> bool:
    register_target_once(state, path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if not state.allow_existing:
            raise ProjectionV2Error(f"{kind} target already exists: {path}")
        existing = path.read_text(encoding="utf-8")
        if existing != content:
            raise ProjectionV2Error(f"{kind} target exists with different content: {path}")
        return False
    with path.open("x", encoding="utf-8", newline="") as handle:
        handle.write(content)
    return True


def write_json_expected(state: ExportState, path: Path, payload: dict[str, Any], kind: str) -> bool:
    content = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    return write_text_expected(state, path, content, kind)


def iso(value: Any) -> str | None:
    return value.isoformat() if value is not None else None


def fetchall(conn: psycopg.Connection, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def scalar(conn: psycopg.Connection, sql: str, params: tuple[Any, ...] = ()) -> int:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        value = cur.fetchone()[0]
    return int(value)


def table_counts(conn: psycopg.Connection) -> dict[str, int]:
    tables = ["courses", "lessons", "lesson_contents", "lesson_media", "media_assets"]
    return {table: scalar(conn, f"select count(*) from app.{table}") for table in tables}


def schema_column_counts(conn: psycopg.Connection) -> dict[str, int]:
    rows = fetchall(
        conn,
        """
        select table_name, count(*)::int as column_count
        from information_schema.columns
        where table_schema = 'app'
          and table_name in ('courses', 'lessons', 'lesson_contents', 'lesson_media', 'media_assets')
        group by table_name
        order by table_name
        """,
    )
    return {str(row["table_name"]): int(row["column_count"]) for row in rows}


def validation_failures(conn: psycopg.Connection) -> dict[str, int]:
    checks = {
        "duplicate_course_folders": """
            select count(*) from (
              select 'course_' || lpad(group_position::text, 4, '0') || '_' || id::text
              from app.courses
              group by 1
              having count(*) > 1
            ) x
        """,
        "invalid_course_position": """
            select count(*) from app.courses where group_position is null or group_position < 0
        """,
        "duplicate_lesson_folders": """
            select count(*) from (
              select course_id, 'lesson_' || lpad(position::text, 4, '0') || '_' || id::text
              from app.lessons
              group by 1, 2
              having count(*) > 1
            ) x
        """,
        "invalid_lesson_position": """
            select count(*) from app.lessons where position is null or position < 1
        """,
        "missing_lesson_content": """
            select count(*)
            from app.lessons l
            left join app.lesson_contents lc on lc.lesson_id = l.id
            where lc.lesson_id is null or lc.content_markdown is null
        """,
        "orphaned_lessons": """
            select count(*)
            from app.lessons l
            left join app.courses c on c.id = l.course_id
            where c.id is null
        """,
        "orphaned_lesson_media": """
            select count(*)
            from app.lesson_media lm
            left join app.lessons l on l.id = lm.lesson_id
            left join app.media_assets ma on ma.id = lm.media_asset_id
            where l.id is null or ma.id is null
        """,
        "wrong_purpose_lesson_media": """
            select count(*)
            from app.lesson_media lm
            join app.media_assets ma on ma.id = lm.media_asset_id
            where ma.purpose <> 'lesson_media'::app.media_purpose
        """,
        "invalid_referenced_media_identity": """
            select count(*)
            from (
              select distinct ma.*
              from app.lesson_media lm
              join app.media_assets ma on ma.id = lm.media_asset_id
            ) ma
            where ma.file_size is null
               or ma.file_size < 0
               or ma.content_hash_algorithm <> 'sha256'
               or ma.content_hash is null
               or ma.content_hash !~ '^[0-9a-f]{64}$'
               or ma.content_identity_error is not null
               or ma.ingest_format is null
               or ma.original_object_path is null
        """,
        "unreferenced_media_assets": """
            select count(*)
            from app.media_assets ma
            where not exists (
              select 1 from app.lesson_media lm where lm.media_asset_id = ma.id
            )
        """,
        "course_cover_media_refs": """
            select count(*) from app.courses where cover_media_id is not null
        """,
        "duplicate_media_identity": """
            select count(*) from (
              select content_hash_algorithm, content_hash, file_size
              from app.media_assets
              group by content_hash_algorithm, content_hash, file_size
              having count(*) > 1
            ) x
        """,
    }
    return {name: scalar(conn, sql) for name, sql in checks.items() if scalar(conn, sql) != 0}


def load_courses(conn: psycopg.Connection) -> list[Course]:
    rows = fetchall(
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
        order by group_position asc, id asc
        """,
    )
    return [
        Course(
            id=str(row["id"]),
            teacher_id=row["teacher_id"],
            title=str(row["title"]),
            slug=row["slug"],
            course_group_id=row["course_group_id"],
            group_position=int(row["group_position"]),
            visibility=str(row["visibility"]),
            content_ready=bool(row["content_ready"]),
            price_amount_cents=row["price_amount_cents"],
            stripe_product_id=row["stripe_product_id"],
            active_stripe_price_id=row["active_stripe_price_id"],
            sellable=bool(row["sellable"]),
            drip_enabled=bool(row["drip_enabled"]),
            drip_interval_days=row["drip_interval_days"],
            cover_media_id=row["cover_media_id"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
        for row in rows
    ]


def load_lessons(conn: psycopg.Connection) -> dict[str, list[Lesson]]:
    rows = fetchall(
        conn,
        """
        select l.id::text,
               l.course_id::text,
               l.lesson_title,
               l.position,
               l.created_at,
               l.updated_at,
               lc.content_markdown
        from app.lessons l
        join app.lesson_contents lc on lc.lesson_id = l.id
        order by l.course_id asc, l.position asc, l.id asc
        """,
    )
    lessons_by_course: dict[str, list[Lesson]] = {}
    for row in rows:
        lesson = Lesson(
            id=str(row["id"]),
            course_id=str(row["course_id"]),
            title=str(row["lesson_title"]),
            position=int(row["position"]),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            content_markdown=str(row["content_markdown"]),
        )
        lessons_by_course.setdefault(lesson.course_id, []).append(lesson)
    for lessons in lessons_by_course.values():
        lessons.sort(key=lambda lesson: (lesson.position, lesson.id))
    return lessons_by_course


def load_lesson_media(conn: psycopg.Connection) -> dict[str, list[LessonMedia]]:
    rows = fetchall(
        conn,
        """
        select id::text,
               lesson_id::text,
               position,
               media_asset_id::text
        from app.lesson_media
        order by lesson_id asc, position asc, id asc
        """,
    )
    media_by_lesson: dict[str, list[LessonMedia]] = {}
    for row in rows:
        lesson_media = LessonMedia(
            id=str(row["id"]),
            lesson_id=str(row["lesson_id"]),
            position=int(row["position"]),
            media_asset_id=str(row["media_asset_id"]),
        )
        media_by_lesson.setdefault(lesson_media.lesson_id, []).append(lesson_media)
    for media_rows in media_by_lesson.values():
        media_rows.sort(key=lambda media: (media.position, media.id))
    return media_by_lesson


def load_referenced_media_assets(conn: psycopg.Connection) -> dict[str, MediaAsset]:
    rows = fetchall(
        conn,
        """
        select distinct
               ma.id::text,
               ma.media_type::text,
               ma.purpose::text,
               ma.original_object_path,
               ma.ingest_format,
               ma.file_size,
               ma.content_hash_algorithm,
               ma.content_hash,
               ma.created_at,
               ma.updated_at
        from app.lesson_media lm
        join app.media_assets ma on ma.id = lm.media_asset_id
        order by ma.id::text asc
        """,
    )
    assets: dict[str, MediaAsset] = {}
    for row in rows:
        asset = MediaAsset(
            id=str(row["id"]),
            media_type=str(row["media_type"]),
            purpose=str(row["purpose"]),
            original_object_path=str(row["original_object_path"]),
            ingest_format=str(row["ingest_format"]),
            file_size=int(row["file_size"]),
            content_hash_algorithm=str(row["content_hash_algorithm"]),
            content_hash=str(row["content_hash"]),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
        assets[asset.id] = asset
    return assets


def run_readonly_snapshot(database_url: str) -> Snapshot:
    with psycopg.connect(database_url) as conn:
        conn.autocommit = True
        conn.execute("set default_transaction_read_only = on")
        conn.autocommit = False
        with conn.transaction():
            conn.execute("set transaction read only, isolation level repeatable read")
            failures = validation_failures(conn)
            if failures:
                raise ProjectionV2Error(f"Projection V2 contract validation failed: {failures}")
            return Snapshot(
                basis_counts=table_counts(conn),
                schema_column_counts=schema_column_counts(conn),
                courses=load_courses(conn),
                lessons_by_course=load_lessons(conn),
                lesson_media_by_lesson=load_lesson_media(conn),
                media_assets_by_id=load_referenced_media_assets(conn),
            )


def read_counts_readonly(database_url: str) -> tuple[dict[str, int], dict[str, int]]:
    with psycopg.connect(database_url) as conn:
        conn.autocommit = True
        conn.execute("set default_transaction_read_only = on")
        conn.autocommit = False
        with conn.transaction():
            conn.execute("set transaction read only, isolation level repeatable read")
            return table_counts(conn), schema_column_counts(conn)


def validate_manifest_media_path(
    course_dir: Path,
    global_media_root: Path,
    media_asset: MediaAsset,
) -> str:
    file_name = global_media_file_name(media_asset.id, media_asset.ingest_format)
    if Path(file_name).stem != media_asset.id:
        raise ProjectionV2Error(f"media filename stem does not match media_asset_id: {file_name}")
    if Path(file_name).suffix != media_extension(media_asset.ingest_format):
        raise ProjectionV2Error(f"media filename extension does not match ingest_format: {file_name}")

    relative_path = RELATIVE_GLOBAL_MEDIA_PREFIX / file_name
    target_path = global_media_root / file_name
    resolved = (course_dir / Path(*relative_path.parts)).resolve(strict=False)
    if normalize_path(resolved) != normalize_path(target_path):
        raise ProjectionV2Error(
            f"invalid relative media path {relative_path.as_posix()} for target {target_path}"
        )
    common = os.path.commonpath([normalize_path(global_media_root), normalize_path(resolved)])
    if common != normalize_path(global_media_root):
        raise ProjectionV2Error(f"relative media path escapes global media root: {relative_path}")
    return relative_path.as_posix()


def materialize_global_media(
    state: ExportState,
    media_root: Path,
    media_asset: MediaAsset,
) -> Path:
    if media_asset.content_hash_algorithm != "sha256":
        raise ProjectionV2Error(
            f"media asset {media_asset.id} has unsupported hash algorithm {media_asset.content_hash_algorithm!r}"
        )
    if len(media_asset.content_hash) != 64 or any(c not in "0123456789abcdef" for c in media_asset.content_hash):
        raise ProjectionV2Error(f"media asset {media_asset.id} has invalid SHA256 hash")

    source_path = resolve_media_path(media_root, media_asset.original_object_path)
    verify_file_identity(source_path, media_asset.file_size, media_asset.content_hash, "media source")

    file_name = global_media_file_name(media_asset.id, media_asset.ingest_format)
    target_path = state.global_media_root / file_name
    register_target_once(state, target_path)
    add_expected_dir(state, state.global_media_root)

    if target_path.exists():
        if not state.allow_existing:
            raise ProjectionV2Error(f"global media target already exists: {target_path}")
        verify_file_identity(target_path, media_asset.file_size, media_asset.content_hash, "existing global media target")
        state.global_media_files_verified_existing += 1
    else:
        actual_size, actual_hash = stream_copy_with_identity(source_path, target_path)
        if actual_size != media_asset.file_size or actual_hash != media_asset.content_hash:
            raise ProjectionV2Error(
                f"written global media identity mismatch for {target_path}: "
                f"expected {media_asset.file_size}/{media_asset.content_hash}, got {actual_size}/{actual_hash}"
            )
        verify_file_identity(target_path, media_asset.file_size, media_asset.content_hash, "written global media target")
        state.global_media_files_written += 1

    state.written_global_media.add(media_asset.id)
    return target_path


def course_payload(course: Course) -> dict[str, Any]:
    return {
        "id": course.id,
        "teacher_id": course.teacher_id,
        "title": course.title,
        "slug": course.slug,
        "course_group_id": course.course_group_id,
        "group_position": course.group_position,
        "visibility": course.visibility,
        "content_ready": course.content_ready,
        "price_amount_cents": course.price_amount_cents,
        "stripe_product_id": course.stripe_product_id,
        "active_stripe_price_id": course.active_stripe_price_id,
        "sellable": course.sellable,
        "drip_enabled": course.drip_enabled,
        "drip_interval_days": course.drip_interval_days,
        "cover_media_id": course.cover_media_id,
        "created_at": iso(course.created_at),
        "updated_at": iso(course.updated_at),
    }


def media_manifest_payload(
    course_dir: Path,
    global_media_root: Path,
    lesson_media: LessonMedia,
    media_asset: MediaAsset,
) -> dict[str, Any]:
    return {
        "lesson_media_id": lesson_media.id,
        "position": lesson_media.position,
        "media_asset_id": media_asset.id,
        "file": validate_manifest_media_path(course_dir, global_media_root, media_asset),
        "media_type": media_asset.media_type,
        "purpose": media_asset.purpose,
        "original_object_path": media_asset.original_object_path,
        "ingest_format": media_asset.ingest_format,
        "file_size": media_asset.file_size,
        "content_hash_algorithm": media_asset.content_hash_algorithm,
        "content_hash": media_asset.content_hash,
        "media_asset_created_at": iso(media_asset.created_at),
        "media_asset_updated_at": iso(media_asset.updated_at),
    }


def export_courses(state: ExportState, snapshot: Snapshot) -> tuple[int, int]:
    lessons_exported = 0
    for course in snapshot.courses:
        course_folder = course_folder_name(course.group_position, course.id)
        course_dir = state.courses_root / course_folder
        lessons_dir = course_dir / "lessons"
        add_expected_dir(state, course_dir)
        add_expected_dir(state, lessons_dir)
        lessons_dir.mkdir(parents=True, exist_ok=True)

        lessons_payload: list[dict[str, Any]] = []
        lessons = snapshot.lessons_by_course.get(course.id, [])
        for lesson in lessons:
            lesson_folder = lesson_folder_name(lesson.position, lesson.id)
            lesson_dir = lessons_dir / lesson_folder
            add_expected_dir(state, lesson_dir)

            content_path = lesson_dir / "content.md"
            content_written = write_text_expected(state, content_path, lesson.content_markdown, "content.md")
            if content_written:
                state.content_files_written += 1
            else:
                state.content_files_verified_existing += 1
            lessons_exported += 1

            media_payload: list[dict[str, Any]] = []
            for lesson_media in snapshot.lesson_media_by_lesson.get(lesson.id, []):
                media_asset = snapshot.media_assets_by_id.get(lesson_media.media_asset_id)
                if media_asset is None:
                    raise ProjectionV2Error(
                        f"lesson_media {lesson_media.id} references missing media asset {lesson_media.media_asset_id}"
                    )
                media_payload.append(
                    media_manifest_payload(course_dir, state.global_media_root, lesson_media, media_asset)
                )
                state.manifest_media_references += 1

            lessons_payload.append(
                {
                    "id": lesson.id,
                    "folder": lesson_folder,
                    "title": lesson.title,
                    "position": lesson.position,
                    "created_at": iso(lesson.created_at),
                    "updated_at": iso(lesson.updated_at),
                    "content_file": PurePosixPath("lessons", lesson_folder, "content.md").as_posix(),
                    "media": media_payload,
                }
            )

        manifest = {
            "schema": PROJECTION_SCHEMA,
            "source_database": "aveli_local",
            "projection": {
                "media_store": "global",
                "global_media_root": "../../media",
                "course_folder_rule": "course_<group_position_padded>_<course_id>",
                "lesson_folder_rule": "lesson_<position_padded>_<lesson_id>",
                "media_file_rule": "<media_asset_id>.<ext>",
            },
            "course": course_payload(course),
            "lessons": lessons_payload,
        }
        manifest_path = course_dir / "course.json"
        manifest_written = write_json_expected(state, manifest_path, manifest, "course.json")
        if manifest_written:
            state.course_manifests_written += 1
        else:
            state.course_manifests_verified_existing += 1

    return len(snapshot.courses), lessons_exported


def verify_output_structure(state: ExportState, snapshot: Snapshot) -> dict[str, int | bool]:
    expected_file_count = len(state.expected_files)
    actual_files = {normalize_path(path) for path in state.export_root.rglob("*") if path.is_file()}
    actual_dirs = {normalize_path(path) for path in state.export_root.rglob("*") if path.is_dir()}
    actual_dirs.add(normalize_path(state.export_root))

    extra_files = actual_files - state.expected_files
    missing_files = state.expected_files - actual_files
    extra_dirs = actual_dirs - state.expected_dirs
    missing_dirs = state.expected_dirs - actual_dirs

    if extra_files:
        raise ProjectionV2Error(f"unexpected output files found: {sorted(extra_files)[:10]}")
    if missing_files:
        raise ProjectionV2Error(f"expected output files missing: {sorted(missing_files)[:10]}")
    if extra_dirs:
        raise ProjectionV2Error(f"unexpected output directories found: {sorted(extra_dirs)[:10]}")
    if missing_dirs:
        raise ProjectionV2Error(f"expected output directories missing: {sorted(missing_dirs)[:10]}")

    top_level = {path.name for path in state.export_root.iterdir()}
    if top_level - {"courses", "media"}:
        raise ProjectionV2Error(f"Projection V2 output has invalid top-level entries: {sorted(top_level)}")

    lesson_local_media_dirs = [
        path
        for path in state.courses_root.rglob("media")
        if path.is_dir() and normalize_path(path) != normalize_path(state.global_media_root)
    ]
    if lesson_local_media_dirs:
        raise ProjectionV2Error(f"lesson-local media directories are forbidden: {lesson_local_media_dirs[:10]}")

    if any(path.is_dir() for path in state.global_media_root.rglob("*")):
        raise ProjectionV2Error("global media root must not contain subdirectories")

    expected_global_files = {
        normalize_path(state.global_media_root / global_media_file_name(asset.id, asset.ingest_format))
        for asset in snapshot.media_assets_by_id.values()
    }
    actual_global_files = {normalize_path(path) for path in state.global_media_root.glob("*") if path.is_file()}
    orphan_global_files = actual_global_files - expected_global_files
    missing_global_files = expected_global_files - actual_global_files
    if orphan_global_files:
        raise ProjectionV2Error(f"orphan global media files found: {sorted(orphan_global_files)[:10]}")
    if missing_global_files:
        raise ProjectionV2Error(f"expected global media files missing: {sorted(missing_global_files)[:10]}")

    for media_asset in snapshot.media_assets_by_id.values():
        target = state.global_media_root / global_media_file_name(media_asset.id, media_asset.ingest_format)
        verify_file_identity(target, media_asset.file_size, media_asset.content_hash, "global media verification")

    course_manifest_count = 0
    manifest_lesson_count = 0
    manifest_media_count = 0
    for manifest_path in state.courses_root.glob("*/course.json"):
        course_manifest_count += 1
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("schema") != PROJECTION_SCHEMA:
            raise ProjectionV2Error(f"course manifest has invalid schema: {manifest_path}")
        course_dir = manifest_path.parent
        for lesson in manifest.get("lessons", []):
            manifest_lesson_count += 1
            content_file = course_dir / Path(*PurePosixPath(str(lesson["content_file"])).parts)
            if normalize_path(content_file) not in state.expected_files:
                raise ProjectionV2Error(f"manifest content_file is not an expected target: {content_file}")
            for media in lesson.get("media", []):
                manifest_media_count += 1
                media_asset_id = str(media["media_asset_id"])
                media_asset = snapshot.media_assets_by_id.get(media_asset_id)
                if media_asset is None:
                    raise ProjectionV2Error(f"manifest references unknown media_asset_id: {media_asset_id}")
                expected_file = (
                    RELATIVE_GLOBAL_MEDIA_PREFIX
                    / global_media_file_name(media_asset.id, media_asset.ingest_format)
                ).as_posix()
                if media.get("file") != expected_file:
                    raise ProjectionV2Error(
                        f"manifest media file path mismatch for {media_asset_id}: {media.get('file')}"
                    )
                target = (course_dir / Path(*PurePosixPath(expected_file).parts)).resolve(strict=False)
                if normalize_path(target) not in expected_global_files:
                    raise ProjectionV2Error(f"manifest media target is not expected global media: {target}")
                if int(media["file_size"]) != media_asset.file_size:
                    raise ProjectionV2Error(f"manifest file_size mismatch for {media_asset_id}")
                if media["content_hash_algorithm"] != media_asset.content_hash_algorithm:
                    raise ProjectionV2Error(f"manifest hash algorithm mismatch for {media_asset_id}")
                if media["content_hash"] != media_asset.content_hash:
                    raise ProjectionV2Error(f"manifest hash mismatch for {media_asset_id}")

    if course_manifest_count != snapshot.basis_counts["courses"]:
        raise ProjectionV2Error(
            f"course manifest count mismatch: {course_manifest_count} != {snapshot.basis_counts['courses']}"
        )
    if manifest_lesson_count != snapshot.basis_counts["lessons"]:
        raise ProjectionV2Error(
            f"manifest lesson count mismatch: {manifest_lesson_count} != {snapshot.basis_counts['lessons']}"
        )
    if manifest_media_count != snapshot.basis_counts["lesson_media"]:
        raise ProjectionV2Error(
            f"manifest media reference count mismatch: {manifest_media_count} != {snapshot.basis_counts['lesson_media']}"
        )

    return {
        "expected_files": expected_file_count,
        "actual_files": len(actual_files),
        "course_manifests": course_manifest_count,
        "manifest_lessons": manifest_lesson_count,
        "manifest_media_references": manifest_media_count,
        "global_media_files": len(actual_global_files),
        "lesson_local_media_dirs": len(lesson_local_media_dirs),
        "orphan_global_media_files": len(orphan_global_files),
        "missing_global_media_files": len(missing_global_files),
        "top_level_valid": True,
    }


def export_projection_v2(
    database_url: str,
    export_root: Path,
    media_root: Path,
    allow_existing: bool,
) -> dict[str, Any]:
    database_name = require_local_database(database_url)
    if database_name != "aveli_local":
        raise ProjectionV2Error(f"refusing export from unexpected local database {database_name!r}")
    prepare_export_root(export_root, allow_existing)

    snapshot = run_readonly_snapshot(database_url)
    state = ExportState(
        export_root=export_root,
        courses_root=export_root / "courses",
        global_media_root=export_root / "media",
        allow_existing=allow_existing,
    )
    add_expected_dir(state, export_root)
    add_expected_dir(state, state.courses_root)
    add_expected_dir(state, state.global_media_root)

    state.courses_root.mkdir(parents=True, exist_ok=True)
    state.global_media_root.mkdir(parents=True, exist_ok=True)

    for media_asset in sorted(snapshot.media_assets_by_id.values(), key=lambda asset: asset.id):
        materialize_global_media(state, media_root, media_asset)

    courses_exported, lessons_exported = export_courses(state, snapshot)
    verification = verify_output_structure(state, snapshot)

    after_counts, after_schema_column_counts = read_counts_readonly(database_url)
    if after_counts != snapshot.basis_counts:
        raise ProjectionV2Error(
            f"database relationship counts changed during export: before={snapshot.basis_counts}, after={after_counts}"
        )
    if after_schema_column_counts != snapshot.schema_column_counts:
        raise ProjectionV2Error(
            "database schema column counts changed during export: "
            f"before={snapshot.schema_column_counts}, after={after_schema_column_counts}"
        )

    return {
        "projection_schema": PROJECTION_SCHEMA,
        "source_database": database_name,
        "export_root": str(export_root),
        "courses_root": str(state.courses_root),
        "global_media_root": str(state.global_media_root),
        "database_relationship_basis": snapshot.basis_counts,
        "database_schema_column_counts": snapshot.schema_column_counts,
        "courses_exported": courses_exported,
        "lessons_exported": lessons_exported,
        "content_files_written": state.content_files_written,
        "content_files_verified_existing": state.content_files_verified_existing,
        "course_manifests_written": state.course_manifests_written,
        "course_manifests_verified_existing": state.course_manifests_verified_existing,
        "global_media_files_written": state.global_media_files_written,
        "global_media_files_verified_existing": state.global_media_files_verified_existing,
        "referenced_media_assets": len(snapshot.media_assets_by_id),
        "total_manifest_media_references": state.manifest_media_references,
        "duplicate_target_path_conflicts": state.duplicate_target_path_conflicts,
        "verification": verification,
        "errors": 0,
    }


def main() -> int:
    args = parse_args()
    export_root = resolve_root(args.export_root, must_exist=False)
    media_root = resolve_root(args.media_root, must_exist=True)
    result = export_projection_v2(
        database_url=args.database_url,
        export_root=export_root,
        media_root=media_root,
        allow_existing=bool(args.allow_existing),
    )
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
