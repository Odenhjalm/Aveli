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
NEWBASELINE_SLOTS_DIR = ROOT_DIR / "supabase" / "newbaseline_slots"
NEWBASELINE_SLOT_FILES = [
    "canonical_foundation.sql",
    "courses_core.sql",
    "lessons_core.sql",
    "lesson_contents_core.sql",
    "course_enrollments_core.sql",
    "media_assets_core.sql",
    "lesson_media_core.sql",
    "runtime_media_projection_core.sql",
    "runtime_media_projection_sync.sql",
    "canonical_access_policies.sql",
    "worker_query_support.sql",
]


def _admin_conninfo() -> str:
    conninfo = conninfo_to_dict(os.environ["DATABASE_URL"])
    conninfo["dbname"] = "postgres"
    return make_conninfo(**conninfo)


def _db_conninfo(db_name: str) -> str:
    conninfo = conninfo_to_dict(os.environ["DATABASE_URL"])
    conninfo["dbname"] = db_name
    return make_conninfo(**conninfo)


@contextmanager
def _newbaseline_connection():
    db_name = f"aveli_newbaseline_{uuid4().hex[:12]}"
    admin_conninfo = _admin_conninfo()
    database_conninfo = _db_conninfo(db_name)

    with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
        admin_conn.execute(
            sql.SQL("CREATE DATABASE {}").format(sql.Identifier(db_name))
        )

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
            admin_conn.execute(
                sql.SQL("DROP DATABASE IF EXISTS {}").format(sql.Identifier(db_name))
            )


def _apply_newbaseline_slots(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        for filename in NEWBASELINE_SLOT_FILES:
            cur.execute((NEWBASELINE_SLOTS_DIR / filename).read_text())


def _insert_course(
    conn: psycopg.Connection,
    *,
    course_id: str,
    slug: str,
    step: str,
    drip_enabled: bool,
    drip_interval_days: int | None,
    price_amount_cents: int | None,
) -> None:
    group_id = str(uuid4())
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO app.courses (
              id,
              title,
              slug,
              course_group_id,
              step,
              price_amount_cents,
              drip_enabled,
              drip_interval_days,
              cover_media_id
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NULL)
            """,
            (
                course_id,
                f"title-{slug}",
                slug,
                group_id,
                step,
                price_amount_cents,
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
                (
                    str(uuid4()),
                    course_id,
                    f"lesson-{position}",
                    position,
                ),
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
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT (app.canonical_create_course_enrollment(%s, %s, %s, %s, %s)).*
            """,
            (
                enrollment_id,
                user_id,
                course_id,
                source,
                granted_at,
            ),
        )
        row = cur.fetchone()
    assert row is not None
    return dict(row)


def _fetch_enrollment(conn: psycopg.Connection, enrollment_id: str) -> dict[str, object]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT *
            FROM app.course_enrollments
            WHERE id = %s
            """,
            (enrollment_id,),
        )
        row = cur.fetchone()
    assert row is not None
    return dict(row)


async def test_enrollment_initialization_follows_canonical_course_drip_rules():
    with _newbaseline_connection() as conn:
        _apply_newbaseline_slots(conn)

        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        intro_drip_course_id = str(uuid4())
        intro_zero_lessons_course_id = str(uuid4())
        paid_full_unlock_course_id = str(uuid4())
        paid_zero_lessons_course_id = str(uuid4())

        _insert_course(
            conn,
            course_id=intro_drip_course_id,
            slug="intro-drip",
            step="intro",
            drip_enabled=True,
            drip_interval_days=7,
            price_amount_cents=None,
        )
        _insert_lessons(conn, intro_drip_course_id, count=3)

        _insert_course(
            conn,
            course_id=intro_zero_lessons_course_id,
            slug="intro-zero-lessons",
            step="intro",
            drip_enabled=True,
            drip_interval_days=7,
            price_amount_cents=None,
        )

        _insert_course(
            conn,
            course_id=paid_full_unlock_course_id,
            slug="paid-full-unlock",
            step="step1",
            drip_enabled=False,
            drip_interval_days=None,
            price_amount_cents=1000,
        )
        _insert_lessons(conn, paid_full_unlock_course_id, count=4)

        _insert_course(
            conn,
            course_id=paid_zero_lessons_course_id,
            slug="paid-zero-lessons",
            step="step1",
            drip_enabled=False,
            drip_interval_days=None,
            price_amount_cents=1000,
        )

        intro_drip = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=intro_drip_course_id,
            source="intro_enrollment",
            granted_at=granted_at,
        )
        intro_zero = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=intro_zero_lessons_course_id,
            source="intro_enrollment",
            granted_at=granted_at,
        )
        paid_full_unlock = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=paid_full_unlock_course_id,
            source="purchase",
            granted_at=granted_at,
        )
        paid_zero = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=paid_zero_lessons_course_id,
            source="purchase",
            granted_at=granted_at,
        )

        assert intro_drip["drip_started_at"] == granted_at
        assert intro_drip["current_unlock_position"] == 1
        assert intro_zero["drip_started_at"] == granted_at
        assert intro_zero["current_unlock_position"] == 0
        assert paid_full_unlock["drip_started_at"] == granted_at
        assert paid_full_unlock["current_unlock_position"] == 4
        assert paid_zero["drip_started_at"] == granted_at
        assert paid_zero["current_unlock_position"] == 0

        repeated = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=paid_full_unlock_course_id,
            source="purchase",
            granted_at=granted_at + timedelta(days=30),
        )
        assert repeated["id"] == paid_full_unlock["id"]
        assert repeated["granted_at"] == paid_full_unlock["granted_at"]


async def test_enrollment_creation_requires_canonical_boundary_and_source_alignment():
    with _newbaseline_connection() as conn:
        _apply_newbaseline_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
        _insert_course(
            conn,
            course_id=course_id,
            slug="intro-source-check",
            step="intro",
            drip_enabled=True,
            drip_interval_days=7,
            price_amount_cents=None,
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
                    (
                        str(uuid4()),
                        user_id,
                        course_id,
                        granted_at,
                        granted_at,
                    ),
                )

        with pytest.raises(
            psycopg.Error,
            match="intro courses require source = intro_enrollment",
        ):
            _create_enrollment(
                conn,
                enrollment_id=str(uuid4()),
                user_id=user_id,
                course_id=course_id,
                source="purchase",
                granted_at=granted_at,
            )


async def test_worker_is_only_progression_authority_and_clamps_to_lesson_bounds():
    with _newbaseline_connection() as conn:
        _apply_newbaseline_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
        _insert_course(
            conn,
            course_id=course_id,
            slug="paid-drip-course",
            step="step1",
            drip_enabled=True,
            drip_interval_days=2,
            price_amount_cents=1000,
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
        enrollment_id = str(enrollment["id"])
        assert enrollment["current_unlock_position"] == 1

        with pytest.raises(
            psycopg.Error,
            match="current_unlock_position may be advanced only through the canonical drip worker function",
        ):
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE app.course_enrollments
                    SET current_unlock_position = 2
                    WHERE id = %s
                    """,
                    (enrollment_id,),
                )

        advance_at = granted_at + timedelta(days=10)
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT *
                FROM app.canonical_worker_advance_course_enrollment_drip(%s)
                """,
                (advance_at,),
            )
            rows = [dict(row) for row in cur.fetchall()]

        assert [row["id"] for row in rows] == [enrollment["id"]]
        assert rows[0]["current_unlock_position"] == 3
        assert _fetch_enrollment(conn, enrollment_id)["current_unlock_position"] == 3

        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT *
                FROM app.canonical_worker_advance_course_enrollment_drip(%s)
                """,
                (advance_at,),
            )
            repeated_rows = cur.fetchall()

        assert repeated_rows == []
        assert _fetch_enrollment(conn, enrollment_id)["current_unlock_position"] == 3


async def test_worker_does_not_advance_non_drip_courses_and_runtime_surfaces_use_stored_unlock_state():
    with _newbaseline_connection() as conn:
        _apply_newbaseline_slots(conn)

        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        non_drip_course_id = str(uuid4())
        _insert_course(
            conn,
            course_id=non_drip_course_id,
            slug="non-drip-course",
            step="step1",
            drip_enabled=False,
            drip_interval_days=None,
            price_amount_cents=1000,
        )
        _insert_lessons(conn, non_drip_course_id, count=2)
        non_drip_enrollment = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=non_drip_course_id,
            source="purchase",
            granted_at=granted_at,
        )

        zero_lesson_drip_course_id = str(uuid4())
        _insert_course(
            conn,
            course_id=zero_lesson_drip_course_id,
            slug="drip-zero-lessons",
            step="step1",
            drip_enabled=True,
            drip_interval_days=3,
            price_amount_cents=1000,
        )
        zero_lesson_enrollment = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=str(uuid4()),
            course_id=zero_lesson_drip_course_id,
            source="purchase",
            granted_at=granted_at,
        )

        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT *
                FROM app.canonical_worker_advance_course_enrollment_drip(%s)
                """,
                (granted_at + timedelta(days=60),),
            )
            rows = cur.fetchall()

        assert rows == []
        assert _fetch_enrollment(conn, str(non_drip_enrollment["id"]))[
            "current_unlock_position"
        ] == 2
        assert _fetch_enrollment(conn, str(zero_lesson_enrollment["id"]))[
            "current_unlock_position"
        ] == 0

        policies_sql = (NEWBASELINE_SLOTS_DIR / "canonical_access_policies.sql").read_text()
        runtime_projection_sql = (
            NEWBASELINE_SLOTS_DIR / "runtime_media_projection_core.sql"
        ).read_text()

        assert "l.position <= ce.current_unlock_position" in policies_sql
        assert "ce.source = 'intro_enrollment'" in policies_sql
        assert "ce.source = 'purchase'" in policies_sql
        assert "drip_started_at" not in policies_sql
        assert "drip_interval_days" not in policies_sql
        assert "floor(" not in policies_sql.lower()

        assert "current_unlock_position" not in runtime_projection_sql
        assert "drip_started_at" not in runtime_projection_sql
        assert "drip_interval_days" not in runtime_projection_sql
