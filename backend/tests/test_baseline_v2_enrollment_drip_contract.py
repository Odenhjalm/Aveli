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


pytestmark = pytest.mark.anyio("asyncio")


BACKEND_DIR = Path(__file__).resolve().parents[1]
ROOT_DIR = BACKEND_DIR.parent
BASELINE_V2_LOCK_PATH = BACKEND_DIR / "supabase" / "baseline_v2_slots.lock.json"


def _baseline_v2_slot_paths() -> list[Path]:
    lock = json.loads(BASELINE_V2_LOCK_PATH.read_text(encoding="utf-8"))
    return [ROOT_DIR / entry["path"] for entry in lock["slots"]]


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
    group_position: int,
    required_enrollment_source: str,
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
                required_enrollment_source,
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


def _next_unlock_at(
    conn: psycopg.Connection,
    *,
    course_id: str,
    drip_started_at: datetime,
    current_unlock_position: int,
) -> datetime | None:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT app.compute_course_next_unlock_at(%s, %s, %s)
            """,
            (course_id, drip_started_at, current_unlock_position),
        )
        row = cur.fetchone()
    assert row is not None
    return row[0]


async def test_enrollment_initialization_uses_required_source_authority():
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
            required_enrollment_source="intro_enrollment",
            drip_enabled=True,
            drip_interval_days=7,
            sellable=False,
        )
        _insert_lessons(conn, intro_course_id, count=3)

        _insert_course(
            conn,
            course_id=paid_course_id,
            slug="paid-full-unlock",
            group_position=0,
            required_enrollment_source="purchase",
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
            required_enrollment_source="intro_enrollment",
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
            match="requires enrollment source intro_enrollment",
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
            group_position=0,
            required_enrollment_source="purchase",
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


async def test_custom_drip_substrate_rejects_incomplete_schedule_commits():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        _insert_course(
            conn,
            course_id=course_id,
            slug="custom-incomplete-schedule",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=2)
        lessons = _lesson_rows(conn, course_id)

        with pytest.raises(
            psycopg.Error,
            match="custom drip requires one offset row per lesson",
        ):
            with conn.transaction():
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_configs (course_id)
                        VALUES (%s)
                        """,
                        (course_id,),
                    )
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_lesson_offsets (
                          course_id,
                          lesson_id,
                          unlock_offset_days
                        )
                        VALUES (%s, %s, %s)
                        """,
                        (course_id, str(lessons[0]["id"]), 0),
                    )


async def test_custom_drip_substrate_rejects_negative_offsets_and_mismatched_lessons():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        other_course_id = str(uuid4())
        _insert_course(
            conn,
            course_id=course_id,
            slug="custom-negative-offset",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
        )
        _insert_course(
            conn,
            course_id=other_course_id,
            slug="custom-mismatched-lesson",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=1)
        _insert_lessons(conn, other_course_id, count=1)
        course_lesson = _lesson_rows(conn, course_id)[0]
        other_course_lesson = _lesson_rows(conn, other_course_id)[0]

        with pytest.raises(
            psycopg.Error,
            match="unlock_offset_days_check",
        ):
            with conn.transaction():
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_configs (course_id)
                        VALUES (%s)
                        """,
                        (course_id,),
                    )
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_lesson_offsets (
                          course_id,
                          lesson_id,
                          unlock_offset_days
                        )
                        VALUES (%s, %s, %s)
                        """,
                        (course_id, str(course_lesson["id"]), -1),
                    )

        with pytest.raises(
            psycopg.Error,
            match="must belong to course",
        ):
            with conn.transaction():
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_configs (course_id)
                        VALUES (%s)
                        """,
                        (course_id,),
                    )
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_lesson_offsets (
                          course_id,
                          lesson_id,
                          unlock_offset_days
                        )
                        VALUES (%s, %s, %s)
                        """,
                        (course_id, str(other_course_lesson["id"]), 0),
                    )


async def test_custom_drip_substrate_rejects_duplicate_lesson_rows():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        _insert_course(
            conn,
            course_id=course_id,
            slug="custom-duplicate-row",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=1)
        lesson = _lesson_rows(conn, course_id)[0]

        with pytest.raises(
            psycopg.Error,
            match="course_custom_drip_lesson_offsets_pkey",
        ):
            with conn.transaction():
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_configs (course_id)
                        VALUES (%s)
                        """,
                        (course_id,),
                    )
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_lesson_offsets (
                          course_id,
                          lesson_id,
                          unlock_offset_days
                        )
                        VALUES (%s, %s, %s)
                        """,
                        (course_id, str(lesson["id"]), 0),
                    )
                    cur.execute(
                        """
                        INSERT INTO app.course_custom_drip_lesson_offsets (
                          course_id,
                          lesson_id,
                          unlock_offset_days
                        )
                        VALUES (%s, %s, %s)
                        """,
                        (course_id, str(lesson["id"]), 0),
                    )


async def test_custom_drip_enrollment_initialization_and_worker_advancement():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="custom-drip-advancement",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
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
            source="intro_enrollment",
            granted_at=granted_at,
        )
        assert enrollment["current_unlock_position"] == 1

        unchanged = _advance_enrollment(
            conn,
            enrollment_id=str(enrollment["id"]),
            evaluated_at=granted_at + timedelta(days=1),
        )
        assert unchanged["current_unlock_position"] == 1

        day_2 = _advance_enrollment(
            conn,
            enrollment_id=str(enrollment["id"]),
            evaluated_at=granted_at + timedelta(days=2),
        )
        assert day_2["current_unlock_position"] == 2

        day_10 = _advance_enrollment(
            conn,
            enrollment_id=str(enrollment["id"]),
            evaluated_at=granted_at + timedelta(days=10),
        )
        assert day_10["current_unlock_position"] == 3

        day_20 = _advance_enrollment(
            conn,
            enrollment_id=str(enrollment["id"]),
            evaluated_at=granted_at + timedelta(days=20),
        )
        assert day_20["current_unlock_position"] == 4


async def test_custom_drip_initialization_unlocks_all_zero_offset_lessons():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="custom-drip-zero-offset-range",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=3)
        _configure_custom_drip(
            conn,
            course_id=course_id,
            offsets_by_position={1: 0, 2: 0, 3: 5},
        )

        enrollment = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=course_id,
            source="intro_enrollment",
            granted_at=granted_at,
        )

        assert enrollment["current_unlock_position"] == 2


async def test_legacy_drip_next_unlock_projection_matches_worker_schedule():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, 9, 30, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="legacy-next-unlock",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=True,
            drip_interval_days=7,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=4)

        enrollment = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=course_id,
            source="intro_enrollment",
            granted_at=granted_at,
        )

        assert enrollment["current_unlock_position"] == 1
        assert _next_unlock_at(
            conn,
            course_id=course_id,
            drip_started_at=enrollment["drip_started_at"],
            current_unlock_position=enrollment["current_unlock_position"],
        ) == granted_at + timedelta(days=7)

        advanced = _advance_enrollment(
            conn,
            enrollment_id=str(enrollment["id"]),
            evaluated_at=granted_at + timedelta(days=8),
        )

        assert advanced["current_unlock_position"] == 2
        assert _next_unlock_at(
            conn,
            course_id=course_id,
            drip_started_at=advanced["drip_started_at"],
            current_unlock_position=advanced["current_unlock_position"],
        ) == granted_at + timedelta(days=14)


async def test_custom_drip_next_unlock_projection_matches_canonical_offsets():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, 9, 30, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="custom-next-unlock",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
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
            source="intro_enrollment",
            granted_at=granted_at,
        )

        assert enrollment["current_unlock_position"] == 1
        assert _next_unlock_at(
            conn,
            course_id=course_id,
            drip_started_at=enrollment["drip_started_at"],
            current_unlock_position=enrollment["current_unlock_position"],
        ) == granted_at + timedelta(days=2)

        advanced = _advance_enrollment(
            conn,
            enrollment_id=str(enrollment["id"]),
            evaluated_at=granted_at + timedelta(days=2),
        )

        assert advanced["current_unlock_position"] == 2
        assert _next_unlock_at(
            conn,
            course_id=course_id,
            drip_started_at=advanced["drip_started_at"],
            current_unlock_position=advanced["current_unlock_position"],
        ) == granted_at + timedelta(days=7)


async def test_no_drip_next_unlock_projection_returns_null():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, 9, 30, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="no-drip-next-unlock",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=3)

        enrollment = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=course_id,
            source="intro_enrollment",
            granted_at=granted_at,
        )

        assert enrollment["current_unlock_position"] == 3
        assert (
            _next_unlock_at(
                conn,
                course_id=course_id,
                drip_started_at=enrollment["drip_started_at"],
                current_unlock_position=enrollment["current_unlock_position"],
            )
            is None
        )


async def test_custom_drip_schedule_locks_after_first_enrollment():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="custom-drip-locks",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=2)
        _configure_custom_drip(
            conn,
            course_id=course_id,
            offsets_by_position={1: 0, 2: 3},
        )

        lessons = _lesson_rows(conn, course_id)
        _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=course_id,
            source="intro_enrollment",
            granted_at=granted_at,
        )

        with pytest.raises(
            psycopg.Error,
            match="schedule-affecting edits are locked after first enrollment",
        ):
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE app.course_custom_drip_lesson_offsets
                       SET unlock_offset_days = 4
                     WHERE course_id = %s
                       AND lesson_id = %s
                    """,
                    (course_id, str(lessons[1]["id"])),
                )

        with pytest.raises(
            psycopg.Error,
            match="schedule-affecting edits are locked after first enrollment",
        ):
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO app.lessons (id, course_id, lesson_title, position)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (str(uuid4()), course_id, "locked-new-lesson", 3),
                )


async def test_invalid_custom_drip_state_fails_closed_without_fallback():
    with _baseline_v2_connection() as conn:
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="custom-drip-fail-closed",
            group_position=0,
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
            sellable=False,
        )
        _insert_lessons(conn, course_id, count=2)
        _configure_custom_drip(
            conn,
            course_id=course_id,
            offsets_by_position={1: 0, 2: 3},
        )

        lesson_to_remove = _lesson_rows(conn, course_id)[1]
        with conn.cursor() as cur:
            cur.execute(
                """
                ALTER TABLE app.course_custom_drip_lesson_offsets
                DISABLE TRIGGER course_custom_drip_lesson_offsets_schedule_consistency
                """
            )
            cur.execute(
                """
                DELETE FROM app.course_custom_drip_lesson_offsets
                 WHERE course_id = %s
                   AND lesson_id = %s
                """,
                (course_id, str(lesson_to_remove["id"])),
            )
            cur.execute(
                """
                ALTER TABLE app.course_custom_drip_lesson_offsets
                ENABLE TRIGGER course_custom_drip_lesson_offsets_schedule_consistency
                """
            )

        with pytest.raises(
            psycopg.Error,
            match="custom drip requires one offset row per lesson",
        ):
            _create_enrollment(
                conn,
                enrollment_id=str(uuid4()),
                user_id=user_id,
                course_id=course_id,
                source="intro_enrollment",
                granted_at=granted_at,
            )
