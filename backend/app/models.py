import json
import hashlib
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote, urlparse

from psycopg import InterfaceError, errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from .db import get_conn, pool
from .auth import hash_password
from .repositories import (
    create_order as repo_create_order,
    create_user as repo_create_user,
    get_profile as repo_get_profile,
    get_user_by_email as repo_get_user_by_email,
    get_user_by_id as repo_get_user_by_id,
    get_user_order as repo_get_user_order,
    list_services as repo_list_services,
    mark_order_paid as repo_mark_order_paid,
    set_order_checkout_reference as repo_set_order_checkout_reference,
    update_profile as repo_update_profile,
    upsert_refresh_token as repo_upsert_refresh_token,
)
from .repositories.orders import get_order as repo_get_order
from .services import courses_service
from .config import settings
from .utils import media_signer

logger = logging.getLogger(__name__)


async def _fetchone(cur):
    try:
        return await cur.fetchone()
    except InterfaceError:
        return None


async def create_media_object(
    *,
    owner_id: str | None,
    storage_path: str,
    storage_bucket: str,
    content_type: str | None,
    byte_size: int,
    checksum: str | None,
    original_name: str | None,
) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.media_objects (
                    owner_id,
                    storage_path,
                    storage_bucket,
                    content_type,
                    byte_size,
                    checksum,
                    original_name,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, now())
                ON CONFLICT (storage_path, storage_bucket) DO UPDATE
                  SET owner_id = COALESCE(excluded.owner_id, app.media_objects.owner_id),
                      content_type = excluded.content_type,
                      byte_size = excluded.byte_size,
                      checksum = COALESCE(excluded.checksum, app.media_objects.checksum),
                      original_name = COALESCE(excluded.original_name, app.media_objects.original_name),
                      updated_at = now()
                RETURNING id, owner_id, storage_path, storage_bucket, content_type, byte_size, checksum, original_name
                """,
                (
                    owner_id,
                    storage_path,
                    storage_bucket,
                    content_type,
                    byte_size,
                    checksum,
                    original_name,
                ),
            )
            row = await _fetchone(cur)
            await conn.commit()
            return row


async def cleanup_media_object(media_id: str) -> None:
    if not media_id:
        return
    row = None
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            queries = [
                """
                DELETE FROM app.media_objects mo
                WHERE mo.id = %s
                  AND NOT EXISTS (
                    SELECT 1 FROM app.lesson_media lm WHERE lm.media_id = mo.id
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM app.profiles p WHERE p.avatar_media_id = mo.id
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM app.teacher_profile_media tpm WHERE tpm.cover_media_id = mo.id
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM app.meditations m WHERE m.media_id = mo.id
                  )
                RETURNING mo.storage_path, mo.storage_bucket
                """,
                """
                DELETE FROM app.media_objects mo
                WHERE mo.id = %s
                  AND NOT EXISTS (
                    SELECT 1 FROM app.lesson_media lm WHERE lm.media_id = mo.id
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM app.profiles p WHERE p.avatar_media_id = mo.id
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM app.meditations m WHERE m.media_id = mo.id
                  )
                RETURNING mo.storage_path, mo.storage_bucket
                """,
                """
                DELETE FROM app.media_objects mo
                WHERE mo.id = %s
                  AND NOT EXISTS (
                    SELECT 1 FROM app.lesson_media lm WHERE lm.media_id = mo.id
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM app.profiles p WHERE p.avatar_media_id = mo.id
                  )
                RETURNING mo.storage_path, mo.storage_bucket
                """,
            ]
            for query in queries:
                try:
                    await cur.execute(query, (media_id,))
                    row = await _fetchone(cur)
                    break
                except errors.UndefinedTable:
                    await conn.rollback()
            await conn.commit()

    if not row:
        return

    storage_path = row.get("storage_path") if isinstance(row, dict) else None
    storage_bucket = row.get("storage_bucket") if isinstance(row, dict) else None
    if not storage_path:
        return

    candidates: list[Path] = []
    uploads_root = Path(__file__).resolve().parents[1] / "assets" / "uploads"
    try:
        relative = Path(str(storage_path))
        if not relative.is_absolute() and ".." not in relative.parts:
            candidate = (uploads_root / relative).resolve()
            if str(candidate).startswith(str(uploads_root.resolve())):
                candidates.append(candidate)
    except Exception:  # pragma: no cover - defensive
        pass

    base_dir = Path(settings.media_root)
    if storage_bucket:
        candidates.append(base_dir / str(storage_bucket) / str(storage_path))
    candidates.append(base_dir / str(storage_path))

    seen: set[Path] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        try:
            if candidate.exists() and candidate.is_file():
                candidate.unlink()
        except Exception as exc:  # pragma: no cover - defensive logging
            logger.warning("Failed to delete media object file %s: %s", candidate, exc)


async def get_media_object(media_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, owner_id, storage_path, storage_bucket, content_type, byte_size, checksum, original_name
            FROM app.media_objects
            WHERE id = %s
            """,
            (media_id,),
        )
        return await _fetchone(cur)


def _hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


async def register_refresh_token(
    user_id: str, token: str, jti: str, expires_at: datetime
) -> None:
    token_hash = _hash_refresh_token(token)
    await repo_upsert_refresh_token(
        user_id=user_id,
        jti=jti,
        token_hash=token_hash,
        expires_at=expires_at,
    )


async def validate_refresh_token(jti: str, token: str) -> dict | None:
    token_hash = _hash_refresh_token(token)
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT id, user_id, token_hash, expires_at, revoked_at, rotated_at
                FROM app.refresh_tokens
                WHERE jti = %s
                FOR UPDATE
                """,
                (jti,),
            )
            row = await _fetchone(cur)
            if not row:
                await conn.rollback()
                return None

            if row.get("revoked_at") is not None or row.get("rotated_at") is not None:
                await conn.rollback()
                return None

            expires_at = row.get("expires_at")
            if expires_at and isinstance(expires_at, datetime):
                if expires_at < datetime.now(timezone.utc):
                    await cur.execute(
                        "UPDATE app.refresh_tokens SET revoked_at = now() WHERE jti = %s",
                        (jti,),
                    )
                    await conn.commit()
                    return None

            if row.get("token_hash") != token_hash:
                await cur.execute(
                    "UPDATE app.refresh_tokens SET revoked_at = now() WHERE jti = %s",
                    (jti,),
                )
                await conn.commit()
                return None

            await cur.execute(
                """
                UPDATE app.refresh_tokens
                SET rotated_at = now(), last_used_at = now()
                WHERE jti = %s
                """,
                (jti,),
            )
            await conn.commit()
            return row


async def record_auth_event(
    user_id: str | None,
    email: str | None,
    event: str,
    ip_address: str | None,
    user_agent: str | None,
    metadata: dict | None = None,
) -> None:
    ip_value = ip_address if ip_address and ip_address != "unknown" else None
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.auth_events (user_id, email, event, ip_address, user_agent, metadata)
                VALUES (%s, %s, %s, %s::inet, %s, %s)
                """,
                (
                    user_id,
                    email.lower() if email else None,
                    event,
                    ip_value,
                    user_agent,
                    Jsonb(metadata or {}),
                ),
            )
            await conn.commit()


async def get_user_by_email(email: str):
    return await repo_get_user_by_email(email)


async def get_user_by_id(user_id: str):
    return await repo_get_user_by_id(user_id)


async def create_user(email: str, password: str, display_name: str):
    hashed = hash_password(password)
    result = await repo_create_user(
        email=email,
        hashed_password=hashed,
        display_name=display_name,
    )
    return result["user"]["id"]


async def is_teacher_user(user_id: str) -> bool:
    profile = await get_profile(user_id)
    if not profile:
        return False
    if profile.get("is_admin"):
        return True
    if (profile.get("role_v2") or "user") in {"teacher", "admin"}:
        return True

    async with get_conn() as cur:
        await cur.execute(
            "SELECT 1 FROM app.teacher_permissions "
            "WHERE profile_id = %s AND (can_edit_courses = true OR can_publish = true) "
            "LIMIT 1",
            (user_id,),
        )
        if await _fetchone(cur):
            return True

        await cur.execute(
            "SELECT 1 FROM app.teacher_approvals WHERE user_id = %s AND approved_at IS NOT NULL LIMIT 1",
            (user_id,),
        )
        row = await _fetchone(cur)
        return row is not None


async def teacher_courses(user_id: str) -> Iterable[dict]:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    SELECT id,
                           title,
                           slug,
                           description,
                           cover_url,
                           cover_media_id,
                           video_url,
                           branch,
                           is_free_intro,
                           journey_step,
                           is_published,
                           price_amount_cents,
                           currency,
                           created_at,
                           updated_at
                    FROM app.courses
                    WHERE created_by = %s
                    ORDER BY updated_at DESC
                    """,
                    (user_id,),
                )
            except errors.UndefinedColumn:
                await conn.rollback()
                await cur.execute(
                    """
                    SELECT id,
                           title,
                           slug,
                           description,
                           cover_url,
                           NULL::uuid AS cover_media_id,
                           video_url,
                           branch,
                           is_free_intro,
                           NULL::text AS journey_step,
                           is_published,
                           0::int AS price_amount_cents,
                           'sek'::text AS currency,
                           created_at,
                           updated_at
                    FROM app.courses
                    WHERE created_by = %s
                    ORDER BY updated_at DESC
                    """,
                    (user_id,),
                )
            return await cur.fetchall()


async def user_certificates(
    user_id: str, verified_only: bool = False
) -> Iterable[dict]:
    clauses = ["user_id = %s"]
    params = [user_id]
    if verified_only:
        clauses.append("status = 'verified'")
    query = """
        SELECT id, user_id, title, status, notes, evidence_url, created_at, updated_at
        FROM app.certificates
        WHERE {where}
        ORDER BY updated_at DESC
    """.format(where=" AND ".join(clauses))
    async with get_conn() as cur:
        await cur.execute(query, params)
        return await cur.fetchall()


async def teacher_application_certificate(user_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, user_id, title, status, notes, evidence_url, created_at, updated_at
            FROM app.certificates
            WHERE user_id = %s AND lower(title) = lower(%s)
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            (user_id, "Läraransökan"),
        )
        return await _fetchone(cur)


async def add_certificate(
    user_id: str,
    *,
    title: str,
    status: str = "pending",
    notes: str | None = None,
    evidence_url: str | None = None,
) -> dict:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.certificates (user_id, title, status, notes, evidence_url)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, user_id, title, status, notes, evidence_url, created_at, updated_at
                """,
                (user_id, title, status, notes, evidence_url),
            )
            row = await _fetchone(cur)
            await conn.commit()
            return row


async def certificates_of(user_id: str, verified_only: bool = False) -> Iterable[dict]:
    return await user_certificates(user_id, verified_only)


async def teacher_status(user_id: str) -> dict:
    is_teacher = await is_teacher_user(user_id)
    verified = await user_certificates(user_id, True)
    application = await teacher_application_certificate(user_id)
    return {
        "is_teacher": is_teacher,
        "verified_certificates": len(verified),
        "has_application": application is not None,
    }


async def update_user_password(user_id: str, password: str) -> None:
    hashed = hash_password(password)
    async with get_conn() as cur:
        await cur.execute(
            """
            UPDATE auth.users
            SET encrypted_password = %s,
                updated_at = now()
            WHERE id = %s
            """,
            (hashed, user_id),
        )


async def create_course_for_user(user_id: str, data: dict) -> dict | None:
    payload = {**data, "created_by": user_id}
    return await courses_service.create_course(payload)


async def update_course_for_user(
    user_id: str, course_id: str, patch: dict
) -> dict | None:
    if not await courses_service.is_course_owner(user_id, course_id):
        return None
    payload = {key: value for key, value in patch.items()}
    return await courses_service.update_course(course_id, payload)


async def delete_course_for_user(user_id: str, course_id: str) -> bool:
    if not await courses_service.is_course_owner(user_id, course_id):
        return False
    return await courses_service.delete_course(course_id)


async def list_courses(
    *,
    published_only: bool = True,
    free_intro: bool | None = None,
    search: str | None = None,
    limit: int | None = None,
) -> Iterable[dict]:
    rows = await courses_service.list_public_courses(
        published_only=published_only,
        free_intro=free_intro,
        search=search,
        limit=limit,
    )
    return rows


async def list_intro_courses(limit: int = 5) -> Iterable[dict]:
    return await list_courses(free_intro=True, limit=limit)


async def list_popular_courses(limit: int = 6) -> Iterable[dict]:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    SELECT
                        c.id,
                        c.slug,
                        c.title,
                        c.description,
                        c.cover_url,
                        c.cover_media_id,
                        c.video_url,
                        c.branch,
                        c.is_free_intro,
                        c.price_amount_cents,
                        c.currency,
                        c.is_published,
                        c.created_by,
                        c.created_at,
                        c.updated_at,
                        COALESCE(pr.priority, 1000) AS teacher_priority
                    FROM app.courses c
                    JOIN app.profiles prof
                      ON prof.user_id = c.created_by
                    LEFT JOIN app.course_display_priorities pr
                      ON pr.teacher_id = c.created_by
                    WHERE c.is_published = true
                      AND (prof.role_v2 = 'teacher' OR prof.is_admin = true)
                      AND COALESCE(prof.email, '') NOT ILIKE '%%@example.com'
                    ORDER BY COALESCE(pr.priority, 1000), c.updated_at DESC
                    LIMIT %s
                    """,
                    (limit,),
                )
            except errors.UndefinedColumn:
                await conn.rollback()
                await cur.execute(
                    """
                    SELECT
                        c.id,
                        c.slug,
                        c.title,
                        c.description,
                        c.cover_url,
                        NULL::uuid AS cover_media_id,
                        c.video_url,
                        c.branch,
                        c.is_free_intro,
                        0::int AS price_amount_cents,
                        'sek'::text AS currency,
                        c.is_published,
                        c.created_by,
                        c.created_at,
                        c.updated_at,
                        COALESCE(pr.priority, 1000) AS teacher_priority
                    FROM app.courses c
                    JOIN app.profiles prof
                      ON prof.user_id = c.created_by
                    LEFT JOIN app.course_display_priorities pr
                      ON pr.teacher_id = c.created_by
                    WHERE c.is_published = true
                      AND (prof.role_v2 = 'teacher' OR prof.is_admin = true)
                      AND COALESCE(prof.email, '') NOT ILIKE '%%@example.com'
                    ORDER BY COALESCE(pr.priority, 1000), c.updated_at DESC
                    LIMIT %s
                    """,
                    (limit,),
                )
            rows = await cur.fetchall()
            return rows


async def list_teachers(limit: int = 20) -> Iterable[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT
              prof.user_id,
              prof.display_name,
              prof.photo_url,
              prof.bio,
              u.raw_user_meta_data->>'avatar_url' AS auth_avatar_url,
              u.raw_user_meta_data->>'picture' AS auth_picture_url
            FROM app.profiles prof
            LEFT JOIN auth.users u ON u.id = prof.user_id
            WHERE (prof.role_v2 = 'teacher' OR prof.is_admin = true)
              AND lower(prof.email) = lower(%s)
            ORDER BY prof.display_name NULLS LAST
            LIMIT %s
            """,
            ("avelibooks@gmail.com", limit),
        )
        rows = await cur.fetchall()

    items: list[dict[str, Any]] = []
    for row in rows:
        item = dict(row)
        item["photo_url"] = _choose_public_profile_photo_url(
            item.get("photo_url"),
            auth_avatar_url=item.get("auth_avatar_url"),
            auth_picture_url=item.get("auth_picture_url"),
        )
        item.pop("auth_avatar_url", None)
        item.pop("auth_picture_url", None)
        items.append(item)
    return items


def _normalize_public_profile_photo_url(url: str | None) -> str | None:
    if not url:
        return None
    value = url.strip()
    if not value:
        return None

    parsed = urlparse(value)
    if parsed.scheme in {"http", "https"}:
        if parsed.path.startswith(("/api/files/", "/profiles/avatar/", "/auth/avatar/")):
            suffix = f"?{parsed.query}" if parsed.query else ""
            return f"{parsed.path}{suffix}"
        return value

    if value.startswith(("api/files/", "profiles/avatar/", "auth/avatar/")):
        return f"/{value}"

    if value.startswith(("/api/files/", "/profiles/avatar/", "/auth/avatar/")):
        return value

    public_url = media_signer.public_download_url(value)
    return public_url or value


_UPLOADS_ROOT = Path(__file__).resolve().parents[1] / "assets" / "uploads"


def _public_upload_exists(api_files_url: str) -> bool:
    if not api_files_url:
        return False
    base = api_files_url.split("?", 1)[0]
    if not base.startswith("/api/files/"):
        return True

    relative = base[len("/api/files/") :]
    if not relative:
        return False
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts:
        return False

    base_root = _UPLOADS_ROOT.resolve()
    candidate = (_UPLOADS_ROOT / path).resolve()
    if not str(candidate).startswith(str(base_root)):
        return False
    return candidate.exists() and candidate.is_file()


def _sanitize_public_avatar_url(url: str | None) -> str | None:
    if not url:
        return None
    value = url.strip()
    if not value:
        return None

    parsed = urlparse(value)
    if parsed.scheme == "https":
        return parsed.geturl()
    if parsed.scheme == "http":
        return parsed._replace(scheme="https").geturl()
    if not parsed.scheme and parsed.netloc:
        return f"https:{value}"
    return None


def _choose_public_profile_photo_url(
    photo_url: str | None,
    *,
    auth_avatar_url: str | None = None,
    auth_picture_url: str | None = None,
) -> str | None:
    resolved = _normalize_public_profile_photo_url(photo_url)
    if resolved and resolved.startswith("/api/files/") and not _public_upload_exists(resolved):
        resolved = None

    return (
        resolved
        or _sanitize_public_avatar_url(auth_avatar_url)
        or _sanitize_public_avatar_url(auth_picture_url)
    )


async def list_teacher_course_priorities(limit: int | None = None) -> list[dict]:
    clauses = """
        WITH course_stats AS (
            SELECT
                created_by AS teacher_id,
                COUNT(*) AS total_courses,
                COUNT(*) FILTER (WHERE is_published = true) AS published_courses
            FROM app.courses
            GROUP BY created_by
        )
        SELECT
            prof.user_id AS teacher_id,
            prof.display_name,
            prof.email,
            prof.photo_url,
            COALESCE(pr.priority, 100) AS priority,
            pr.notes,
            pr.updated_at,
            pr.updated_by,
            upd.display_name AS updated_by_name,
            COALESCE(stats.total_courses, 0) AS total_courses,
            COALESCE(stats.published_courses, 0) AS published_courses
        FROM app.profiles prof
        LEFT JOIN app.course_display_priorities pr
          ON pr.teacher_id = prof.user_id
        LEFT JOIN app.profiles upd
          ON upd.user_id = pr.updated_by
        LEFT JOIN course_stats stats
          ON stats.teacher_id = prof.user_id
        WHERE prof.role_v2 = 'teacher' OR prof.is_admin = true
        ORDER BY COALESCE(pr.priority, 1000), lower(COALESCE(prof.display_name, prof.email))
    """
    params: tuple = ()
    if limit is not None:
        clauses += " LIMIT %s"
        params = (limit,)

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(clauses, params)
            rows = await cur.fetchall()
            return rows


async def upsert_teacher_course_priority(
    *,
    teacher_id: str,
    priority: int,
    updated_by: str | None,
    notes: str | None = None,
) -> dict:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.course_display_priorities (
                    teacher_id,
                    priority,
                    notes,
                    updated_by
                )
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (teacher_id) DO UPDATE
                  SET priority = excluded.priority,
                      notes = COALESCE(excluded.notes, app.course_display_priorities.notes),
                      updated_by = excluded.updated_by,
                      updated_at = now()
                RETURNING teacher_id, priority, notes, updated_at, updated_by
                """,
                (teacher_id, priority, notes, updated_by),
            )
            row = await _fetchone(cur)
            await conn.commit()
            return row or {}


async def delete_teacher_course_priority(teacher_id: str) -> None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.course_display_priorities WHERE teacher_id = %s",
                (teacher_id,),
            )
            await conn.commit()


async def get_teacher_course_priority(teacher_id: str) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH course_stats AS (
                    SELECT
                        created_by AS teacher_id,
                        COUNT(*) AS total_courses,
                        COUNT(*) FILTER (WHERE is_published = true) AS published_courses
                    FROM app.courses
                    GROUP BY created_by
                )
                SELECT
                    prof.user_id AS teacher_id,
                    prof.display_name,
                    prof.email,
                    prof.photo_url,
                    COALESCE(pr.priority, 100) AS priority,
                    pr.notes,
                    pr.updated_at,
                    pr.updated_by,
                    upd.display_name AS updated_by_name,
                    COALESCE(stats.total_courses, 0) AS total_courses,
                    COALESCE(stats.published_courses, 0) AS published_courses
                FROM app.profiles prof
                LEFT JOIN app.course_display_priorities pr
                  ON pr.teacher_id = prof.user_id
                LEFT JOIN app.profiles upd
                  ON upd.user_id = pr.updated_by
                LEFT JOIN course_stats stats
                  ON stats.teacher_id = prof.user_id
                WHERE (prof.role_v2 = 'teacher' OR prof.is_admin = true)
                  AND prof.user_id = %s
                """,
                (teacher_id,),
            )
            return await _fetchone(cur)


async def fetch_admin_metrics() -> dict:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT
                    (SELECT COUNT(*) FROM app.profiles) AS total_users,
                    (SELECT COUNT(*) FROM app.profiles
                        WHERE role_v2 = 'teacher' OR is_admin = true) AS total_teachers,
                    (SELECT COUNT(*) FROM app.courses) AS total_courses,
                    (SELECT COUNT(*) FROM app.courses WHERE is_published = true) AS published_courses,
                    (SELECT COUNT(*) FROM app.orders WHERE status = 'paid') AS paid_orders_total,
                    (SELECT COUNT(*) FROM app.orders
                        WHERE status = 'paid'
                          AND created_at >= now() - interval '30 days') AS paid_orders_30d,
                    (SELECT COUNT(DISTINCT user_id) FROM app.orders WHERE status = 'paid') AS paying_customers_total,
                    (SELECT COUNT(DISTINCT user_id) FROM app.orders
                        WHERE status = 'paid'
                          AND created_at >= now() - interval '30 days') AS paying_customers_30d,
                    COALESCE((
                        SELECT SUM(amount_cents) FROM app.payments WHERE status = 'paid'
                    ), 0) AS revenue_total_cents,
                    COALESCE((
                        SELECT SUM(amount_cents) FROM app.payments
                        WHERE status = 'paid'
                          AND created_at >= now() - interval '30 days'
                    ), 0) AS revenue_30d_cents,
                    (SELECT COUNT(*) FROM app.auth_events
                        WHERE event IN ('login_success', 'refresh_success')
                          AND occurred_at >= now() - interval '7 days') AS login_events_7d,
                    (SELECT COUNT(DISTINCT user_id) FROM app.auth_events
                        WHERE event IN ('login_success', 'refresh_success')
                          AND occurred_at >= now() - interval '7 days'
                          AND user_id IS NOT NULL) AS active_users_7d
            """
            )
            row = await _fetchone(cur) or {}
            keys = {
                "total_users",
                "total_teachers",
                "total_courses",
                "published_courses",
                "paid_orders_total",
                "paid_orders_30d",
                "paying_customers_total",
                "paying_customers_30d",
                "revenue_total_cents",
                "revenue_30d_cents",
                "login_events_7d",
                "active_users_7d",
            }
            return {key: int(row.get(key) or 0) for key in keys}


async def list_services(limit: int = 6) -> Iterable[dict]:
    services: list[dict] = []
    async for service in repo_list_services(status="active"):
        services.append(service)
        if len(services) >= limit:
            break
    return services


async def get_course(course_id: str | None = None, slug: str | None = None):
    return await courses_service.fetch_course(course_id=course_id, slug=slug)


async def list_modules(course_id: str) -> Iterable[dict]:
    return await courses_service.list_modules(course_id)


async def list_lessons(module_id: str) -> Iterable[dict]:
    return await courses_service.list_lessons(module_id)


async def list_course_lessons(course_id: str) -> Iterable[dict]:
    return await courses_service.list_course_lessons(course_id)


async def get_module_row(module_id: str):
    return await courses_service.fetch_module(module_id)


async def get_lesson(lesson_id: str):
    return await courses_service.fetch_lesson(lesson_id)


async def list_lesson_media(lesson_id: str) -> list[dict]:
    return await courses_service.list_lesson_media(lesson_id)


async def next_lesson_media_position(lesson_id: str) -> int:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT COALESCE(MAX(position), 0) + 1 AS next_position
                FROM app.lesson_media
                WHERE lesson_id = %s
                """,
                (lesson_id,),
            )
            row = await _fetchone(cur)
            if not row:
                return 1
            return int(row.get("next_position") or 1)


async def add_lesson_media_entry_with_position_retry(
    *,
    lesson_id: str,
    kind: str,
    storage_path: str | None,
    storage_bucket: str,
    media_id: str | None,
    media_asset_id: str | None = None,
    duration_seconds: int | None = None,
    max_retries: int = 10,
) -> dict | None:
    """Insert lesson media with a concurrency-safe position allocation.

    Position is derived from MAX(position)+1 and may collide under concurrent inserts.
    Guard with UNIQUE(lesson_id, position) and retry on UniqueViolation.
    """

    max_attempts = max(1, int(max_retries))
    for _ in range(max_attempts):
        position = await next_lesson_media_position(lesson_id)
        try:
            return await add_lesson_media_entry(
                lesson_id=lesson_id,
                kind=kind,
                storage_path=storage_path,
                storage_bucket=storage_bucket,
                position=position,
                media_id=media_id,
                media_asset_id=media_asset_id,
                duration_seconds=duration_seconds,
            )
        except errors.UniqueViolation:
            continue
    return None


async def add_lesson_media_entry(
    *,
    lesson_id: str,
    kind: str,
    storage_path: str | None,
    storage_bucket: str,
    position: int,
    media_id: str | None,
    media_asset_id: str | None = None,
    duration_seconds: int | None = None,
) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH inserted AS (
                  INSERT INTO app.lesson_media (
                    lesson_id,
                    kind,
                    storage_path,
                    storage_bucket,
                    media_id,
                    media_asset_id,
                    position,
                    duration_seconds
                  )
                  VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                  RETURNING
                    id,
                    lesson_id,
                    kind,
                    storage_path,
                    storage_bucket,
                    media_id,
                    media_asset_id,
                    position,
                    duration_seconds,
                    created_at
                )
                SELECT
                  i.id,
                  i.lesson_id,
                  i.kind,
                  coalesce(mo.storage_path, i.storage_path) AS storage_path,
                  coalesce(mo.storage_bucket, i.storage_bucket, 'lesson-media') AS storage_bucket,
                  i.media_id,
                  i.media_asset_id,
                  i.position,
                  i.duration_seconds,
                  mo.content_type,
                  mo.byte_size,
                  mo.original_name,
                  i.created_at
                FROM inserted i
                LEFT JOIN app.media_objects mo ON mo.id = i.media_id
                """,
                (
                    lesson_id,
                    kind,
                    storage_path,
                    storage_bucket,
                    media_id,
                    media_asset_id,
                    position,
                    duration_seconds,
                ),
            )
            row = await _fetchone(cur)
            await conn.commit()
            return row


async def delete_lesson_media_entry(media_id: str) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH deleted AS (
                  DELETE FROM app.lesson_media
                  WHERE id = %s
                  RETURNING id, lesson_id, storage_path, storage_bucket, media_id, media_asset_id
                ),
                usage AS (
                  SELECT
                    d.media_asset_id,
                    EXISTS(
                      SELECT 1
                      FROM app.lesson_media lm
                      WHERE lm.media_asset_id = d.media_asset_id
                        AND lm.id <> d.id
                    ) AS used_in_lessons,
                    EXISTS(
                      SELECT 1
                      FROM app.courses c
                      WHERE c.cover_media_id = d.media_asset_id
                    ) AS used_as_cover
                  FROM deleted d
                ),
                deleted_asset AS (
                  DELETE FROM app.media_assets ma
                  USING usage u
                  WHERE ma.id = u.media_asset_id
                    AND u.media_asset_id IS NOT NULL
                    AND NOT u.used_in_lessons
                    AND NOT u.used_as_cover
                  RETURNING ma.id
                )
                SELECT
                  d.id,
                  d.lesson_id,
                  coalesce(mo.storage_path, d.storage_path) AS storage_path,
                  coalesce(mo.storage_bucket, d.storage_bucket, 'lesson-media') AS storage_bucket,
                  d.media_id,
                  d.media_asset_id,
                  mo.content_type,
                  mo.byte_size,
                  mo.original_name,
                  EXISTS(SELECT 1 FROM deleted_asset) AS media_asset_deleted
                FROM deleted d
                LEFT JOIN app.media_objects mo ON mo.id = d.media_id
                """,
                (media_id,),
            )
            row = await _fetchone(cur)
            await conn.commit()
    if row and row.get("media_id"):
        await cleanup_media_object(row["media_id"])
    return row


async def reorder_media(lesson_id: str, ordered_ids: list[str]) -> None:
    if not ordered_ids:
        return
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            for index, media_id in enumerate(ordered_ids, start=1):
                await cur.execute(
                    "UPDATE app.lesson_media SET position = %s WHERE id = %s AND lesson_id = %s",
                    (index, media_id, lesson_id),
                )
            await conn.commit()


async def get_media(media_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT
              lm.id,
              lm.lesson_id,
              lm.kind,
              coalesce(mo.storage_path, lm.storage_path) AS storage_path,
              coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media') AS storage_bucket,
              lm.media_id,
              lm.media_asset_id,
              mo.content_type,
              mo.byte_size,
              mo.original_name
            FROM app.lesson_media lm
            LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
            WHERE lm.id = %s
            """,
            (media_id,),
        )
        return await _fetchone(cur)


async def is_course_owner(user_id: str, course_id: str) -> bool:
    return await courses_service.is_course_owner(user_id, course_id)


async def module_course_id(module_id: str) -> str | None:
    return await courses_service.get_module_course_id(module_id)


async def lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    return await courses_service.lesson_course_ids(lesson_id)


async def add_module(course_id: str, title: str, position: int) -> dict | None:
    payload = {
        "title": title,
        "position": position,
    }
    return await courses_service.upsert_module(course_id, payload)


async def update_module(module_id: str, patch: dict) -> dict | None:
    if not patch:
        return await get_module_row(module_id)
    course_id = await courses_service.get_module_course_id(module_id)
    if not course_id:
        return None
    payload: dict[str, Any] = {"id": module_id}
    payload.update(patch)
    return await courses_service.upsert_module(course_id, payload)


async def delete_module(module_id: str) -> bool:
    return await courses_service.delete_module(module_id)


async def upsert_lesson(
    *,
    lesson_id: str | None,
    course_id: str,
    title: str | None = None,
    content_markdown: str | None = None,
    position: int | None = None,
    is_intro: bool | None = None,
) -> dict | None:
    payload: dict[str, Any] = {}
    if lesson_id is not None:
        payload["id"] = lesson_id
    if title is not None:
        payload["title"] = title
    if content_markdown is not None:
        payload["content_markdown"] = content_markdown
    if position is not None:
        payload["position"] = position
    if is_intro is not None:
        payload["is_intro"] = is_intro

    if lesson_id is not None and not payload.keys() - {"id"}:
        return await get_lesson(lesson_id)

    return await courses_service.upsert_lesson(course_id, payload)


async def delete_lesson(lesson_id: str) -> bool:
    return await courses_service.delete_lesson(lesson_id)


async def set_lesson_intro(lesson_id: str, is_intro: bool) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    UPDATE app.lessons
                    SET is_intro = %s, updated_at = now()
                    WHERE id = %s
                    RETURNING id, course_id, title, position, is_intro
                    """,
                    (is_intro, lesson_id),
                )
            except errors.UndefinedColumn:
                await conn.rollback()
                await cur.execute(
                    """
                    UPDATE app.lessons
                    SET is_intro = %s
                    WHERE id = %s
                    RETURNING id, module_id, title, position, is_intro
                    """,
                    (is_intro, lesson_id),
                )
            row = await _fetchone(cur)
            await conn.commit()
            return row


async def get_profile(user_id: str):
    return await repo_get_profile(user_id)


async def update_profile(
    user_id: str,
    *,
    display_name: str | None = None,
    bio: str | None = None,
    photo_url: str | None = None,
    avatar_media_id: str | None = None,
) -> dict | None:
    return await repo_update_profile(
        user_id,
        display_name=display_name,
        bio=bio,
        photo_url=photo_url,
        avatar_media_id=avatar_media_id,
    )


async def free_course_limit() -> int:
    return await courses_service.get_free_course_limit()


async def free_consumed_count(user_id: str) -> int:
    return await courses_service.free_consumed_count(user_id)


async def is_enrolled(user_id: str, course_id: str) -> bool:
    return await courses_service.is_user_enrolled(user_id, course_id)


async def enroll_free_intro(user_id: str, course_id: str) -> dict:
    return await courses_service.enroll_free_intro(user_id, course_id)


async def list_my_courses(user_id: str) -> Iterable[dict]:
    return await courses_service.list_my_courses(user_id)


async def latest_order_for_course(user_id: str, course_id: str):
    return await courses_service.latest_order_for_course(user_id, course_id)


async def course_access_snapshot(user_id: str, course_id: str) -> dict:
    return await courses_service.course_access_snapshot(user_id, course_id)


async def set_order_checkout_reference(
    order_id: str, *, checkout_id: str, payment_intent: str | None
) -> dict | None:
    return await repo_set_order_checkout_reference(
        order_id=order_id,
        checkout_id=checkout_id,
        payment_intent=payment_intent,
    )


async def get_user_email(user_id: str) -> str | None:
    async with get_conn() as cur:
        await cur.execute(
            "SELECT email FROM app.profiles WHERE user_id = %s LIMIT 1",
            (user_id,),
        )
        row = await _fetchone(cur)
    if row and row.get("email"):
        return row.get("email")

    async with get_conn() as cur:
        await cur.execute(
            "SELECT email FROM auth.users WHERE id = %s LIMIT 1",
            (user_id,),
        )
        row = await _fetchone(cur)
    if row and row.get("email"):
        return row.get("email")
    return None


async def stripe_customer_id_for_user(user_id: str) -> str | None:
    async with get_conn() as cur:
        await cur.execute(
            "SELECT customer_id FROM app.stripe_customers WHERE user_id = %s",
            (user_id,),
        )
        row = await _fetchone(cur)
    return row.get("customer_id") if row else None


async def save_stripe_customer_id(user_id: str, customer_id: str) -> None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.stripe_customers (user_id, customer_id, created_at, updated_at)
                VALUES (%s, %s, now(), now())
                ON CONFLICT (user_id) DO UPDATE
                  SET customer_id = excluded.customer_id,
                      updated_at = now()
                """,
                (user_id, customer_id),
            )
            await conn.commit()


async def list_subscription_plans() -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, name, price_cents, interval, is_active
            FROM public.subscription_plans
            WHERE is_active = true
            ORDER BY price_cents, name
            """
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def active_subscription_for(user_id: str) -> dict | None:
    async with get_conn() as cur:
        try:
            await cur.execute(
                """
                SELECT id, user_id, subscription_id, status, customer_id, price_id, created_at, updated_at
                FROM app.subscriptions
                WHERE user_id = %s
                ORDER BY updated_at DESC
                LIMIT 1
                """,
                (user_id,),
            )
        except errors.UndefinedTable:
            return None
        row = await _fetchone(cur)
    return dict(row) if row else None


async def preview_coupon(plan_id: str, code: str | None) -> dict:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, price_cents
            FROM public.subscription_plans
            WHERE id = %s AND is_active = true
            LIMIT 1
            """,
            (plan_id,),
        )
        plan = await _fetchone(cur)
    if not plan:
        return {"valid": False, "pay_amount_cents": 0}

    price_cents = int(plan.get("price_cents") or 0)
    normalized_code = (code or "").strip()
    if not normalized_code:
        return {"valid": False, "pay_amount_cents": price_cents}

    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT code, max_redemptions, redeemed_count
            FROM public.coupons
            WHERE code = %s
              AND (expires_at IS NULL OR expires_at > now())
              AND (plan_id IS NULL OR plan_id = %s)
            LIMIT 1
            """,
            (normalized_code, plan_id),
        )
        coupon = await _fetchone(cur)
    if not coupon:
        return {"valid": False, "pay_amount_cents": price_cents}

    max_redemptions = coupon.get("max_redemptions")
    redeemed_count = int(coupon.get("redeemed_count") or 0)
    if max_redemptions is not None and redeemed_count >= int(max_redemptions):
        return {"valid": False, "pay_amount_cents": price_cents}

    return {"valid": True, "pay_amount_cents": 0}


async def redeem_coupon(
    user_id: str, plan_id: str, code: str
) -> tuple[bool, str | None, dict | None]:
    normalized_code = code.strip()
    if not normalized_code:
        return False, "invalid_coupon", None

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT id, name, interval
                FROM public.subscription_plans
                WHERE id = %s AND is_active = true
                LIMIT 1
                """,
                (plan_id,),
            )
            plan = await _fetchone(cur)
            if not plan:
                await conn.rollback()
                return False, "invalid_plan", None

            await cur.execute(
                """
                SELECT code, plan_id, grants, max_redemptions, redeemed_count, expires_at
                FROM public.coupons
                WHERE code = %s
                  AND (expires_at IS NULL OR expires_at > now())
                  AND (plan_id IS NULL OR plan_id = %s)
                FOR UPDATE
                LIMIT 1
                """,
                (normalized_code, plan_id),
            )
            coupon = await _fetchone(cur)
            if not coupon:
                await conn.rollback()
                return False, "invalid_coupon", None

            max_redemptions = coupon.get("max_redemptions")
            redeemed_count = int(coupon.get("redeemed_count") or 0)
            if max_redemptions is not None and redeemed_count >= int(max_redemptions):
                await conn.rollback()
                return False, "coupon_redeemed", None

            await cur.execute(
                "UPDATE public.coupons SET redeemed_count = redeemed_count + 1 WHERE code = %s",
                (normalized_code,),
            )

            interval_text = (plan.get("interval") or "month").lower()
            if interval_text.startswith("year"):
                period_end = datetime.now(timezone.utc) + timedelta(days=365)
            else:
                period_end = datetime.now(timezone.utc) + timedelta(days=30)

            await cur.execute(
                """
                INSERT INTO public.subscriptions (user_id, plan_id, status, current_period_end, created_at)
                VALUES (%s, %s, 'active', %s, now())
                RETURNING id, user_id, plan_id, status, current_period_end, created_at
                """,
                (user_id, plan_id, period_end),
            )
            subscription_row = await _fetchone(cur)

            grants = coupon.get("grants") or {}
            if isinstance(grants, Jsonb):
                grants = grants.obj
            if isinstance(grants, str):
                try:
                    grants = json.loads(grants)
                except ValueError:
                    grants = {}
            if not isinstance(grants, dict):
                grants = {}

            role_target = grants.get("role")
            teacher_grant = grants.get("teacher") in (True, "true", "True", 1, "1")
            raw_areas = grants.get("certified_areas") if grants else []
            certified_areas = []
            if isinstance(raw_areas, list):
                certified_areas = [str(area) for area in raw_areas if str(area).strip()]

            if role_target:
                await cur.execute(
                    "SELECT raw_app_meta_data FROM auth.users WHERE id = %s FOR UPDATE",
                    (user_id,),
                )
                user_row = await _fetchone(cur)
                raw_meta = user_row.get("raw_app_meta_data") if user_row else {}
                if isinstance(raw_meta, str):
                    try:
                        raw_meta = json.loads(raw_meta)
                    except ValueError:
                        raw_meta = {}
                if isinstance(raw_meta, dict):
                    raw_meta["role"] = role_target
                else:
                    raw_meta = {"role": role_target}
                await cur.execute(
                    "UPDATE auth.users SET raw_app_meta_data = %s WHERE id = %s",
                    (Jsonb(raw_meta), user_id),
                )

            if teacher_grant:
                await cur.execute(
                    """
                    INSERT INTO app.teacher_permissions (
                      profile_id,
                      can_edit_courses,
                      can_publish,
                      granted_by,
                      granted_at
                    )
                    VALUES (%s, true, true, %s, now())
                    ON CONFLICT (profile_id) DO UPDATE
                      SET can_edit_courses = true,
                          can_publish = true,
                          granted_at = COALESCE(app.teacher_permissions.granted_at, excluded.granted_at)
                    """,
                    (user_id, user_id),
                )

            for area in certified_areas:
                await cur.execute(
                    """
                    INSERT INTO public.user_certifications (user_id, area)
                    VALUES (%s, %s)
                    ON CONFLICT (user_id, area) DO NOTHING
                    """,
                    (user_id, area),
                )

            await conn.commit()
            subscription = dict(subscription_row) if subscription_row else None
            return True, None, subscription


async def start_course_order(
    user_id: str,
    course_id: str,
    amount_cents: int,
    currency: str,
    metadata: dict | None = None,
) -> dict:
    return await repo_create_order(
        user_id=user_id,
        service_id=None,
        course_id=course_id,
        amount_cents=amount_cents,
        currency=currency or "sek",
        metadata=metadata,
    )


async def start_service_order(
    user_id: str,
    service_id: str,
    amount_cents: int,
    currency: str,
    metadata: dict | None = None,
) -> dict:
    return await repo_create_order(
        user_id=user_id,
        service_id=service_id,
        course_id=None,
        amount_cents=amount_cents,
        currency=currency or "sek",
        metadata=metadata,
    )


async def get_order(order_id: str, user_id: str) -> dict | None:
    return await repo_get_user_order(order_id, user_id)


async def get_order_by_id(order_id: str) -> dict | None:
    return await repo_get_order(order_id)


async def mark_order_paid(
    order_id: str,
    *,
    payment_intent: str | None,
    checkout_id: str | None,
) -> dict | None:
    order = await repo_mark_order_paid(
        order_id,
        payment_intent=payment_intent,
        checkout_id=checkout_id,
    )
    if not order:
        return None

    course_id = order.get("course_id")
    user_id = order.get("user_id")
    if course_id and user_id:
        async with pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    INSERT INTO app.enrollments (user_id, course_id, source)
                    VALUES (%s, %s, 'purchase')
                    ON CONFLICT (user_id, course_id) DO NOTHING
                    """,
                    (user_id, course_id),
                )
                await conn.commit()

    return order


async def upsert_subscription_record(
    *,
    user_id: str,
    subscription_id: str,
    status: str,
    customer_id: str | None = None,
    price_id: str | None = None,
) -> dict:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.subscriptions (
                      user_id,
                      subscription_id,
                      status,
                      customer_id,
                      price_id,
                      created_at,
                      updated_at
                    )
                    VALUES (%s, %s, %s, %s, %s, now(), now())
                    ON CONFLICT (subscription_id) DO UPDATE
                      SET user_id = excluded.user_id,
                          status = excluded.status,
                          customer_id = COALESCE(excluded.customer_id, app.subscriptions.customer_id),
                          price_id = COALESCE(excluded.price_id, app.subscriptions.price_id),
                          updated_at = now()
                    RETURNING
                      id,
                      user_id,
                      subscription_id,
                      status,
                      customer_id,
                      price_id,
                      created_at,
                      updated_at
                    """,
                    (user_id, subscription_id, status, customer_id, price_id),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                logger.warning(
                    "app.subscriptions is missing; skipping upsert_subscription_record for %s", subscription_id
                )
                return {
                    "user_id": user_id,
                    "subscription_id": subscription_id,
                    "status": status,
                    "customer_id": customer_id,
                    "price_id": price_id,
                }
            row = await _fetchone(cur)
            await conn.commit()
            return dict(row)


async def update_subscription_status(
    subscription_id: str,
    *,
    status: str,
    customer_id: str | None = None,
    price_id: str | None = None,
) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    UPDATE app.subscriptions
                       SET status = %s,
                           customer_id = COALESCE(%s, customer_id),
                           price_id = COALESCE(%s, price_id),
                           updated_at = now()
                     WHERE subscription_id = %s
                     RETURNING id, user_id, subscription_id, status, customer_id, price_id, created_at, updated_at
                    """,
                    (status, customer_id, price_id, subscription_id),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                logger.warning(
                    "app.subscriptions is missing; cannot update subscription_id=%s", subscription_id
                )
                return None
            row = await _fetchone(cur)
            await conn.commit()
            return dict(row) if row else None


async def get_subscription_record(subscription_id: str) -> dict | None:
    async with get_conn() as cur:
        try:
            await cur.execute(
                """
                SELECT id, user_id, subscription_id, status, customer_id, price_id
                FROM app.subscriptions
                WHERE subscription_id = %s
                LIMIT 1
                """,
                (subscription_id,),
            )
        except errors.UndefinedTable:
            logger.warning("app.subscriptions is missing; get_subscription_record skipped for %s", subscription_id)
            return None
        row = await _fetchone(cur)
    return dict(row) if row else None


async def claim_purchase_with_token(user_id: str, token: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT token, course_id, purchase_id
                FROM app.guest_claim_tokens
                WHERE token = %s
                  AND used = false
                  AND expires_at > now()
                FOR UPDATE
                LIMIT 1
                """,
                (token,),
            )
            claim_row = await _fetchone(cur)
            if not claim_row:
                await conn.rollback()
                return False

            course_id = claim_row.get("course_id")
            purchase_id = claim_row.get("purchase_id")

            await cur.execute(
                "UPDATE app.purchases SET user_id = %s WHERE id = %s",
                (user_id, purchase_id),
            )
            await cur.execute(
                "UPDATE app.guest_claim_tokens SET used = true WHERE token = %s",
                (token,),
            )
            if course_id:
                await cur.execute(
                    """
                    INSERT INTO app.enrollments (user_id, course_id, source)
                    VALUES (%s, %s, 'purchase')
                    ON CONFLICT (user_id, course_id) DO NOTHING
                    """,
                    (user_id, course_id),
                )

            await conn.commit()
            return True


async def course_quiz_info(course_id: str, user_id: str | None):
    return await courses_service.course_quiz_info(course_id, user_id)


async def quiz_questions(quiz_id: str) -> Iterable[dict]:
    return await courses_service.quiz_questions(quiz_id)


async def submit_quiz(quiz_id: str, user_id: str, answers: dict):
    return await courses_service.submit_quiz(quiz_id, user_id, answers)


async def ensure_quiz_for_user(course_id: str, user_id: str) -> dict | None:
    if not await is_course_owner(user_id, course_id):
        return None
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    "SELECT id, course_id, title, pass_score, created_at "
                    "FROM app.course_quizzes WHERE course_id = %s LIMIT 1",
                    (course_id,),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return None
            row = await _fetchone(cur)
            if row:
                return row
            await cur.execute(
                """
                INSERT INTO app.course_quizzes (course_id, title, pass_score, created_by)
                VALUES (%s, 'Quiz', 80, %s)
                RETURNING id, course_id, title, pass_score, created_at
                """,
                (course_id, user_id),
            )
            new_row = await _fetchone(cur)
            await conn.commit()
            return new_row


async def quiz_belongs_to_user(quiz_id: str, user_id: str) -> bool:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT cq.course_id, c.created_by
            FROM app.course_quizzes cq
            JOIN app.courses c ON c.id = cq.course_id
            WHERE cq.id = %s
            """,
            (quiz_id,),
        )
        row = await _fetchone(cur)
    if not row:
        return False
    return row.get("created_by") == user_id


async def upsert_quiz_question(quiz_id: str, data: dict) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            if data.get("id"):
                fields = []
                params = []
                for key in ("position", "kind", "prompt", "options", "correct"):
                    if key in data:
                        fields.append(f"{key} = %s")
                        value = data[key]
                        if key == "options" and value is not None:
                            value = Jsonb(value)
                        params.append(value)
                if not fields:
                    await cur.execute(
                        "SELECT id, quiz_id, position, kind, prompt, options, correct "
                        "FROM app.quiz_questions WHERE id = %s",
                        (data["id"],),
                    )
                else:
                    params.extend([data["id"], quiz_id])
                    await cur.execute(
                        """
                        UPDATE app.quiz_questions
                        SET {set_clause}, updated_at = now()
                        WHERE id = %s AND quiz_id = %s
                        RETURNING id, quiz_id, position, kind, prompt, options, correct
                        """.format(set_clause=", ".join(fields)),
                        params,
                    )
            else:
                await cur.execute(
                    """
                    INSERT INTO app.quiz_questions (quiz_id, position, kind, prompt, options, correct)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    RETURNING id, quiz_id, position, kind, prompt, options, correct
                    """,
                    (
                        quiz_id,
                        data.get("position", 0),
                        data.get("kind", "single"),
                        data.get("prompt"),
                        Jsonb(data.get("options") or {}),
                        data.get("correct"),
                    ),
                )
            row = await _fetchone(cur)
            await conn.commit()
            return row


async def delete_quiz_question(question_id: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.quiz_questions WHERE id = %s",
                (question_id,),
            )
            deleted = cur.rowcount > 0
            await conn.commit()
            return deleted


def _as_string_list(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    if isinstance(value, str):
        return [value]
    return []


async def list_community_posts(limit: int = 50) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT p.id,
                   p.author_id,
                   p.content,
                   p.media_paths,
                   p.created_at,
                   prof.display_name,
                   prof.photo_url,
                   prof.bio
            FROM app.posts p
            LEFT JOIN app.profiles prof ON prof.user_id = p.author_id
            ORDER BY p.created_at DESC
            LIMIT %s
            """,
            (limit,),
        )
        rows = await cur.fetchall()

    items: list[dict] = []
    for row in rows:
        media_paths = _as_string_list(row.get("media_paths"))
        profile = None
        if row.get("display_name") is not None or row.get("photo_url") is not None:
            profile = {
                "user_id": row.get("author_id"),
                "display_name": row.get("display_name"),
                "photo_url": row.get("photo_url"),
                "bio": row.get("bio"),
            }
        items.append(
            {
                "id": row.get("id"),
                "author_id": row.get("author_id"),
                "content": row.get("content"),
                "media_paths": media_paths,
                "created_at": row.get("created_at"),
                "profile": profile,
            }
        )
    return items


async def create_community_post(
    author_id: str,
    content: str,
    media_paths: list[str] | None = None,
) -> dict:
    payload = Jsonb(media_paths or []) if media_paths else Jsonb([])
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH inserted AS (
                    INSERT INTO app.posts (author_id, content, media_paths)
                    VALUES (%s, %s, %s)
                    RETURNING id, author_id, content, media_paths, created_at
                )
                SELECT i.id,
                       i.author_id,
                       i.content,
                       i.media_paths,
                       i.created_at,
                       prof.display_name,
                       prof.photo_url,
                       prof.bio
                FROM inserted i
                LEFT JOIN app.profiles prof ON prof.user_id = i.author_id
                """,
                (author_id, content, payload),
            )
            row = await _fetchone(cur)
            await conn.commit()

    media = _as_string_list(row.get("media_paths")) if row else []
    profile = None
    if row and (
        row.get("display_name") is not None or row.get("photo_url") is not None
    ):
        profile = {
            "user_id": row.get("author_id"),
            "display_name": row.get("display_name"),
            "photo_url": row.get("photo_url"),
            "bio": row.get("bio"),
        }
    return {
        "id": row.get("id") if row else None,
        "author_id": author_id,
        "content": content,
        "media_paths": media,
        "created_at": row.get("created_at") if row else None,
        "profile": profile,
    }


async def list_teacher_directory(limit: int = 100) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT td.user_id,
                   td.headline,
                   td.specialties,
                   td.rating,
                   td.created_at,
                   prof.display_name,
                   prof.photo_url,
                   prof.bio,
                   u.raw_user_meta_data->>'avatar_url' AS auth_avatar_url,
                   u.raw_user_meta_data->>'picture' AS auth_picture_url,
                   COALESCE(cert.count, 0) AS verified_certificates
            FROM app.teacher_directory td
            LEFT JOIN app.profiles prof ON prof.user_id = td.user_id
            LEFT JOIN auth.users u ON u.id = td.user_id
            LEFT JOIN (
                SELECT user_id, COUNT(*) FILTER (WHERE status = 'verified') AS count
                FROM app.certificates
                GROUP BY user_id
            ) cert ON cert.user_id = td.user_id
            ORDER BY td.created_at DESC
            LIMIT %s
            """,
            (limit,),
        )
        rows = await cur.fetchall()

    items: list[dict] = []
    for row in rows:
        specialties = _as_string_list(row.get("specialties"))
        rating = row.get("rating")
        if rating is not None:
            rating = float(rating)
        profile = None
        if row.get("display_name") is not None or row.get("photo_url") is not None:
            profile = {
                "user_id": row.get("user_id"),
                "display_name": row.get("display_name"),
                "photo_url": _choose_public_profile_photo_url(
                    row.get("photo_url"),
                    auth_avatar_url=row.get("auth_avatar_url"),
                    auth_picture_url=row.get("auth_picture_url"),
                ),
                "bio": row.get("bio"),
            }
        items.append(
            {
                "user_id": row.get("user_id"),
                "headline": row.get("headline"),
                "specialties": specialties,
                "rating": rating,
                "created_at": row.get("created_at"),
                "profile": profile,
                "verified_certificates": int(row.get("verified_certificates") or 0),
            }
        )
    return items


async def get_teacher_directory_item(user_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT td.user_id,
                   td.headline,
                   td.specialties,
                   td.rating,
                   td.created_at,
                   prof.display_name,
                   prof.photo_url,
                   prof.bio,
                   u.raw_user_meta_data->>'avatar_url' AS auth_avatar_url,
                   u.raw_user_meta_data->>'picture' AS auth_picture_url,
                   COALESCE(cert.count, 0) AS verified_certificates
            FROM app.teacher_directory td
            LEFT JOIN app.profiles prof ON prof.user_id = td.user_id
            LEFT JOIN auth.users u ON u.id = td.user_id
            LEFT JOIN (
                SELECT user_id, COUNT(*) FILTER (WHERE status = 'verified') AS count
                FROM app.certificates
                GROUP BY user_id
            ) cert ON cert.user_id = td.user_id
            WHERE td.user_id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = await _fetchone(cur)

        if not row:
            await cur.execute(
                """
                SELECT prof.user_id,
                       prof.display_name,
                       prof.photo_url,
                       prof.bio,
                       prof.created_at,
                       u.raw_user_meta_data->>'avatar_url' AS auth_avatar_url,
                       u.raw_user_meta_data->>'picture' AS auth_picture_url
                FROM app.profiles prof
                LEFT JOIN auth.users u ON u.id = prof.user_id
                WHERE prof.user_id = %s
                  AND (prof.role_v2 = 'teacher' OR prof.is_admin = true)
                  AND lower(prof.email) = lower(%s)
                LIMIT 1
                """,
                (user_id, "avelibooks@gmail.com"),
            )
            fallback_profile = await _fetchone(cur)
        else:
            fallback_profile = None

    if not row and not fallback_profile:
        return None

    if not row and fallback_profile:
        profile = {
            "user_id": fallback_profile.get("user_id"),
            "display_name": fallback_profile.get("display_name"),
            "photo_url": _choose_public_profile_photo_url(
                fallback_profile.get("photo_url"),
                auth_avatar_url=fallback_profile.get("auth_avatar_url"),
                auth_picture_url=fallback_profile.get("auth_picture_url"),
            ),
            "bio": fallback_profile.get("bio"),
        }
        return {
            "user_id": fallback_profile.get("user_id"),
            "headline": "",
            "specialties": [],
            "rating": None,
            "created_at": fallback_profile.get("created_at"),
            "profile": profile,
            "verified_certificates": 0,
        }

    specialties = _as_string_list(row.get("specialties"))
    rating = row.get("rating")
    if rating is not None:
        rating = float(rating)
    profile = None
    if row.get("display_name") is not None or row.get("photo_url") is not None:
        profile = {
            "user_id": row.get("user_id"),
            "display_name": row.get("display_name"),
            "photo_url": _choose_public_profile_photo_url(
                row.get("photo_url"),
                auth_avatar_url=row.get("auth_avatar_url"),
                auth_picture_url=row.get("auth_picture_url"),
            ),
            "bio": row.get("bio"),
        }
    return {
        "user_id": row.get("user_id"),
        "headline": row.get("headline"),
        "specialties": specialties,
        "rating": rating,
        "created_at": row.get("created_at"),
        "profile": profile,
        "verified_certificates": int(row.get("verified_certificates") or 0),
    }


async def list_teacher_services(user_id: str) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, title, description, price_cents, duration_min,
                   certified_area, active, created_at
            FROM app.services
            WHERE provider_id = %s
            ORDER BY created_at DESC
            """,
            (user_id,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def service_detail(service_id: str) -> tuple[dict | None, dict | None]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT
                s.id,
                s.provider_id,
                s.title,
                s.description,
                s.price_cents,
                s.duration_min,
                s.certified_area,
                s.active,
                s.created_at,
                p.user_id AS provider_user_id,
                p.display_name AS provider_display_name,
                p.photo_url AS provider_photo_url,
                p.bio AS provider_bio
            FROM app.services s
            LEFT JOIN app.profiles p ON p.user_id = s.provider_id
            WHERE s.id = %s
            LIMIT 1
            """,
            (service_id,),
        )
        row = await _fetchone(cur)
    if not row:
        return None, None
    row_dict = dict(row)
    service_keys = {
        "id",
        "provider_id",
        "title",
        "description",
        "price_cents",
        "duration_min",
        "certified_area",
        "active",
        "created_at",
    }
    service = {key: row_dict.get(key) for key in service_keys if key in row_dict}
    provider = None
    provider_user_id = row_dict.get("provider_user_id")
    if provider_user_id:
        provider = {
            "user_id": provider_user_id,
            "display_name": row_dict.get("provider_display_name"),
            "photo_url": row_dict.get("provider_photo_url"),
            "bio": row_dict.get("provider_bio"),
        }
    return service, provider


async def list_tarot_requests_for_user(user_id: str) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, requester_id, reader_id, question, status,
                   deliverable_url, created_at, updated_at
            FROM app.tarot_requests
            WHERE requester_id = %s
            ORDER BY created_at DESC
            """,
            (user_id,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def create_tarot_request(user_id: str, question: str) -> dict:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.tarot_requests (requester_id, question)
                VALUES (%s, %s)
                RETURNING id, requester_id, reader_id, question, status,
                          deliverable_url, created_at, updated_at
                """,
                (user_id, question),
            )
            row = await _fetchone(cur)
            await conn.commit()
            return dict(row)


async def list_teacher_meditations(user_id: str) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, teacher_id, title, description, audio_path,
                   duration_seconds, is_public, created_at
            FROM app.meditations
            WHERE teacher_id = %s
            ORDER BY created_at DESC
            """,
            (user_id,),
        )
        rows = await cur.fetchall()
    items: list[dict] = []
    for row in rows:
        item = dict(row)
        item["audio_url"] = _build_audio_url(row.get("audio_path"))
        items.append(item)
    return items


async def verified_certificate_counts(user_ids: list[str]) -> dict[str, int]:
    if not user_ids:
        return {}
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT user_id, COUNT(*) AS count
            FROM app.certificates
            WHERE status = 'verified' AND user_id = ANY(%s)
            GROUP BY user_id
            """,
            (user_ids,),
        )
        rows = await cur.fetchall()
    return {row["user_id"]: int(row["count"]) for row in rows}


async def list_reviews_for_service(service_id: str) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, service_id, reviewer_id, rating, comment, created_at
            FROM app.reviews
            WHERE service_id = %s
            ORDER BY created_at DESC
            """,
            (service_id,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def add_review_for_service(
    service_id: str,
    reviewer_id: str,
    rating: int,
    comment: str | None = None,
) -> dict:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.reviews (service_id, reviewer_id, rating, comment)
                VALUES (%s, %s, %s, %s)
                RETURNING id, service_id, reviewer_id, rating, comment, created_at
                """,
                (service_id, reviewer_id, int(rating), comment),
            )
            row = await _fetchone(cur)
            await conn.commit()
    return dict(row)


_PUBLIC_MESSAGE_CHANNELS = {"global"}


def _authorize_message_channel(
    channel: str, user_id: str | None
) -> tuple[str, str | None]:
    channel_value = (channel or "").strip()
    if not channel_value:
        raise ValueError("Channel is required")

    user_id_str = str(user_id) if user_id is not None else None

    if channel_value in _PUBLIC_MESSAGE_CHANNELS or channel_value.startswith("public:"):
        if not user_id_str:
            raise PermissionError("Authentication required for this channel")
        return "public", None

    if channel_value.startswith("dm:"):
        parts = channel_value.split(":")
        if len(parts) != 3:
            raise ValueError("Invalid dm channel format")
        participant_a, participant_b = parts[1], parts[2]
        if not participant_a or not participant_b:
            raise ValueError("Invalid dm channel participants")
        if user_id_str not in {participant_a, participant_b}:
            raise PermissionError("You are not part of this conversation")
        other = participant_b if user_id_str == participant_a else participant_a
        return "dm", other

    raise PermissionError("Channel is not accessible")


async def list_channel_messages(channel: str, viewer_id: str) -> list[dict]:
    _authorize_message_channel(channel, viewer_id)
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, channel, sender_id, content, created_at
            FROM app.messages
            WHERE channel = %s AND sender_id IS NOT NULL
            ORDER BY created_at
            """,
            (channel,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def create_channel_message(channel: str, sender_id: str, content: str) -> dict:
    _, recipient_id = _authorize_message_channel(channel, sender_id)
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.messages (channel, sender_id, recipient_id, content)
                VALUES (%s, %s, %s, %s)
                RETURNING id, channel, sender_id, content, created_at
                """,
                (channel, sender_id, recipient_id, content),
            )
            row = await _fetchone(cur)
            await conn.commit()
    return dict(row)


def _build_audio_url(audio_path: str | None) -> str | None:
    if not audio_path:
        return None
    sanitized = audio_path.lstrip("/")
    return f"/community/meditations/audio?path={quote(sanitized)}"


async def list_public_meditations(limit: int = 100) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, teacher_id, title, description, audio_path,
                   duration_seconds, is_public, created_at
            FROM app.meditations
            WHERE is_public = true
            ORDER BY created_at DESC
            LIMIT %s
            """,
            (limit,),
        )
        rows = await cur.fetchall()

    items: list[dict] = []
    for row in rows:
        item = dict(row)
        item["audio_url"] = _build_audio_url(row.get("audio_path"))
        items.append(item)
    return items


async def get_profile_row(user_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT user_id, email, display_name, bio, photo_url, role_v2, is_admin
            FROM app.profiles
            WHERE user_id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = await _fetchone(cur)
    return dict(row) if row else None


async def is_admin_user(user_id: str) -> bool:
    profile = await get_profile_row(user_id)
    if not profile:
        return False
    if profile.get("is_admin"):
        return True
    role = (profile.get("role_v2") or "").lower()
    return role == "admin"


async def list_teacher_applications() -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT c.id,
                   c.user_id,
                   c.title,
                   c.status,
                   c.notes,
                   c.evidence_url,
                   c.created_at,
                   c.updated_at,
                   prof.display_name,
                   prof.email,
                   prof.role_v2,
                   ta.approved_by,
                   ta.approved_at
            FROM app.certificates c
            LEFT JOIN app.profiles prof ON prof.user_id = c.user_id
            LEFT JOIN app.teacher_approvals ta ON ta.user_id = c.user_id
            WHERE lower(c.title) = lower(%s)
            ORDER BY c.created_at DESC
            """,
            ("Läraransökan",),
        )
        rows = await cur.fetchall()

    items: list[dict] = []
    for row in rows:
        item = dict(row)
        approval = None
        if row.get("approved_at") is not None or row.get("approved_by") is not None:
            approval = {
                "approved_by": row.get("approved_by"),
                "approved_at": row.get("approved_at"),
            }
        if approval:
            item["approval"] = approval
        items.append(item)
    return items


async def list_recent_certificates(limit: int = 200) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, user_id, title, status, notes, evidence_url,
                   created_at, updated_at
            FROM app.certificates
            ORDER BY created_at DESC
            LIMIT %s
            """,
            (limit,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def set_certificate_status(cert_id: str, status: str) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.certificates
                SET status = %s, updated_at = now()
                WHERE id = %s
                RETURNING id, user_id, title, status, notes, evidence_url, created_at, updated_at
                """,
                (status, cert_id),
            )
            row = await _fetchone(cur)
            await conn.commit()
    return dict(row) if row else None


async def approve_teacher_user(user_id: str, reviewer_id: str) -> None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher', updated_at = now() WHERE user_id = %s",
                (user_id,),
            )
            await cur.execute(
                """
                INSERT INTO app.teacher_approvals (user_id, approved_by, approved_at)
                VALUES (%s, %s, now())
                ON CONFLICT (user_id)
                DO UPDATE SET approved_by = EXCLUDED.approved_by, approved_at = EXCLUDED.approved_at
                """,
                (user_id, reviewer_id),
            )
            await cur.execute(
                """
                UPDATE app.certificates
                SET status = 'verified', updated_at = now()
                WHERE user_id = %s AND lower(title) = lower(%s)
                """,
                (user_id, "Läraransökan"),
            )
            await conn.commit()


async def reject_teacher_user(user_id: str, reviewer_id: str) -> None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.certificates
                SET status = 'rejected', updated_at = now()
                WHERE user_id = %s AND lower(title) = lower(%s)
                """,
                (user_id, "Läraransökan"),
            )
            await cur.execute(
                "DELETE FROM app.teacher_approvals WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def follow_user(follower_id: str, followee_id: str) -> None:
    if follower_id == followee_id:
        raise ValueError("Cannot follow self")
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.follows (follower_id, followee_id)
                VALUES (%s, %s)
                ON CONFLICT (follower_id, followee_id) DO NOTHING
                """,
                (follower_id, followee_id),
            )
            await conn.commit()


async def unfollow_user(follower_id: str, followee_id: str) -> None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.follows WHERE follower_id = %s AND followee_id = %s",
                (follower_id, followee_id),
            )
            await conn.commit()


async def is_following_user(follower_id: str, followee_id: str) -> bool:
    if not follower_id or not followee_id:
        return False
    async with get_conn() as cur:
        await cur.execute(
            "SELECT 1 FROM app.follows WHERE follower_id = %s AND followee_id = %s LIMIT 1",
            (follower_id, followee_id),
        )
        row = await _fetchone(cur)
        return row is not None


async def list_notifications_for_user(
    user_id: str, unread_only: bool = False
) -> list[dict]:
    async with get_conn() as cur:
        if unread_only:
            await cur.execute(
                """
                SELECT id, kind, payload, is_read, created_at
                FROM app.notifications
                WHERE user_id = %s AND is_read = false
                ORDER BY created_at DESC
                LIMIT 200
                """,
                (user_id,),
            )
        else:
            await cur.execute(
                """
                SELECT id, kind, payload, is_read, created_at
                FROM app.notifications
                WHERE user_id = %s
                ORDER BY created_at DESC
                LIMIT 200
                """,
                (user_id,),
            )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def mark_notification_read(
    notification_id: str, user_id: str, is_read: bool
) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.notifications
                SET is_read = %s
                WHERE id = %s AND user_id = %s
                RETURNING id, user_id, kind, payload, is_read, created_at
                """,
                (is_read, notification_id, user_id),
            )
            row = await _fetchone(cur)
            await conn.commit()
    return dict(row) if row else None


async def profile_overview(
    target_user_id: str,
    viewer_id: str | None = None,
) -> dict | None:
    profile = await get_profile_row(target_user_id)
    if not profile:
        return None
    is_following = False
    if viewer_id and viewer_id != target_user_id:
        is_following = await is_following_user(viewer_id, target_user_id)
    services = await list_teacher_services(target_user_id)
    meditations = await list_teacher_meditations(target_user_id)
    return {
        "profile": profile,
        "is_following": is_following,
        "services": services,
        "meditations": meditations,
    }
