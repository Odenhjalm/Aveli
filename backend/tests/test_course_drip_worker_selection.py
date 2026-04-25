from __future__ import annotations

import json
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

from app import db
from app.services import course_drip_worker


pytestmark = pytest.mark.anyio("asyncio")


BACKEND_DIR = Path(__file__).resolve().parents[1]
ROOT_DIR = BACKEND_DIR.parent
BASELINE_V2_LOCK_PATH = BACKEND_DIR / "supabase" / "baseline_v2_slots.lock.json"


def _baseline_v2_slot_paths() -> list[Path]:
    lock = json.loads(BASELINE_V2_LOCK_PATH.read_text(encoding="utf-8"))
    return [ROOT_DIR / entry["path"] for entry in lock["slots"]]


def _admin_conninfo() -> str:
    if not os.getenv("DATABASE_URL"):
        pytest.skip("DATABASE_URL is required for isolated Baseline V2 worker tests")
    conninfo = conninfo_to_dict(os.environ["DATABASE_URL"])
    conninfo["dbname"] = "postgres"
    return make_conninfo(**conninfo)


def _db_conninfo(db_name: str) -> str:
    conninfo = conninfo_to_dict(os.environ["DATABASE_URL"])
    conninfo["dbname"] = db_name
    return make_conninfo(**conninfo)


@contextmanager
def _baseline_v2_connection():
    db_name = f"aveli_course_drip_worker_{uuid4().hex[:12]}"
    admin_conninfo = _admin_conninfo()
    database_conninfo = _db_conninfo(db_name)

    with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
        admin_conn.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(db_name)))

    try:
        with psycopg.connect(database_conninfo, autocommit=True) as conn:
            yield conn, database_conninfo
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


def _apply_baseline_v2_slots(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        for path in _baseline_v2_slot_paths():
            cur.execute(path.read_text(encoding="utf-8"))


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
    required_enrollment_source: str,
    drip_enabled: bool,
    drip_interval_days: int | None,
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
              required_enrollment_source,
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
              0,
              %s,
              'public',
              true,
              NULL,
              NULL,
              NULL,
              false,
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
                required_enrollment_source,
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


def _lesson_rows(conn: psycopg.Connection, course_id: str) -> list[dict[str, object]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT id, position
            FROM app.lessons
            WHERE course_id = %s
            ORDER BY position, id
            """,
            (course_id,),
        )
        return [dict(row) for row in cur.fetchall()]


def _configure_custom_drip(
    conn: psycopg.Connection,
    *,
    course_id: str,
    offsets_by_position: dict[int, int],
) -> None:
    lessons = _lesson_rows(conn, course_id)
    lesson_positions = {int(lesson["position"]) for lesson in lessons}
    assert lesson_positions == set(offsets_by_position)

    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE app.courses
                   SET drip_enabled = false,
                       drip_interval_days = NULL
                 WHERE id = %s
                """,
                (course_id,),
            )
            cur.execute(
                """
                INSERT INTO app.course_custom_drip_configs (course_id)
                VALUES (%s)
                """,
                (course_id,),
            )
            for lesson in lessons:
                cur.execute(
                    """
                    INSERT INTO app.course_custom_drip_lesson_offsets (
                      course_id,
                      lesson_id,
                      unlock_offset_days
                    )
                    VALUES (%s, %s, %s)
                    """,
                    (
                        course_id,
                        str(lesson["id"]),
                        offsets_by_position[int(lesson["position"])],
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
    _insert_auth_subject(conn, user_id, role="learner")
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT ce.*
            FROM app.canonical_create_course_enrollment(%s, %s, %s, %s, %s) AS ce
            """,
            (enrollment_id, user_id, course_id, source, granted_at),
        )
        row = cur.fetchone()
    assert row is not None
    return dict(row)


def _read_current_unlock_position(conn: psycopg.Connection, enrollment_id: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT current_unlock_position
            FROM app.course_enrollments
            WHERE id = %s
            """,
            (enrollment_id,),
        )
        row = cur.fetchone()
    assert row is not None
    return int(row[0])


async def _run_course_drip_worker_once(database_conninfo: str, *, now: datetime) -> int:
    original_pool = course_drip_worker.pool
    worker_pool = db.ContextAwareAsyncConnectionPool(
        conninfo=database_conninfo,
        min_size=1,
        max_size=1,
        check=db.ContextAwareAsyncConnectionPool.check_connection,
        open=False,
    )
    course_drip_worker.pool = worker_pool
    try:
        await worker_pool.open(wait=True)
        return await course_drip_worker.run_once(now=now)
    finally:
        course_drip_worker.pool = original_pool
        if not worker_pool.closed:
            await worker_pool.close()


async def test_run_once_advances_legacy_uniform_drip_candidate():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="worker-legacy-uniform",
            required_enrollment_source="purchase",
            drip_enabled=True,
            drip_interval_days=2,
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

        advanced_enrollments = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=10),
        )

        assert advanced_enrollments == 1
        assert _read_current_unlock_position(conn, str(enrollment["id"])) == 3


async def test_run_once_advances_custom_lesson_offsets_candidate():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="worker-custom-offsets",
            required_enrollment_source="purchase",
            drip_enabled=False,
            drip_interval_days=None,
        )
        _insert_lessons(conn, course_id, count=4)
        _configure_custom_drip(
            conn,
            course_id=course_id,
            offsets_by_position={1: 0, 2: 2, 3: 7, 4: 14},
        )
        enrollment = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=course_id,
            source="purchase",
            granted_at=granted_at,
        )
        assert enrollment["current_unlock_position"] == 1

        advanced_enrollments = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=10),
        )

        assert advanced_enrollments == 1
        assert _read_current_unlock_position(conn, str(enrollment["id"])) == 3


async def test_run_once_does_not_create_false_advancement_for_no_drip_course():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="worker-no-drip",
            required_enrollment_source="purchase",
            drip_enabled=False,
            drip_interval_days=None,
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
        assert enrollment["current_unlock_position"] == 3

        advanced_enrollments = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=10),
        )

        assert advanced_enrollments == 0
        assert _read_current_unlock_position(conn, str(enrollment["id"])) == 3


def test_run_once_uses_mode_aware_candidate_query_and_canonical_worker_call():
    source = Path(course_drip_worker.__file__).read_text(encoding="utf-8")
    normalized = " ".join(source.lower().split())

    assert "resolve_course_drip_mode" in source
    assert "canonical_worker_advance_course_enrollment_drip(%s, %s)" in normalized
    assert "where c.drip_enabled = true" not in normalized

    for marker in (
        "drip_interval_days * 86400",
        "unlock_offset_days",
        "floor(",
        "extract(epoch",
    ):
        assert marker not in normalized
