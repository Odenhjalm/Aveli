from __future__ import annotations

import os
from contextlib import contextmanager
from pathlib import Path
from uuid import uuid4

import psycopg
import pytest
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo


ROOT = Path(__file__).resolve().parents[2]
SLOT_DIR = ROOT / "backend" / "supabase" / "baseline_v2_slots"


def _slot_paths(*, include_0023: bool) -> list[Path]:
    paths = sorted(SLOT_DIR.glob("V2_*.sql"))
    if include_0023:
        return [
            path
            for path in paths
            if path.name <= "V2_0023_course_family_ordering.sql"
        ]
    return [path for path in paths if path.name < "V2_0023_course_family_ordering.sql"]


def _admin_conninfo() -> str:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        pytest.skip("DATABASE_URL is required for isolated Baseline V2 ordering tests")
    conninfo = conninfo_to_dict(database_url)
    conninfo["dbname"] = "postgres"
    return make_conninfo(**conninfo)


def _db_conninfo(db_name: str) -> str:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        pytest.skip("DATABASE_URL is required for isolated Baseline V2 ordering tests")
    conninfo = conninfo_to_dict(database_url)
    conninfo["dbname"] = db_name
    return make_conninfo(**conninfo)


@contextmanager
def _isolated_database():
    db_name = f"aveli_course_family_{uuid4().hex[:12]}"
    admin_conninfo = _admin_conninfo()
    database_conninfo = _db_conninfo(db_name)

    with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
        admin_conn.execute(sql.SQL("create database {}").format(sql.Identifier(db_name)))

    try:
        with psycopg.connect(database_conninfo, autocommit=False) as conn:
            yield conn
    finally:
        with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
            admin_conn.execute(
                """
                select pg_terminate_backend(pid)
                  from pg_stat_activity
                 where datname = %s
                   and pid <> pg_backend_pid()
                """,
                (db_name,),
            )
            admin_conn.execute(sql.SQL("drop database if exists {}").format(sql.Identifier(db_name)))


def _apply_slots(conn: psycopg.Connection, *, include_0023: bool) -> None:
    with conn.cursor() as cur:
        for path in _slot_paths(include_0023=include_0023):
            cur.execute(path.read_text(encoding="utf-8"))
    conn.commit()


def _insert_teacher(conn: psycopg.Connection, teacher_id: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            insert into app.auth_subjects (user_id, email, onboarding_state, role)
            values (%s, %s, 'completed', 'teacher')
            """,
            (teacher_id, f"{teacher_id}@example.test"),
        )
    conn.commit()


def _insert_course(
    conn: psycopg.Connection,
    *,
    course_id: str,
    teacher_id: str,
    slug: str,
    family_id: str,
    position: int,
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            insert into app.courses (
              id,
              teacher_id,
              title,
              slug,
              course_group_id,
              group_position
            )
            values (%s, %s, %s, %s, %s, %s)
            """,
            (
                course_id,
                teacher_id,
                f"title-{slug}",
                slug,
                family_id,
                position,
            ),
        )
    conn.commit()


def test_slot_0023_backfills_sparse_positions_and_logs_events() -> None:
    teacher_id = "11111111-1111-1111-1111-111111111111"
    family_a = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    family_b = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    family_c = "cccccccc-cccc-cccc-cccc-cccccccccccc"

    with _isolated_database() as conn:
        _apply_slots(conn, include_0023=False)
        _insert_teacher(conn, teacher_id)

        _insert_course(
            conn,
            course_id="10000000-0000-0000-0000-000000000001",
            teacher_id=teacher_id,
            slug="family-a-1",
            family_id=family_a,
            position=1,
        )
        _insert_course(
            conn,
            course_id="10000000-0000-0000-0000-000000000002",
            teacher_id=teacher_id,
            slug="family-a-2",
            family_id=family_a,
            position=3,
        )
        _insert_course(
            conn,
            course_id="10000000-0000-0000-0000-000000000003",
            teacher_id=teacher_id,
            slug="family-b-1",
            family_id=family_b,
            position=0,
        )
        _insert_course(
            conn,
            course_id="10000000-0000-0000-0000-000000000004",
            teacher_id=teacher_id,
            slug="family-c-1",
            family_id=family_c,
            position=2,
        )

        with conn.cursor() as cur:
            cur.execute(
                (
                    SLOT_DIR / "V2_0023_course_family_ordering.sql"
                ).read_text(encoding="utf-8")
            )
        conn.commit()

        with conn.cursor() as cur:
            cur.execute(
                """
                select course_group_id::text,
                       array_agg(group_position order by group_position, id)
                  from app.courses
                 group by course_group_id
                 order by course_group_id::text
                """
            )
            assert cur.fetchall() == [
                (family_a, [0, 1]),
                (family_b, [0]),
                (family_c, [0]),
            ]

            cur.execute(
                """
                select event_type,
                       old_group_position,
                       new_group_position,
                       reason,
                       old_course_group_id::text,
                       new_course_group_id::text
                  from app.course_family_position_events
                 order by course_id
                """
            )
            assert cur.fetchall() == [
                ("update", 1, 0, "baseline_v2_slot_0023_backfill", family_a, family_a),
                ("update", 3, 1, "baseline_v2_slot_0023_backfill", family_a, family_a),
                ("update", 2, 0, "baseline_v2_slot_0023_backfill", family_c, family_c),
            ]


def test_slot_0023_rejects_sparse_new_family_and_allows_transactional_reorder() -> None:
    teacher_id = "21111111-1111-1111-1111-111111111111"
    family_id = "dddddddd-dddd-dddd-dddd-dddddddddddd"

    with _isolated_database() as conn:
        _apply_slots(conn, include_0023=True)
        _insert_teacher(conn, teacher_id)

        _insert_course(
            conn,
            course_id="20000000-0000-0000-0000-000000000001",
            teacher_id=teacher_id,
            slug="family-d-1",
            family_id=family_id,
            position=0,
        )
        _insert_course(
            conn,
            course_id="20000000-0000-0000-0000-000000000002",
            teacher_id=teacher_id,
            slug="family-d-2",
            family_id=family_id,
            position=1,
        )
        _insert_course(
            conn,
            course_id="20000000-0000-0000-0000-000000000003",
            teacher_id=teacher_id,
            slug="family-d-3",
            family_id=family_id,
            position=2,
        )

        with pytest.raises(psycopg.errors.RaiseException, match="contiguous positions from 0 to 0"):
            with conn.cursor() as cur:
                cur.execute(
                    """
                    insert into app.courses (
                      id,
                      teacher_id,
                      title,
                      slug,
                      course_group_id,
                      group_position
                    )
                    values (%s, %s, %s, %s, %s, %s)
                    """,
                    (
                        "20000000-0000-0000-0000-000000000004",
                        teacher_id,
                        "title-family-e-1",
                        "family-e-1",
                        "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
                        1,
                    ),
                )
            conn.commit()
        conn.rollback()

        with conn.cursor() as cur:
            cur.execute(
                """
                update app.courses
                   set group_position = 999
                 where id = %s
                """,
                ("20000000-0000-0000-0000-000000000001",),
            )
            cur.execute(
                """
                update app.courses
                   set group_position = group_position - 1
                 where course_group_id = %s::uuid
                   and group_position between 1 and 2
                """,
                (family_id,),
            )
            cur.execute(
                """
                update app.courses
                   set group_position = 2
                 where id = %s
                """,
                ("20000000-0000-0000-0000-000000000001",),
            )
        conn.commit()

        with conn.cursor() as cur:
            cur.execute(
                """
                select id::text, group_position
                  from app.courses
                 where course_group_id = %s::uuid
                 order by group_position
                """,
                (family_id,),
            )
            assert cur.fetchall() == [
                ("20000000-0000-0000-0000-000000000002", 0),
                ("20000000-0000-0000-0000-000000000003", 1),
                ("20000000-0000-0000-0000-000000000001", 2),
            ]


def test_slot_0023_requires_delete_collapse_and_allows_cross_family_move() -> None:
    teacher_id = "31111111-1111-1111-1111-111111111111"
    source_family = "ffffffff-ffff-ffff-ffff-ffffffffffff"
    target_family = "99999999-9999-9999-9999-999999999999"

    with _isolated_database() as conn:
        _apply_slots(conn, include_0023=True)
        _insert_teacher(conn, teacher_id)

        _insert_course(
            conn,
            course_id="30000000-0000-0000-0000-000000000001",
            teacher_id=teacher_id,
            slug="source-1",
            family_id=source_family,
            position=0,
        )
        _insert_course(
            conn,
            course_id="30000000-0000-0000-0000-000000000002",
            teacher_id=teacher_id,
            slug="source-2",
            family_id=source_family,
            position=1,
        )
        _insert_course(
            conn,
            course_id="30000000-0000-0000-0000-000000000003",
            teacher_id=teacher_id,
            slug="target-1",
            family_id=target_family,
            position=0,
        )

        with pytest.raises(psycopg.errors.RaiseException, match="contiguous positions from 0 to 0"):
            with conn.cursor() as cur:
                cur.execute(
                    "delete from app.courses where id = %s",
                    ("30000000-0000-0000-0000-000000000001",),
                )
            conn.commit()
        conn.rollback()

        with conn.cursor() as cur:
            cur.execute(
                """
                update app.courses
                   set group_position = 999
                 where id = %s
                """,
                ("30000000-0000-0000-0000-000000000002",),
            )
            cur.execute(
                """
                update app.courses
                   set group_position = group_position - 1
                 where course_group_id = %s::uuid
                   and group_position > 1
                """,
                (source_family,),
            )
            cur.execute(
                """
                update app.courses
                   set group_position = group_position + 1
                 where course_group_id = %s::uuid
                   and group_position >= 1
                """,
                (target_family,),
            )
            cur.execute(
                """
                update app.courses
                   set course_group_id = %s::uuid,
                       group_position = 1
                 where id = %s
                """,
                (
                    target_family,
                    "30000000-0000-0000-0000-000000000002",
                ),
            )
        conn.commit()

        with conn.cursor() as cur:
            cur.execute(
                """
                select course_group_id::text,
                       array_agg(id::text order by group_position)
                  from app.courses
                 group by course_group_id
                 order by course_group_id::text
                """
            )
            assert cur.fetchall() == [
                (
                    target_family,
                    [
                        "30000000-0000-0000-0000-000000000003",
                        "30000000-0000-0000-0000-000000000002",
                    ],
                ),
                (source_family, ["30000000-0000-0000-0000-000000000001"]),
            ]
