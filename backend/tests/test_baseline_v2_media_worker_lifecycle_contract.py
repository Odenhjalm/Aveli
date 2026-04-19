from __future__ import annotations

import os
from contextlib import contextmanager
from datetime import datetime, timezone
from uuid import uuid4

import psycopg
import pytest
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.rows import dict_row

from backend.bootstrap import baseline_v2


pytestmark = pytest.mark.anyio("asyncio")


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
    db_name = f"aveli_baseline_v2_media_{uuid4().hex[:12]}"
    admin_conninfo = _admin_conninfo()
    database_conninfo = _db_conninfo(db_name)

    with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
        admin_conn.execute(
            sql.SQL("CREATE DATABASE {}").format(sql.Identifier(db_name))
        )

    try:
        with psycopg.connect(
            database_conninfo, autocommit=True, row_factory=dict_row
        ) as conn:
            for slot in baseline_v2._slot_paths():
                conn.execute(slot.read_text(encoding="utf-8"))
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


def _insert_media_asset(conn: psycopg.Connection, *, media_id: str) -> None:
    conn.execute(
        """
        INSERT INTO app.media_assets (
          id,
          media_type,
          purpose,
          original_object_path,
          ingest_format,
          file_size,
          content_hash_algorithm,
          content_hash
        )
        VALUES (
          %s::uuid,
          'audio'::app.media_type,
          'lesson_media'::app.media_purpose,
          'courses/course-1/lessons/lesson-1/media/source.wav',
          'wav',
          4,
          'sha256',
          repeat('a', 64)
        )
        """,
        (media_id,),
    )


def _insert_course_cover_asset(conn: psycopg.Connection, *, media_id: str) -> None:
    conn.execute(
        """
        INSERT INTO app.media_assets (
          id,
          media_type,
          purpose,
          original_object_path,
          ingest_format,
          file_size,
          content_hash_algorithm,
          content_hash
        )
        VALUES (
          %s::uuid,
          'image'::app.media_type,
          'course_cover'::app.media_purpose,
          'media/source/cover/courses/course-1/source.png',
          'png',
          4,
          'sha256',
          repeat('b', 64)
        )
        """,
        (media_id,),
    )


def _transition(
    conn: psycopg.Connection,
    media_id: str,
    state: str,
    *,
    playback_object_path: str | None = None,
    playback_format: str | None = None,
    error_message: str | None = None,
    next_retry_at: datetime | None = None,
) -> dict[str, object]:
    row = conn.execute(
        """
        SELECT *
        FROM app.canonical_worker_transition_media_asset(
          %s::uuid,
          %s::app.media_state,
          %s,
          %s,
          %s,
          %s
        )
        """,
        (
            media_id,
            state,
            playback_object_path,
            playback_format,
            error_message,
            next_retry_at,
        ),
    ).fetchone()
    assert row is not None
    return dict(row)


async def test_media_lifecycle_mutations_are_db_function_owned():
    with _baseline_v2_connection() as conn:
        media_id = str(uuid4())
        _insert_media_asset(conn, media_id=media_id)

        with pytest.raises(
            psycopg.Error,
            match="media lifecycle fields may be mutated only through the canonical worker context",
        ):
            conn.execute(
                sql.SQL(
                    "UPDATE {} SET state = 'uploaded'::app.media_state WHERE id = %s::uuid"
                ).format(sql.Identifier("app", "media_assets")),
                (media_id,),
            )

        uploaded = _transition(conn, media_id, "uploaded")
        assert str(uploaded["state"]) == "uploaded"

        locked = conn.execute(
            """
            SELECT *
            FROM app.canonical_worker_lock_media_asset_for_processing(%s::uuid)
            """,
            (media_id,),
        ).fetchone()
        assert locked is not None
        assert str(locked["state"]) == "processing"
        assert locked["processing_locked_at"] is not None
        assert int(locked["processing_attempts"]) == 0

        with pytest.raises(
            psycopg.Error,
            match="media lifecycle fields may be mutated only through the canonical worker context",
        ):
            conn.execute(
                sql.SQL(
                    "UPDATE {} SET processing_attempts = processing_attempts + 1 WHERE id = %s::uuid"
                ).format(sql.Identifier("app", "media_assets")),
                (media_id,),
            )

        incremented = conn.execute(
            """
            SELECT *
            FROM app.canonical_worker_increment_media_asset_attempts(%s::uuid)
            """,
            (media_id,),
        ).fetchone()
        assert incremented is not None
        assert int(incremented["processing_attempts"]) == 1

        retry_at = datetime(2026, 4, 19, 12, 0, tzinfo=timezone.utc)
        deferred = conn.execute(
            """
            SELECT *
            FROM app.canonical_worker_defer_media_asset_processing(%s::uuid, %s)
            """,
            (media_id, retry_at),
        ).fetchone()
        assert deferred is not None
        assert deferred["processing_locked_at"] is None
        assert deferred["next_retry_at"] == retry_at

        relocked = conn.execute(
            """
            SELECT *
            FROM app.canonical_worker_lock_media_asset_for_processing(%s::uuid)
            """,
            (media_id,),
        ).fetchone()
        assert relocked is not None
        assert str(relocked["state"]) == "processing"

        with pytest.raises(
            psycopg.Error, match="ready media requires playback_format"
        ):
            _transition(
                conn,
                media_id,
                "ready",
                playback_object_path="media/derived/source.mp3",
                playback_format=None,
            )

        ready = _transition(
            conn,
            media_id,
            "ready",
            playback_object_path="media/derived/source.mp3",
            playback_format="mp3",
        )
        assert str(ready["state"]) == "ready"
        assert ready["playback_object_path"] == "media/derived/source.mp3"
        assert ready["playback_format"] == "mp3"


async def test_course_cover_ready_requires_jpg_playback_identity():
    with _baseline_v2_connection() as conn:
        media_id = str(uuid4())
        _insert_course_cover_asset(conn, media_id=media_id)
        _transition(conn, media_id, "uploaded")
        conn.execute(
            """
            SELECT app.canonical_worker_lock_media_asset_for_processing(%s::uuid)
            """,
            (media_id,),
        )

        with pytest.raises(
            psycopg.Error,
            match="ready media requires playback_format",
        ):
            _transition(
                conn,
                media_id,
                "ready",
                playback_object_path="media/derived/cover/courses/course-1/source.jpg",
                playback_format=None,
            )

        with pytest.raises(
            psycopg.Error,
            match="ready course cover media requires playback_format jpg",
        ):
            _transition(
                conn,
                media_id,
                "ready",
                playback_object_path="media/derived/cover/courses/course-1/source.jpg",
                playback_format="png",
            )

        ready = _transition(
            conn,
            media_id,
            "ready",
            playback_object_path="media/derived/cover/courses/course-1/source.jpg",
            playback_format="jpg",
        )
        assert str(ready["state"]) == "ready"
        assert ready["playback_object_path"] == (
            "media/derived/cover/courses/course-1/source.jpg"
        )
        assert ready["playback_format"] == "jpg"


async def test_media_worker_failed_transition_carries_error_and_retry():
    with _baseline_v2_connection() as conn:
        media_id = str(uuid4())
        _insert_media_asset(conn, media_id=media_id)
        _transition(conn, media_id, "uploaded")
        conn.execute(
            """
            SELECT app.canonical_worker_lock_media_asset_for_processing(%s::uuid)
            """,
            (media_id,),
        )

        retry_at = datetime(2026, 4, 19, 12, 5, tzinfo=timezone.utc)
        failed = _transition(
            conn,
            media_id,
            "failed",
            error_message="source missing",
            next_retry_at=retry_at,
        )

        assert str(failed["state"]) == "failed"
        assert failed["error_message"] == "source missing"
        assert failed["next_retry_at"] == retry_at
        assert failed["processing_locked_at"] is None


async def test_media_worker_failed_requeue_is_forbidden():
    with _baseline_v2_connection() as conn:
        media_id = str(uuid4())
        _insert_media_asset(conn, media_id=media_id)
        _transition(conn, media_id, "uploaded")
        conn.execute(
            """
            SELECT app.canonical_worker_lock_media_asset_for_processing(%s::uuid)
            """,
            (media_id,),
        )
        conn.execute(
            """
            SELECT app.canonical_worker_increment_media_asset_attempts(%s::uuid)
            """,
            (media_id,),
        )
        _transition(conn, media_id, "failed", error_message="upload signing failed")

        with pytest.raises(
            psycopg.Error,
            match="media lifecycle fields may be mutated only through the canonical worker context",
        ):
            conn.execute(
                sql.SQL(
                    "UPDATE {} SET state = 'uploaded'::app.media_state WHERE id = %s::uuid"
                ).format(sql.Identifier("app", "media_assets")),
                (media_id,),
            )

        with pytest.raises(
            psycopg.Error,
            match="failed media requeue is not authorized",
        ):
            conn.execute(
                """
                SELECT *
                FROM app.canonical_worker_requeue_failed_media_asset(%s::uuid)
                """,
                (media_id,),
            )

        row = conn.execute(
            "SELECT state::text AS state FROM app.media_assets WHERE id = %s::uuid",
            (media_id,),
        ).fetchone()
        assert row is not None
        assert row["state"] == "failed"
