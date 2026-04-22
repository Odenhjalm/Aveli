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


def _admin_conninfo() -> str:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        pytest.skip("DATABASE_URL is required for isolated Baseline V2 family tests")
    conninfo = conninfo_to_dict(database_url)
    conninfo["dbname"] = "postgres"
    return make_conninfo(**conninfo)


def _db_conninfo(db_name: str) -> str:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        pytest.skip("DATABASE_URL is required for isolated Baseline V2 family tests")
    conninfo = conninfo_to_dict(database_url)
    conninfo["dbname"] = db_name
    return make_conninfo(**conninfo)


def _slot_paths(*, through: str) -> list[Path]:
    return [path for path in sorted(SLOT_DIR.glob("V2_*.sql")) if path.name <= through]


@contextmanager
def _isolated_database():
    db_name = f"aveli_course_families_{uuid4().hex[:12]}"
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


def _apply_slots(conn: psycopg.Connection, *, through: str) -> None:
    with conn.cursor() as cur:
        for path in _slot_paths(through=through):
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
    title: str,
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
                title,
                slug,
                family_id,
                position,
            ),
        )
    conn.commit()


def test_course_families_backfill_and_fk_preserve_ordering() -> None:
    teacher_id = str(uuid4())
    family_a = str(uuid4())
    family_b = str(uuid4())
    standalone_family = str(uuid4())

    with _isolated_database() as conn:
        _apply_slots(conn, through="V2_0023_course_family_ordering.sql")
        _insert_teacher(conn, teacher_id)
        _insert_course(
            conn,
            course_id=str(uuid4()),
            teacher_id=teacher_id,
            slug="family-a-intro",
            title="Family A Intro",
            family_id=family_a,
            position=0,
        )
        _insert_course(
            conn,
            course_id=str(uuid4()),
            teacher_id=teacher_id,
            slug="family-a-step",
            title="Family A Step",
            family_id=family_a,
            position=1,
        )
        _insert_course(
            conn,
            course_id=str(uuid4()),
            teacher_id=teacher_id,
            slug="family-b-intro",
            title="Family B Intro",
            family_id=family_b,
            position=0,
        )

        with conn.cursor() as cur:
            cur.execute((SLOT_DIR / "V2_0024_course_families.sql").read_text(encoding="utf-8"))
        conn.commit()

        with conn.cursor() as cur:
            cur.execute(
                """
                select id::text, name, teacher_id::text
                  from app.course_families
                 order by id::text
                """
            )
            families = cur.fetchall()
            cur.execute(
                """
                select count(*)
                  from pg_constraint
                 where conname = 'courses_course_group_id_fkey'
                   and conrelid = 'app.courses'::regclass
                """
            )
            fk_count = cur.fetchone()[0]
            cur.execute(
                """
                select course_group_id
                  from app.courses
                 group by course_group_id
                having min(group_position) <> 0
                    or max(group_position) <> count(*) - 1
                    or count(distinct group_position) <> count(*)
                """
            )
            bad_families = cur.fetchall()

            cur.execute(
                """
                insert into app.course_families (id, name, teacher_id)
                values (%s::uuid, 'Standalone Family', %s::uuid)
                """,
                (standalone_family, teacher_id),
            )
            conn.commit()

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
                values (%s::uuid, %s::uuid, 'Standalone Course', 'standalone-course', %s::uuid, 0)
                """,
                (str(uuid4()), teacher_id, standalone_family),
            )
            conn.commit()

            seeded_family_id = str(uuid4())
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
                values (%s::uuid, %s::uuid, 'Seeded Course', 'seeded-course', %s::uuid, 0)
                """,
                (str(uuid4()), teacher_id, seeded_family_id),
            )
            conn.commit()

            cur.execute(
                """
                select count(*)
                  from app.courses as c
                  left join app.course_families as f
                    on f.id = c.course_group_id
                 where f.id is null
                """
            )
            orphan_courses = cur.fetchone()[0]
            cur.execute(
                """
                select name
                  from app.course_families
                 where id = %s::uuid
                """,
                (seeded_family_id,),
            )
            seeded_family = cur.fetchone()

        assert sorted(families) == sorted([
            (family_a, "Family A Intro", teacher_id),
            (family_b, "Family B Intro", teacher_id),
        ])
        assert fk_count == 1
        assert bad_families == []
        assert orphan_courses == 0
        assert seeded_family == ("Seeded Course",)
