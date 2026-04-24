from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from psycopg.rows import dict_row

from tests.test_course_drip_worker_selection import (
    _apply_baseline_v2_slots,
    _baseline_v2_connection,
    _configure_custom_drip,
    _create_enrollment,
    _insert_course,
    _insert_auth_subject,
    _insert_lessons,
    _lesson_rows,
    _read_current_unlock_position,
    _run_course_drip_worker_once,
)


pytestmark = pytest.mark.anyio("asyncio")


def _completion_rows(conn, *, user_id: str) -> list[dict[str, object]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT user_id, course_id, lesson_id, completion_source
            FROM app.lesson_completions
            WHERE user_id = %s
            ORDER BY course_id, lesson_id
            """,
            (user_id,),
        )
        rows = [dict(row) for row in cur.fetchall()]
    return [
        {
            "user_id": str(row["user_id"]),
            "course_id": str(row["course_id"]),
            "lesson_id": str(row["lesson_id"]),
            "completion_source": row["completion_source"],
        }
        for row in rows
    ]


def _create_intro_enrollment(
    conn,
    *,
    enrollment_id: str,
    user_id: str,
    course_id: str,
    granted_at: datetime,
) -> dict[str, object]:
    _insert_auth_subject(conn, user_id, role="learner")
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT *
            FROM app.canonical_create_course_enrollment(%s, %s, %s, %s, %s)
            """,
            (
                enrollment_id,
                user_id,
                course_id,
                "intro_enrollment",
                granted_at,
            ),
        )
        row = cur.fetchone()
    assert row is not None
    return dict(row)


async def test_run_once_advances_custom_lesson_offset_drip_enrollment():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="worker-custom-offsets-ice010",
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


async def test_run_once_does_not_advance_no_drip_immediate_access_enrollment():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="worker-no-drip-ice010",
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
        assert _completion_rows(conn, user_id=user_id) == []


async def test_worker_auto_completion_waits_for_final_unlock_and_seven_day_window():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)

        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="worker-legacy-autocomplete",
            required_enrollment_source="intro_enrollment",
            drip_enabled=True,
            drip_interval_days=2,
        )
        _insert_lessons(conn, course_id, count=3)
        final_lesson_id = str(_lesson_rows(conn, course_id)[-1]["id"])
        enrollment = _create_intro_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=course_id,
            granted_at=granted_at,
        )
        assert enrollment["current_unlock_position"] == 1

        first_run = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=10),
        )
        assert first_run == 1
        assert _completion_rows(conn, user_id=user_id) == []

        second_run = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=11),
        )
        assert second_run == 0

        completion_rows = _completion_rows(conn, user_id=user_id)
        assert completion_rows == [
            {
                "user_id": user_id,
                "course_id": course_id,
                "lesson_id": final_lesson_id,
                "completion_source": "auto_final_lesson",
            }
        ]


async def test_worker_auto_completion_supports_custom_and_no_drip_intro_enrollments():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)

        custom_course_id = str(uuid4())
        no_drip_course_id = str(uuid4())
        custom_user_id = str(uuid4())
        no_drip_user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=custom_course_id,
            slug="worker-custom-autocomplete",
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
        )
        _insert_lessons(conn, custom_course_id, count=4)
        _configure_custom_drip(
            conn,
            course_id=custom_course_id,
            offsets_by_position={1: 0, 2: 2, 3: 7, 4: 14},
        )
        custom_final_lesson_id = str(_lesson_rows(conn, custom_course_id)[-1]["id"])
        custom_enrollment = _create_intro_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=custom_user_id,
            course_id=custom_course_id,
            granted_at=granted_at,
        )

        _insert_course(
            conn,
            course_id=no_drip_course_id,
            slug="worker-no-drip-autocomplete",
            required_enrollment_source="intro_enrollment",
            drip_enabled=False,
            drip_interval_days=None,
        )
        _insert_lessons(conn, no_drip_course_id, count=3)
        no_drip_final_lesson_id = str(_lesson_rows(conn, no_drip_course_id)[-1]["id"])
        no_drip_enrollment = _create_intro_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=no_drip_user_id,
            course_id=no_drip_course_id,
            granted_at=granted_at,
        )

        assert custom_enrollment["current_unlock_position"] == 1
        assert no_drip_enrollment["current_unlock_position"] == 3

        before_window = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=6),
        )
        assert before_window == 1
        assert _read_current_unlock_position(conn, str(custom_enrollment["id"])) == 2
        assert _read_current_unlock_position(conn, str(no_drip_enrollment["id"])) == 3
        assert _completion_rows(conn, user_id=custom_user_id) == []
        assert _completion_rows(conn, user_id=no_drip_user_id) == []

        no_drip_window = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=7),
        )
        assert no_drip_window == 1
        assert _read_current_unlock_position(conn, str(custom_enrollment["id"])) == 3
        assert _completion_rows(conn, user_id=no_drip_user_id) == [
            {
                "user_id": no_drip_user_id,
                "course_id": no_drip_course_id,
                "lesson_id": no_drip_final_lesson_id,
                "completion_source": "auto_final_lesson",
            }
        ]

        custom_window = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=21),
        )
        assert custom_window == 1
        assert _completion_rows(conn, user_id=custom_user_id) == [
            {
                "user_id": custom_user_id,
                "course_id": custom_course_id,
                "lesson_id": custom_final_lesson_id,
                "completion_source": "auto_final_lesson",
            }
        ]

        repeat_run = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=30),
        )
        assert repeat_run == 0
        assert _completion_rows(conn, user_id=custom_user_id) == [
            {
                "user_id": custom_user_id,
                "course_id": custom_course_id,
                "lesson_id": custom_final_lesson_id,
                "completion_source": "auto_final_lesson",
            }
        ]
        assert _completion_rows(conn, user_id=no_drip_user_id) == [
            {
                "user_id": no_drip_user_id,
                "course_id": no_drip_course_id,
                "lesson_id": no_drip_final_lesson_id,
                "completion_source": "auto_final_lesson",
            }
        ]
