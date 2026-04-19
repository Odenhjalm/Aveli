#!/usr/bin/env python3
"""Transactional preserve_ids importer for Baseline V2 Projection V2 exports."""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

try:
    import psycopg
    from psycopg.rows import dict_row
except Exception as exc:  # pragma: no cover - surfaced in direct script usage
    raise SystemExit("psycopg is required for Projection V2 import") from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from backend.scripts.preflight_import_baseline_v2_projection_v2 import (  # noqa: E402
    PROJECTION_SCHEMA_V2,
    build_global_media_index,
    read_json,
    resolve_export_root,
    verify_global_media_files,
)


DEFAULT_EXPORT_ROOT = REPO_ROOT / "canonical_projection_export_v2"
DEFAULT_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/aveli_projection_v2_clean_target"
TARGET_DATABASE_NAME = "aveli_projection_v2_clean_target"
IMPORT_TABLES = ("courses", "lessons", "lesson_contents", "media_assets", "lesson_media")
EXPECTED_COUNTS = {
    "courses": 33,
    "lessons": 444,
    "lesson_contents": 444,
    "media_assets": 680,
    "lesson_media": 2466,
}


class ProjectionV2ImportError(RuntimeError):
    pass


@dataclass(frozen=True)
class CourseRow:
    id: str
    teacher_id: str
    title: str
    slug: str
    course_group_id: str
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
    created_at: str
    updated_at: str


@dataclass(frozen=True)
class LessonRow:
    id: str
    course_id: str
    title: str
    position: int
    created_at: str
    updated_at: str
    content_markdown: str


@dataclass(frozen=True)
class MediaAssetRow:
    id: str
    media_type: str
    purpose: str
    original_object_path: str
    ingest_format: str
    file_size: int
    content_hash_algorithm: str
    content_hash: str


@dataclass(frozen=True)
class LessonMediaRow:
    id: str
    lesson_id: str
    media_asset_id: str
    position: int
    purpose: str


@dataclass(frozen=True)
class ProjectionRows:
    courses: list[CourseRow]
    lessons: list[LessonRow]
    media_assets: list[MediaAssetRow]
    lesson_media: list[LessonMediaRow]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import Projection V2 course data into a clean Baseline V2 target DB."
    )
    parser.add_argument(
        "--export-root",
        default=str(DEFAULT_EXPORT_ROOT),
        help="Projection V2 root containing courses/ and media/.",
    )
    parser.add_argument(
        "--database-url",
        default=os.environ.get("DATABASE_URL") or DEFAULT_DATABASE_URL,
        help="Target PostgreSQL URL. Must be local aveli_projection_v2_clean_target.",
    )
    parser.add_argument(
        "--mode",
        default="preserve_ids",
        choices=("preserve_ids",),
        help="Only preserve_ids is supported.",
    )
    return parser.parse_args()


def require_target_database(database_url: str) -> None:
    parsed = urlsplit(database_url)
    if parsed.scheme not in {"postgresql", "postgres"}:
        raise ProjectionV2ImportError(f"database URL must be PostgreSQL, got {parsed.scheme!r}")
    if parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise ProjectionV2ImportError(f"refusing non-local target DB host {parsed.hostname!r}")
    database = parsed.path.lstrip("/")
    if database != TARGET_DATABASE_NAME:
        raise ProjectionV2ImportError(
            f"refusing unexpected target database {database!r}; expected {TARGET_DATABASE_NAME!r}"
        )


def import_table_counts(conn: psycopg.Connection) -> dict[str, int]:
    counts: dict[str, int] = {}
    with conn.cursor(row_factory=dict_row) as cur:
        for table in IMPORT_TABLES:
            cur.execute(f"select count(*) as count from app.{table}")
            counts[table] = int(cur.fetchone()["count"])
    return counts


def assert_import_tables_empty(conn: psycopg.Connection) -> dict[str, int]:
    counts = import_table_counts(conn)
    non_empty = {table: count for table, count in counts.items() if count != 0}
    if non_empty:
        raise ProjectionV2ImportError(f"target import tables are not empty: {non_empty}")
    return counts


def assert_no_schema_drift(conn: psycopg.Connection) -> dict[str, int]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select table_name, count(*)::int as column_count
              from information_schema.columns
             where table_schema = 'app'
               and table_name = any(%s)
             group by table_name
             order by table_name
            """,
            (list(IMPORT_TABLES),),
        )
        column_counts = {str(row["table_name"]): int(row["column_count"]) for row in cur.fetchall()}
        cur.execute(
            """
            select count(*)::int as invalid_constraints
              from pg_constraint con
              join pg_namespace n on n.oid = con.connamespace
             where n.nspname in ('app', 'auth', 'storage')
               and con.convalidated = false
            """
        )
        invalid_constraints = int(cur.fetchone()["invalid_constraints"])
    if invalid_constraints:
        raise ProjectionV2ImportError(f"invalid constraints present before import: {invalid_constraints}")
    expected_column_counts = {
        "courses": 17,
        "lessons": 6,
        "lesson_contents": 4,
        "media_assets": 19,
        "lesson_media": 4,
    }
    if column_counts != expected_column_counts:
        raise ProjectionV2ImportError(
            f"target schema column counts mismatch: expected {expected_column_counts}, got {column_counts}"
        )
    return column_counts


def require_string(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or not value:
        raise ProjectionV2ImportError(f"{field_name} must be a non-empty string")
    return value


def require_int(value: Any, field_name: str) -> int:
    if not isinstance(value, int):
        raise ProjectionV2ImportError(f"{field_name} must be an integer")
    return value


def require_bool(value: Any, field_name: str) -> bool:
    if not isinstance(value, bool):
        raise ProjectionV2ImportError(f"{field_name} must be a boolean")
    return value


def load_projection_rows(export_root: Path) -> ProjectionRows:
    courses: list[CourseRow] = []
    lessons: list[LessonRow] = []
    media_assets_by_id: dict[str, MediaAssetRow] = {}
    lesson_media: list[LessonMediaRow] = []

    manifest_paths = sorted((export_root / "courses").glob("*/course.json"), key=lambda path: path.as_posix())
    for manifest_path in manifest_paths:
        manifest = read_json(manifest_path)
        if manifest.get("schema") != PROJECTION_SCHEMA_V2:
            raise ProjectionV2ImportError(f"manifest schema is not Projection V2: {manifest_path}")
        course = manifest.get("course")
        if not isinstance(course, dict):
            raise ProjectionV2ImportError(f"course payload missing in {manifest_path}")
        course_row = CourseRow(
            id=require_string(course.get("id"), "course.id"),
            teacher_id=require_string(course.get("teacher_id"), "course.teacher_id"),
            title=require_string(course.get("title"), "course.title"),
            slug=require_string(course.get("slug"), "course.slug"),
            course_group_id=require_string(course.get("course_group_id"), "course.course_group_id"),
            group_position=require_int(course.get("group_position"), "course.group_position"),
            visibility=require_string(course.get("visibility"), "course.visibility"),
            content_ready=require_bool(course.get("content_ready"), "course.content_ready"),
            price_amount_cents=course.get("price_amount_cents"),
            stripe_product_id=course.get("stripe_product_id"),
            active_stripe_price_id=course.get("active_stripe_price_id"),
            sellable=require_bool(course.get("sellable"), "course.sellable"),
            drip_enabled=require_bool(course.get("drip_enabled"), "course.drip_enabled"),
            drip_interval_days=course.get("drip_interval_days"),
            cover_media_id=course.get("cover_media_id"),
            created_at=require_string(course.get("created_at"), "course.created_at"),
            updated_at=require_string(course.get("updated_at"), "course.updated_at"),
        )
        courses.append(course_row)

        if course_row.cover_media_id is not None:
            raise ProjectionV2ImportError(
                "non-null cover_media_id cannot be imported with strict course-before-media order"
            )

        raw_lessons = manifest.get("lessons")
        if not isinstance(raw_lessons, list):
            raise ProjectionV2ImportError(f"lessons must be a list in {manifest_path}")
        for raw_lesson in raw_lessons:
            if not isinstance(raw_lesson, dict):
                raise ProjectionV2ImportError(f"lesson must be an object in {manifest_path}")
            lesson_id = require_string(raw_lesson.get("id"), "lesson.id")
            content_file = require_string(raw_lesson.get("content_file"), "lesson.content_file")
            content_path = manifest_path.parent / Path(*content_file.split("/"))
            if not content_path.is_file():
                raise ProjectionV2ImportError(f"content.md missing for lesson {lesson_id}: {content_path}")
            lessons.append(
                LessonRow(
                    id=lesson_id,
                    course_id=course_row.id,
                    title=require_string(raw_lesson.get("title"), "lesson.title"),
                    position=require_int(raw_lesson.get("position"), "lesson.position"),
                    created_at=require_string(raw_lesson.get("created_at"), "lesson.created_at"),
                    updated_at=require_string(raw_lesson.get("updated_at"), "lesson.updated_at"),
                    content_markdown=content_path.read_text(encoding="utf-8"),
                )
            )

            raw_media = raw_lesson.get("media")
            if not isinstance(raw_media, list):
                raise ProjectionV2ImportError(f"lesson.media must be a list in {manifest_path}")
            for media in raw_media:
                if not isinstance(media, dict):
                    raise ProjectionV2ImportError(f"media entry must be an object in {manifest_path}")
                media_asset_id = require_string(media.get("media_asset_id"), "media_asset_id")
                purpose = require_string(media.get("purpose"), "purpose")
                media_row = MediaAssetRow(
                    id=media_asset_id,
                    media_type=require_string(media.get("media_type"), "media_type"),
                    purpose=purpose,
                    original_object_path=require_string(media.get("original_object_path"), "original_object_path"),
                    ingest_format=require_string(media.get("ingest_format"), "ingest_format"),
                    file_size=require_int(media.get("file_size"), "file_size"),
                    content_hash_algorithm=require_string(
                        media.get("content_hash_algorithm"), "content_hash_algorithm"
                    ),
                    content_hash=require_string(media.get("content_hash"), "content_hash"),
                )
                existing_media = media_assets_by_id.get(media_asset_id)
                if existing_media is None:
                    media_assets_by_id[media_asset_id] = media_row
                elif existing_media != media_row:
                    raise ProjectionV2ImportError(f"media_asset_id has conflicting manifest fields: {media_asset_id}")
                lesson_media.append(
                    LessonMediaRow(
                        id=require_string(media.get("lesson_media_id"), "lesson_media_id"),
                        lesson_id=lesson_id,
                        media_asset_id=media_asset_id,
                        position=require_int(media.get("position"), "media.position"),
                        purpose=purpose,
                    )
                )

    return ProjectionRows(
        courses=sorted(courses, key=lambda row: (row.group_position, row.id)),
        lessons=sorted(lessons, key=lambda row: (row.course_id, row.position, row.id)),
        media_assets=sorted(media_assets_by_id.values(), key=lambda row: row.id),
        lesson_media=sorted(lesson_media, key=lambda row: (row.lesson_id, row.position, row.id)),
    )


def assert_projection_expected_counts(rows: ProjectionRows) -> dict[str, int]:
    counts = {
        "courses": len(rows.courses),
        "lessons": len(rows.lessons),
        "lesson_contents": len(rows.lessons),
        "media_assets": len(rows.media_assets),
        "lesson_media": len(rows.lesson_media),
    }
    if counts != EXPECTED_COUNTS:
        raise ProjectionV2ImportError(f"projection count mismatch: expected {EXPECTED_COUNTS}, got {counts}")
    return counts


def assert_preserve_id_prerequisites(conn: psycopg.Connection, rows: ProjectionRows) -> None:
    teacher_ids = sorted({course.teacher_id for course in rows.courses})
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select user_id::text
              from app.auth_subjects
             where user_id = any(%s::uuid[])
             order by user_id::text
            """,
            (teacher_ids,),
        )
        existing_teacher_ids = [str(row["user_id"]) for row in cur.fetchall()]
    missing_teacher_ids = sorted(set(teacher_ids) - set(existing_teacher_ids))
    if missing_teacher_ids:
        raise ProjectionV2ImportError(
            "preserve_ids import requires existing app.auth_subjects rows for course.teacher_id; "
            f"missing {len(missing_teacher_ids)} teacher subject(s): {missing_teacher_ids}"
        )


def insert_courses(cur: psycopg.Cursor, rows: list[CourseRow]) -> None:
    for row in rows:
        cur.execute(
            """
            insert into app.courses (
              id,
              teacher_id,
              title,
              slug,
              course_group_id,
              group_position,
              visibility,
              content_ready,
              price_amount_cents,
              stripe_product_id,
              active_stripe_price_id,
              sellable,
              drip_enabled,
              drip_interval_days,
              cover_media_id,
              created_at,
              updated_at
            )
            values (
              %s::uuid,
              %s::uuid,
              %s,
              %s,
              %s::uuid,
              %s,
              %s::app.course_visibility,
              %s,
              %s,
              %s,
              %s,
              %s,
              %s,
              %s,
              %s::uuid,
              %s::timestamptz,
              %s::timestamptz
            )
            """,
            (
                row.id,
                row.teacher_id,
                row.title,
                row.slug,
                row.course_group_id,
                row.group_position,
                row.visibility,
                row.content_ready,
                row.price_amount_cents,
                row.stripe_product_id,
                row.active_stripe_price_id,
                row.sellable,
                row.drip_enabled,
                row.drip_interval_days,
                row.cover_media_id,
                row.created_at,
                row.updated_at,
            ),
        )


def insert_lessons(cur: psycopg.Cursor, rows: list[LessonRow]) -> None:
    for row in rows:
        cur.execute(
            """
            insert into app.lessons (
              id, course_id, lesson_title, position, created_at, updated_at
            )
            values (%s::uuid, %s::uuid, %s, %s, %s::timestamptz, %s::timestamptz)
            """,
            (row.id, row.course_id, row.title, row.position, row.created_at, row.updated_at),
        )


def insert_lesson_contents(cur: psycopg.Cursor, rows: list[LessonRow]) -> None:
    for row in rows:
        cur.execute(
            """
            insert into app.lesson_contents (lesson_id, content_markdown)
            values (%s::uuid, %s)
            """,
            (row.id, row.content_markdown),
        )


def insert_media_assets(cur: psycopg.Cursor, rows: list[MediaAssetRow]) -> None:
    for row in rows:
        cur.execute(
            """
            insert into app.media_assets (
              id,
              media_type,
              purpose,
              original_object_path,
              ingest_format,
              file_size,
              content_hash_algorithm,
              content_hash
            )
            values (
              %s::uuid,
              %s::app.media_type,
              %s::app.media_purpose,
              %s,
              %s,
              %s,
              %s,
              %s
            )
            """,
            (
                row.id,
                row.media_type,
                row.purpose,
                row.original_object_path,
                row.ingest_format,
                row.file_size,
                row.content_hash_algorithm,
                row.content_hash,
            ),
        )


def insert_lesson_media(cur: psycopg.Cursor, rows: list[LessonMediaRow]) -> None:
    for row in rows:
        if row.purpose != "lesson_media":
            raise ProjectionV2ImportError(
                f"lesson_media placement {row.id} references media purpose {row.purpose!r}"
            )
        cur.execute(
            """
            insert into app.lesson_media (id, lesson_id, media_asset_id, position)
            values (%s::uuid, %s::uuid, %s::uuid, %s)
            """,
            (row.id, row.lesson_id, row.media_asset_id, row.position),
        )


def post_import_checks(conn: psycopg.Connection, rows: ProjectionRows) -> dict[str, Any]:
    counts = import_table_counts(conn)
    if counts != EXPECTED_COUNTS:
        raise ProjectionV2ImportError(f"post-import counts mismatch: expected {EXPECTED_COUNTS}, got {counts}")

    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select count(*)::int as count
              from app.lessons l
              left join app.courses c on c.id = l.course_id
             where c.id is null
            """
        )
        orphan_lessons = int(cur.fetchone()["count"])

        cur.execute(
            """
            select count(*)::int as count
              from app.lesson_contents lc
              left join app.lessons l on l.id = lc.lesson_id
             where l.id is null
            """
        )
        orphan_contents = int(cur.fetchone()["count"])

        cur.execute(
            """
            select count(*)::int as count
              from app.lesson_media lm
              left join app.lessons l on l.id = lm.lesson_id
              left join app.media_assets ma on ma.id = lm.media_asset_id
             where l.id is null or ma.id is null
            """
        )
        orphan_placements = int(cur.fetchone()["count"])

        cur.execute(
            """
            select count(*)::int as count
              from app.media_assets ma
             where ma.file_size is null
                or ma.content_hash_algorithm <> 'sha256'
                or ma.content_hash is null
                or ma.content_hash !~ '^[0-9a-f]{64}$'
                or ma.content_identity_error is not null
            """
        )
        invalid_identity_rows = int(cur.fetchone()["count"])

        cur.execute(
            """
            select count(*)::int as count
              from app.lesson_media lm
              join app.media_assets ma on ma.id = lm.media_asset_id
             where ma.purpose <> 'lesson_media'::app.media_purpose
            """
        )
        wrong_purpose_placements = int(cur.fetchone()["count"])

        cur.execute(
            """
            select ma.id::text,
                   ma.file_size,
                   ma.content_hash_algorithm,
                   ma.content_hash
              from app.media_assets ma
             order by ma.id::text
            """
        )
        db_identity = {
            row["id"]: (
                int(row["file_size"]),
                str(row["content_hash_algorithm"]),
                str(row["content_hash"]),
            )
            for row in cur.fetchall()
        }

        cur.execute(
            """
            select lm.id::text, lm.lesson_id::text, lm.media_asset_id::text, lm.position
              from app.lesson_media lm
             order by lm.lesson_id::text, lm.position, lm.id::text
            """
        )
        db_lesson_media = [
            (row["id"], row["lesson_id"], row["media_asset_id"], int(row["position"]))
            for row in cur.fetchall()
        ]

    manifest_identity = {
        row.id: (row.file_size, row.content_hash_algorithm, row.content_hash)
        for row in rows.media_assets
    }
    if db_identity != manifest_identity:
        raise ProjectionV2ImportError("media identity fields do not match manifest after import")

    manifest_lesson_media = [
        (row.id, row.lesson_id, row.media_asset_id, row.position)
        for row in sorted(rows.lesson_media, key=lambda item: (item.lesson_id, item.position, item.id))
    ]
    if db_lesson_media != manifest_lesson_media:
        raise ProjectionV2ImportError("lesson_media ordering or references do not match manifest after import")

    checks = {
        "orphan_lessons": orphan_lessons,
        "orphan_lesson_contents": orphan_contents,
        "orphan_lesson_media": orphan_placements,
        "invalid_identity_rows": invalid_identity_rows,
        "wrong_purpose_placements": wrong_purpose_placements,
    }
    failures = {name: value for name, value in checks.items() if value != 0}
    if failures:
        raise ProjectionV2ImportError(f"post-import relationship checks failed: {failures}")
    return {"counts": counts, **checks}


def import_projection_v2(export_root: Path, database_url: str) -> dict[str, Any]:
    require_target_database(database_url)
    export_root = resolve_export_root(str(export_root))

    course_count, lesson_count, media_index = build_global_media_index(export_root)
    global_media_files = verify_global_media_files(export_root, media_index)
    rows = load_projection_rows(export_root)
    projection_counts = assert_projection_expected_counts(rows)
    if course_count != projection_counts["courses"] or lesson_count != projection_counts["lessons"]:
        raise ProjectionV2ImportError("projection manifest counts diverge from preflight counts")
    if len(media_index) != projection_counts["media_assets"]:
        raise ProjectionV2ImportError("global media index count diverges from manifest rows")
    if sum(len(entry.placements) for entry in media_index.values()) != projection_counts["lesson_media"]:
        raise ProjectionV2ImportError("global media placement count diverges from manifest rows")
    if global_media_files != projection_counts["media_assets"]:
        raise ProjectionV2ImportError("global media file count diverges from manifest rows")

    with psycopg.connect(database_url, connect_timeout=5) as conn:
        before_schema = assert_no_schema_drift(conn)
        before_counts = assert_import_tables_empty(conn)
        assert_preserve_id_prerequisites(conn, rows)

        try:
            with conn.transaction():
                with conn.cursor() as cur:
                    insert_courses(cur, rows.courses)
                    insert_lessons(cur, rows.lessons)
                    insert_lesson_contents(cur, rows.lessons)
                    insert_media_assets(cur, rows.media_assets)
                    insert_lesson_media(cur, rows.lesson_media)
                post_checks = post_import_checks(conn, rows)
        except Exception:
            conn.rollback()
            raise

        after_schema = assert_no_schema_drift(conn)
        if after_schema != before_schema:
            raise ProjectionV2ImportError(f"schema changed during import: before={before_schema}, after={after_schema}")

    return {
        "status": "PASS",
        "mode": "preserve_ids",
        "target_database": TARGET_DATABASE_NAME,
        "projection_schema": PROJECTION_SCHEMA_V2,
        "before_counts": before_counts,
        "projection_counts": projection_counts,
        "inserted": post_checks["counts"],
        "post_checks": post_checks,
        "global_media_files_verified": global_media_files,
        "transaction": "committed_after_full_success",
    }


def main() -> int:
    args = parse_args()
    try:
        result = import_projection_v2(Path(args.export_root), args.database_url)
    except ProjectionV2ImportError as exc:
        print(
            json.dumps(
                {
                    "status": "BLOCKED",
                    "mode": args.mode,
                    "target_database": TARGET_DATABASE_NAME,
                    "error": str(exc),
                    "transaction": "not_started_or_rolled_back",
                },
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
        )
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
