from __future__ import annotations

import os
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import psycopg
import pytest
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.rows import dict_row


pytestmark = pytest.mark.anyio("asyncio")


ROOT_DIR = Path(__file__).resolve().parents[1]
BASELINE_V2_SLOTS_DIR = ROOT_DIR / "supabase" / "baseline_v2_slots"
BASELINE_V2_SLOT_FILES = [
    "V2_0001_foundation_enums.sql",
    "V2_0002_auth_subjects.sql",
    "V2_0003_media_assets.sql",
    "V2_0004_courses_and_public_content.sql",
    "V2_0005_lessons_content_and_access.sql",
    "V2_0013_workers.sql",
]


def _admin_conninfo() -> str:
    if not os.getenv("DATABASE_URL"):
        pytest.skip("DATABASE_URL is required for isolated Baseline V2 contract tests")
    conninfo = conninfo_to_dict(os.environ["DATABASE_URL"])
    conninfo["dbname"] = "postgres"
    return make_conninfo(**conninfo)


def _db_conninfo(db_name: str) -> str:
    conninfo = conninfo_to_dict(os.environ["DATABASE_URL"])
    conninfo["dbname"] = db_name
    return make_conninfo(**conninfo)


@contextmanager
def _baseline_v2_connection():
    db_name = f"aveli_baseline_v2_{uuid4().hex[:12]}"
    admin_conninfo = _admin_conninfo()
    database_conninfo = _db_conninfo(db_name)

    with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
        admin_conn.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(db_name)))

    try:
        with psycopg.connect(database_conninfo, autocommit=True) as conn:
            yield conn
    finally:
        with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
            admin_conn.execute(
                """
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = %s
                  AND pid <> pg_backend_pid()
                """,
                (db_name,),
            )
            admin_conn.execute(sql.SQL("DROP DATABASE IF EXISTS {}").format(sql.Identifier(db_name)))


def _apply_baseline_v2_slots(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        for filename in BASELINE_V2_SLOT_FILES:
            cur.execute((BASELINE_V2_SLOTS_DIR / filename).read_text(encoding="utf-8"))


def _insert_auth_subject(conn: psycopg.Connection, user_id: str, *, role: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO app.auth_subjects (user_id, email, onboarding_state, role)
            VALUES (%s, %s, 'completed', %s)
            ON CONFLICT (user_id) DO NOTHING
            """,
            (user_id, f"{user_id}@example.test", role),
        )


def _insert_course(
    conn: psycopg.Connection,
    *,
    course_id: str,
    slug: str,
    group_position: int,
    drip_enabled: bool,
    drip_interval_days: int | None,
    sellable: bool,
) -> None:
    teacher_id = str(uuid4())
    _insert_auth_subject(conn, teacher_id, role="teacher")
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO app.courses (
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
              cover_media_id
            )
            VALUES (
              %s,
              %s,
              %s,
              %s,
              %s,
              %s,
              'public',
              true,
              %s,
              %s,
              %s,
              %s,
              %s,
              %s,
              NULL
            )
            """,
            (
                course_id,
                teacher_id,
                f"title-{slug}",
                slug,
                str(uuid4()),
                group_position,
                1000 if sellable else None,
                f"prod_{course_id}" if sellable else None,
                f"price_{course_id}" if sellable else None,
                sellable,
                drip_enabled,
                drip_interval_days,
            ),
        )


def _insert_lessons(conn: psycopg.Connection, course_id: str, count: int) -> None:
    with conn.cursor() as cur:
        for position in range(1, count + 1):
            cur.execute(
                """
                INSERT INTO app.lessons (id, course_id, lesson_title, position)
                VALUES (%s, %s, %s, %s)
                """,
                (str(uuid4()), course_id, f"lesson-{position}", position),
            )


def _create_enrollment(
    conn: psycopg.Connection,
    *,
    enrollment_id: str,
    user_id: str,
    course_id: str,
    source: str,
    granted_at: datetime,
) -> dict[str, object]:
    _insert_auth_subject(conn, user_id, role="learner")
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT (app.canonical_create_course_enrollment(%s, %s, %s, %s, %s)).*
            """,
            (enrollment_id, user_id, course_id, source, granted_at),
        )
        row = cur.fetchone()
    assert row is not None
    return dict(row)


def _advance_enrollment(
    conn: psycopg.Connection,
    *,
    enrollment_id: str,
    evaluated_at: datetime,
) -> dict[str, object]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT *
            FROM app.canonical_worker_advance_course_enrollment_drip(%s, %s)
            """,
            (enrollment_id, evaluated_at),
        )
        row = cur.fetchone()
    assert row is not None
    return dict(row)


async def test_enrollment_initialization_uses_group_position_and_sellable_authority():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        intro_course_id = str(uuid4())
        paid_course_id = str(uuid4())

        _insert_course(
            conn,
            course_id=intro_course_id,
            slug="intro-drip",
            group_position=0,
            drip_enabled=True,
            drip_interval_days=7,
            sellable=False,
        )
        _insert_lessons(conn, intro_course_id, count=3)

        _insert_course(
            conn,
            course_id=paid_course_id,
            slug="paid-full-unlock",
            group_position=1,
            drip_enabled=False,
            drip_interval_days=None,
            sellable=True,
        )
        _insert_lessons(conn, paid_course_id, count=4)

        intro = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=intro_course_id,
            source="intro_enrollment",
            granted_at=granted_at,
        )
        paid = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=paid_course_id,
            source="purchase",
            granted_at=granted_at,
        )

        assert intro["current_unlock_position"] == 1
        assert paid["current_unlock_position"] == 4


async def test_enrollment_creation_enforces_canonical_boundary_and_source_alignment():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
        _insert_auth_subject(conn, user_id, role="learner")
        _insert_course(
            conn,
            course_id=course_id,
            slug="intro-source-check",
            group_position=0,
            drip_enabled=True,
            drip_interval_days=7,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=1)

        with pytest.raises(
            psycopg.Error,
            match="course_enrollments rows may be inserted only through the canonical enrollment function",
        ):
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO app.course_enrollments (
                      id,
                      user_id,
                      course_id,
                      source,
                      granted_at,
                      drip_started_at,
                      current_unlock_position
                    )
                    VALUES (%s, %s, %s, 'intro_enrollment', %s, %s, 1)
                    """,
                    (str(uuid4()), user_id, course_id, granted_at, granted_at),
                )

        with pytest.raises(
            psycopg.Error,
            match="non-sellable courses require source = intro_enrollment",
        ):
            _create_enrollment(
                conn,
                enrollment_id=str(uuid4()),
                user_id=user_id,
                course_id=course_id,
                source="purchase",
                granted_at=granted_at,
            )


async def test_worker_advances_existing_drip_enrollment_only():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
        _insert_course(
            conn,
            course_id=course_id,
            slug="paid-drip-course",
            group_position=1,
            drip_enabled=True,
            drip_interval_days=2,
            sellable=True,
        )
        _insert_lessons(conn, course_id, count=3)

        enrollment = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=course_id,
            source="purchase",
            granted_at=granted_at,
        )
        assert enrollment["current_unlock_position"] == 1

        advanced = _advance_enrollment(
            conn,
            enrollment_id=str(enrollment["id"]),
            evaluated_at=granted_at + timedelta(days=10),
        )

        assert advanced["id"] == enrollment["id"]
        assert advanced["current_unlock_position"] == 3
