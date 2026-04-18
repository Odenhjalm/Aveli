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
    auth_subjects as auth_subjects_repo,
    create_order as repo_create_order,
    create_user as repo_create_user,
    get_profile as repo_get_profile,
    get_user_by_email as repo_get_user_by_email,
    get_user_by_id as repo_get_user_by_id,
    get_user_order as repo_get_user_order,
    list_services as repo_list_services,
    mark_order_paid as repo_mark_order_paid,
    insert_auth_event as repo_insert_auth_event,
    revoke_refresh_tokens_for_user as repo_revoke_refresh_tokens_for_user,
    set_order_checkout_reference as repo_set_order_checkout_reference,
    update_profile as repo_update_profile,
    upsert_refresh_token as repo_upsert_refresh_token,
)
from .repositories.orders import get_order as repo_get_order
from .services import courses_service
from .services import storage_service
from .config import settings
from .utils import media_signer

logger = logging.getLogger(__name__)


def _test_visibility_clause(alias: str) -> str:
    return f"app.is_test_row_visible({alias}.is_test, {alias}.test_session_id)"


def _effective_role_sql(alias: str) -> str:
    return f"""
        CASE
            WHEN lower(COALESCE({alias}.role::text, '')) IN ('learner', 'teacher', 'admin')
                THEN lower({alias}.role::text)
            ELSE NULL
        END
    """


def _profile_photo_url_sql(alias: str) -> str:
    return (
        f"CASE WHEN {alias}.avatar_media_id IS NOT NULL "
        f"THEN '/profiles/avatar/' || {alias}.avatar_media_id::text "
        f"ELSE NULL END"
    )


def _effective_subject_role(auth_subject: dict[str, Any] | None) -> str | None:
    if auth_subject is None:
        return None
    role = str(auth_subject.get("role") or "").strip().lower()
    if role in {"learner", "teacher", "admin"}:
        return role
    return None


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
                    SELECT 1 FROM app.home_player_uploads hpu WHERE hpu.media_id = mo.id
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

    # Best-effort: delete from Supabase Storage when configured.
    if storage_bucket:
        normalized_bucket = str(storage_bucket).strip() or None
    else:
        normalized_bucket = None
    if normalized_bucket:
        try:
            service = storage_service.get_storage_service(normalized_bucket)
            if service.enabled:
                normalized_path = str(storage_path).lstrip("/")
                candidates: list[str] = []
                bucket_prefix = f"{normalized_bucket}/"
                if normalized_path.startswith(bucket_prefix):
                    stripped = normalized_path[len(bucket_prefix) :].lstrip("/")
                    if stripped:
                        candidates.append(stripped)
                candidates.append(normalized_path)
                for key in candidates:
                    try:
                        await service.delete_object(key)
                        break
                    except storage_service.StorageServiceError as exc:
                        logger.warning(
                            "Failed to delete storage object bucket=%s path=%s: %s",
                            normalized_bucket,
                            key,
                            exc,
                        )
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning(
                "Failed to cleanup remote media object bucket=%s path=%s: %s",
                normalized_bucket,
                storage_path,
                exc,
            )

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
    user_id: str,
    token: str,
    jti: str,
    expires_at: datetime,
    *,
    rotated_from_jti: str | None = None,
) -> None:
    token_hash = _hash_refresh_token(token)
    await repo_upsert_refresh_token(
        user_id=user_id,
        jti=jti,
        token_hash=token_hash,
        expires_at=expires_at,
        rotated_from_jti=rotated_from_jti,
    )


async def validate_refresh_token(jti: str, token: str) -> dict | None:
    token_hash = _hash_refresh_token(token)
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT jti,
                       user_id,
                       token_hash,
                       issued_at,
                       expires_at,
                       last_used_at,
                       revoked_at,
                       rotated_at,
                       rotated_from_jti
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
    *,
    actor_user_id: str | None,
    subject_user_id: str,
    event_type: str,
    metadata: dict | None = None,
) -> None:
    await repo_insert_auth_event(
        actor_user_id=actor_user_id,
        subject_user_id=subject_user_id,
        event_type=event_type,
        metadata=metadata,
    )


async def get_user_by_email(email: str):
    return await repo_get_user_by_email(email)


async def get_user_by_id(user_id: str):
    return await repo_get_user_by_id(user_id)


async def create_user(
    email: str,
    password: str,
    display_name: str | None = None,
):
    hashed = hash_password(password)
    result = await repo_create_user(
        email=email,
        hashed_password=hashed,
        display_name=display_name,
    )
    return result["user"]["id"]


async def is_teacher_user(user_id: str) -> bool:
    auth_subject = await auth_subjects_repo.get_auth_subject(user_id)
    return _effective_subject_role(auth_subject) == "teacher"


async def teacher_courses(user_id: str) -> Iterable[dict]:
    del user_id
    return await courses_service.list_courses()


async def user_certificates(
    user_id: str, verified_only: bool = False
) -> Iterable[dict]:
    del user_id, verified_only
    return []


async def add_certificate(
    user_id: str,
    *,
    title: str,
    status: str = "pending",
    notes: str | None = None,
    evidence_url: str | None = None,
) -> dict:
    del user_id, title, status, notes, evidence_url
    raise RuntimeError("certificates have no Baseline V2 authority")


async def certificates_of(user_id: str, verified_only: bool = False) -> Iterable[dict]:
    return await user_certificates(user_id, verified_only)


async def teacher_status(user_id: str) -> dict:
    auth_subject = await auth_subjects_repo.get_auth_subject(user_id)
    role = "teacher" if _effective_subject_role(auth_subject) == "teacher" else "learner"
    return {
        "role": role,
        "has_application": False,
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


async def revoke_refresh_tokens_for_user(user_id: str) -> None:
    await repo_revoke_refresh_tokens_for_user(user_id)


async def create_course_for_user(user_id: str, data: dict) -> dict | None:
    del user_id
    return await courses_service.create_course(dict(data))


async def update_course_for_user(
    user_id: str, course_id: str, patch: dict
) -> dict | None:
    del user_id
    payload = {key: value for key, value in patch.items()}
    return await courses_service.update_course(course_id, payload)


async def delete_course_for_user(user_id: str, course_id: str) -> bool:
    del user_id
    return await courses_service.delete_course(course_id)


async def list_courses(
    *,
    published_only: bool = True,
    free_intro: bool | None = None,
    search: str | None = None,
    limit: int | None = None,
) -> Iterable[dict]:
    del published_only, free_intro
    rows = await courses_service.list_public_courses(search=search, limit=limit)
    return rows


async def list_intro_courses(limit: int = 5) -> Iterable[dict]:
    return await _list_landing_courses(limit=limit, intro_only=True)


async def list_popular_courses(limit: int = 6) -> Iterable[dict]:
    return await _list_landing_courses(limit=limit, intro_only=False)


async def _list_landing_courses(
    *,
    limit: int,
    intro_only: bool,
) -> Iterable[dict]:
    clauses = []
    params: list[Any] = []

    clauses.append("c.visibility = 'public'::app.course_visibility")

    if intro_only:
        clauses.append("c.group_position = 0")

    where_sql = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    order_sql = (
        "ORDER BY c.updated_at DESC"
        if intro_only
        else "ORDER BY c.group_position ASC, c.updated_at DESC"
    )

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                f"""
                SELECT
                    c.id,
                    c.slug,
                    c.title,
                    c.group_position,
                    c.price_amount_cents,
                    cpc.short_description,
                    NULL::text AS resolved_cover_url
                FROM app.courses c
                LEFT JOIN app.course_public_content cpc
                  ON cpc.course_id = c.id
                {where_sql}
                {order_sql}
                LIMIT %s
                """,
                [*params, limit],
            )
            rows = await cur.fetchall()
            return rows


async def list_teachers(limit: int = 20) -> Iterable[dict]:
    teacher_role_sql = _effective_role_sql("subj")
    async with get_conn() as cur:
        await cur.execute(
            f"""
            SELECT
              prof.user_id,
              prof.display_name,
              {_profile_photo_url_sql("prof")} AS photo_url,
              prof.bio
            FROM app.profiles prof
            LEFT JOIN auth.users u ON u.id = prof.user_id
            LEFT JOIN app.auth_subjects subj ON subj.user_id = prof.user_id
            WHERE ({teacher_role_sql}) = 'teacher'
              AND lower(u.email) = lower(%s)
            ORDER BY prof.display_name NULLS LAST
            LIMIT %s
            """,
            ("avelibooks@gmail.com", limit),
        )
        rows = await cur.fetchall()

    items: list[dict[str, Any]] = []
    for row in rows:
        item = dict(row)
        item["photo_url"] = _choose_public_profile_photo_url(item.get("photo_url"))
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
        if parsed.path.startswith(
            ("/api/files/", "/profiles/avatar/", "/auth/avatar/")
        ):
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


def _choose_public_profile_photo_url(photo_url: str | None) -> str | None:
    resolved = _normalize_public_profile_photo_url(photo_url)
    if (
        resolved
        and resolved.startswith("/api/files/")
        and not _public_upload_exists(resolved)
    ):
        resolved = None

    return resolved


async def list_teacher_course_priorities(limit: int | None = None) -> list[dict]:
    teacher_role_sql = _effective_role_sql("subj")
    clauses = f"""
        WITH course_stats AS (
            SELECT
                teacher_id AS teacher_id,
                COUNT(*) AS total_courses,
                COUNT(*) FILTER (
                    WHERE visibility = 'public'::app.course_visibility
                ) AS published_courses
            FROM app.courses
            GROUP BY teacher_id
        )
        SELECT
            prof.user_id AS teacher_id,
            prof.display_name,
            u.email AS email,
            {_profile_photo_url_sql("prof")} AS photo_url,
            100 AS priority,
            NULL::text AS notes,
            NULL::timestamptz AS updated_at,
            NULL::uuid AS updated_by,
            NULL::text AS updated_by_name,
            COALESCE(stats.total_courses, 0) AS total_courses,
            COALESCE(stats.published_courses, 0) AS published_courses
        FROM app.profiles prof
        LEFT JOIN auth.users u
          ON u.id = prof.user_id
        LEFT JOIN app.auth_subjects subj
          ON subj.user_id = prof.user_id
        LEFT JOIN course_stats stats
          ON stats.teacher_id = prof.user_id
        WHERE ({teacher_role_sql}) = 'teacher'
        ORDER BY lower(COALESCE(prof.display_name, u.email))
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


async def get_teacher_course_priority(teacher_id: str) -> dict | None:
    teacher_role_sql = _effective_role_sql("subj")
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                f"""
                WITH course_stats AS (
                    SELECT
                        teacher_id AS teacher_id,
                        COUNT(*) AS total_courses,
                        COUNT(*) FILTER (
                            WHERE visibility = 'public'::app.course_visibility
                        ) AS published_courses
                    FROM app.courses
                    GROUP BY teacher_id
                )
                SELECT
                    prof.user_id AS teacher_id,
                    prof.display_name,
                    u.email AS email,
                    {_profile_photo_url_sql("prof")} AS photo_url,
                    100 AS priority,
                    NULL::text AS notes,
                    NULL::timestamptz AS updated_at,
                    NULL::uuid AS updated_by,
                    NULL::text AS updated_by_name,
                    COALESCE(stats.total_courses, 0) AS total_courses,
                    COALESCE(stats.published_courses, 0) AS published_courses
                FROM app.profiles prof
                LEFT JOIN auth.users u
                  ON u.id = prof.user_id
                LEFT JOIN app.auth_subjects subj
                  ON subj.user_id = prof.user_id
                LEFT JOIN course_stats stats
                  ON stats.teacher_id = prof.user_id
                WHERE ({teacher_role_sql}) = 'teacher'
                  AND prof.user_id = %s
                """,
                (teacher_id,),
            )
            return await _fetchone(cur)


async def fetch_admin_metrics() -> dict:
    teacher_role_sql = _effective_role_sql("subj")
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                f"""
                SELECT
                    (SELECT COUNT(*) FROM app.profiles) AS total_users,
                    (SELECT COUNT(*) FROM app.auth_subjects subj
                        WHERE ({teacher_role_sql}) = 'teacher') AS total_teachers,
                    (SELECT COUNT(*) FROM app.courses) AS total_courses,
                    (SELECT COUNT(*) FROM app.courses
                        WHERE visibility = 'public'::app.course_visibility) AS published_courses,
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


async def list_course_lessons(course_id: str) -> Iterable[dict]:
    return await courses_service.list_course_lessons(course_id)


async def get_lesson(lesson_id: str):
    return await courses_service.fetch_lesson(lesson_id)


async def list_lesson_media(
    lesson_id: str,
    *,
    mode: str | None = None,
) -> list[dict]:
    return list(await courses_service.list_lesson_media(lesson_id, mode=mode))


# UWD-001 non-canonical write isolation: direct lesson_media mutation helpers below
# are helper-only implementation surfaces and must not define canonical media authority.
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

    normalized_media_asset_id = str(media_asset_id or "").strip()
    if not normalized_media_asset_id:
        raise ValueError("lesson_media writes require media_asset_id")

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
                media_asset_id=normalized_media_asset_id,
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
    normalized_media_asset_id = str(media_asset_id or "").strip()
    if not normalized_media_asset_id:
        raise ValueError("lesson_media writes require media_asset_id")

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
                  CASE
                    WHEN ma.id IS NOT NULL AND ma.state = 'ready'
                      THEN ma.playback_object_path
                    ELSE i.storage_path
                  END AS storage_path,
                  CASE
                    WHEN ma.id IS NOT NULL AND ma.state = 'ready'
                      THEN %s
                    ELSE coalesce(i.storage_bucket, 'lesson-media')
                  END AS storage_bucket,
                  i.media_id,
                  i.media_asset_id,
                  i.position,
                  coalesce(ma.duration_seconds, i.duration_seconds) AS duration_seconds,
                  CASE
                    WHEN ma.state = 'ready' AND lower(coalesce(ma.media_type, '')) = 'audio'
                      THEN 'audio/mpeg'
                    WHEN ma.id IS NOT NULL
                      THEN ma.original_content_type
                    WHEN lower(coalesce(i.kind, '')) IN ('document', 'pdf')
                      THEN 'application/pdf'
                    ELSE NULL
                  END AS content_type,
                  CASE
                    WHEN ma.id IS NOT NULL THEN ma.original_size_bytes
                    ELSE NULL
                  END AS byte_size,
                  CASE
                    WHEN ma.id IS NOT NULL THEN ma.original_filename
                    ELSE NULL
                  END AS original_name,
                  CASE
                    WHEN ma.id IS NOT NULL THEN ma.state
                    WHEN lower(coalesce(i.kind, '')) IN ('document', 'pdf')
                      THEN 'ready'
                    ELSE NULL
                  END AS media_state,
                  ma.ingest_format,
                  ma.playback_format,
                  ma.codec,
                  ma.error_message,
                  i.created_at
                FROM inserted i
                LEFT JOIN app.media_assets ma ON ma.id = i.media_asset_id
                """,
                (
                    lesson_id,
                    kind,
                    storage_path,
                    storage_bucket,
                    media_id,
                    normalized_media_asset_id,
                    position,
                    duration_seconds,
                    settings.media_source_bucket,
                ),
            )
            row = await _fetchone(cur)
            await conn.commit()
            return row


async def update_lesson_media_asset_link(
    *,
    lesson_media_id: str,
    lesson_id: str,
    kind: str,
    media_asset_id: str,
    storage_bucket: str,
    duration_seconds: int | None = None,
) -> dict | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.lesson_media
                SET kind = %s,
                    media_id = null,
                    media_asset_id = %s,
                    storage_path = null,
                    storage_bucket = %s,
                    duration_seconds = %s
                WHERE id = %s
                  AND lesson_id = %s
                RETURNING id
                """,
                (
                    kind,
                    media_asset_id,
                    storage_bucket,
                    duration_seconds,
                    lesson_media_id,
                    lesson_id,
                ),
            )
            row = await _fetchone(cur)
            await conn.commit()
    if not row:
        return None
    return await get_media(str(row["id"]))


async def get_media(media_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT
              lm.id,
              lm.lesson_id,
              lm.kind,
              CASE
                WHEN ma.id IS NOT NULL AND ma.state = 'ready'
                  THEN ma.playback_object_path
                ELSE lm.storage_path
              END AS storage_path,
              CASE
                WHEN ma.id IS NOT NULL AND ma.state = 'ready'
                  THEN %s
                ELSE coalesce(lm.storage_bucket, 'lesson-media')
              END AS storage_bucket,
              lm.media_id,
              lm.media_asset_id,
              CASE
                WHEN ma.state = 'ready' AND lower(coalesce(ma.media_type, '')) = 'audio'
                  THEN 'audio/mpeg'
                WHEN ma.id IS NOT NULL
                  THEN ma.original_content_type
                WHEN lower(coalesce(lm.kind, '')) IN ('document', 'pdf')
                  THEN 'application/pdf'
                ELSE NULL
              END AS content_type,
              CASE
                WHEN ma.id IS NOT NULL THEN ma.original_size_bytes
                ELSE NULL
              END AS byte_size,
              CASE
                WHEN ma.id IS NOT NULL THEN ma.original_filename
                ELSE NULL
              END AS original_name,
              CASE
                WHEN ma.id IS NOT NULL THEN ma.state
                WHEN lower(coalesce(lm.kind, '')) IN ('document', 'pdf') THEN 'ready'
                ELSE NULL
              END AS media_state,
              ma.ingest_format,
              ma.playback_format,
              ma.codec,
              ma.error_message
            FROM app.lesson_media lm
            LEFT JOIN app.media_assets ma ON ma.id = lm.media_asset_id
            WHERE lm.id = %s
              AND app.is_test_row_visible(lm.is_test, lm.test_session_id)
            """,
            (settings.media_source_bucket, media_id),
        )
        return await _fetchone(cur)


async def get_lesson_media_by_media_asset_id(media_asset_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id
            FROM app.lesson_media
            WHERE media_asset_id = %s
              AND app.is_test_row_visible(app.lesson_media.is_test, app.lesson_media.test_session_id)
            ORDER BY created_at DESC
            LIMIT 1
            """,
            (media_asset_id,),
        )
        row = await _fetchone(cur)
    if not row:
        return None
    return await get_media(str(row["id"]))


async def is_course_owner(user_id: str, course_id: str) -> bool:
    return await courses_service.is_course_owner(user_id, course_id)


async def is_course_teacher_or_instructor(user_id: str, course_id: str) -> bool:
    return await courses_service.is_course_teacher_or_instructor(user_id, course_id)


async def lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    return await courses_service.lesson_course_ids(lesson_id)


async def upsert_lesson(
    *,
    lesson_id: str | None,
    course_id: str,
    lesson_title: str | None = None,
    position: int | None = None,
) -> dict | None:
    del lesson_id, course_id, lesson_title, position
    raise RuntimeError(
        "Legacy mixed lesson upsert is disabled; use separate structure and content surfaces"
    )


async def delete_lesson(lesson_id: str) -> bool:
    return await courses_service.delete_lesson(lesson_id)


async def get_profile(user_id: str):
    return await repo_get_profile(user_id)


async def update_profile(
    user_id: str,
    *,
    display_name: str | None = None,
    bio: str | None = None,
) -> dict | None:
    return await repo_update_profile(
        user_id,
        display_name=display_name,
        bio=bio,
    )


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


async def course_quiz_info(course_id: str, user_id: str | None):
    del course_id, user_id
    raise RuntimeError("quizzes have no Baseline V2 authority")


async def quiz_questions(quiz_id: str) -> Iterable[dict]:
    del quiz_id
    raise RuntimeError("quizzes have no Baseline V2 authority")


async def submit_quiz(quiz_id: str, user_id: str, answers: dict):
    del quiz_id, user_id, answers
    raise RuntimeError("quizzes have no Baseline V2 authority")


async def ensure_quiz_for_user(course_id: str, user_id: str) -> dict | None:
    del course_id, user_id
    raise RuntimeError("quizzes have no Baseline V2 authority")


async def quiz_belongs_to_user(quiz_id: str, user_id: str) -> bool:
    del quiz_id, user_id
    return False


async def upsert_quiz_question(quiz_id: str, data: dict) -> dict | None:
    del quiz_id, data
    raise RuntimeError("quizzes have no Baseline V2 authority")


async def delete_quiz_question(question_id: str) -> bool:
    del question_id
    return False


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
            f"""
            SELECT p.id,
                   p.author_id,
                   p.content,
                   p.media_paths,
                   p.created_at,
                   prof.display_name,
                   {_profile_photo_url_sql("prof")} AS photo_url,
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
                "photo_url": _choose_public_profile_photo_url(row.get("photo_url")),
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
                f"""
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
                       {_profile_photo_url_sql("prof")} AS photo_url,
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
            "photo_url": _choose_public_profile_photo_url(row.get("photo_url")),
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
            f"""
            SELECT td.user_id,
                   td.headline,
                   td.specialties,
                   td.rating,
                   td.created_at,
                   prof.display_name,
                   {_profile_photo_url_sql("prof")} AS photo_url,
                   prof.bio
            FROM app.teacher_directory td
            LEFT JOIN app.profiles prof ON prof.user_id = td.user_id
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
                "photo_url": _choose_public_profile_photo_url(row.get("photo_url")),
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
            }
        )
    return items


async def get_teacher_directory_item(user_id: str) -> dict | None:
    async with get_conn() as cur:
        await cur.execute(
            f"""
            SELECT td.user_id,
                   td.headline,
                   td.specialties,
                   td.rating,
                   td.created_at,
                   prof.display_name,
                   {_profile_photo_url_sql("prof")} AS photo_url,
                   prof.bio
            FROM app.teacher_directory td
            LEFT JOIN app.profiles prof ON prof.user_id = td.user_id
            WHERE td.user_id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = await _fetchone(cur)

        if not row:
            await cur.execute(
                f"""
                SELECT prof.user_id,
                       prof.display_name,
                       {_profile_photo_url_sql("prof")} AS photo_url,
                       prof.bio,
                       prof.created_at
                FROM app.profiles prof
                LEFT JOIN auth.users u ON u.id = prof.user_id
                LEFT JOIN app.auth_subjects subj ON subj.user_id = prof.user_id
                WHERE prof.user_id = %s
                  AND ({_effective_role_sql("subj")}) = 'teacher'
                  AND lower(u.email) = lower(%s)
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
                fallback_profile.get("photo_url")
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
            "photo_url": _choose_public_profile_photo_url(row.get("photo_url")),
            "bio": row.get("bio"),
        }
    return {
        "user_id": row.get("user_id"),
        "headline": row.get("headline"),
        "specialties": specialties,
        "rating": rating,
        "created_at": row.get("created_at"),
        "profile": profile,
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
            f"""
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
                {_profile_photo_url_sql("p")} AS provider_photo_url,
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
            "photo_url": _choose_public_profile_photo_url(
                row_dict.get("provider_photo_url")
            ),
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
    del user_ids
    return {}


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
    return await repo_get_profile(user_id)


async def user_has_admin_role(user_id: str) -> bool:
    auth_subject = await auth_subjects_repo.get_auth_subject(user_id)
    return _effective_subject_role(auth_subject) == "admin"


async def _set_teacher_role(
    *,
    target_user_id: str,
    actor_user_id: str,
    role: str,
    event_type: str,
) -> dict[str, Any]:
    if actor_user_id == target_user_id:
        raise PermissionError("Teacher role self-mutation is forbidden")

    target_user = await repo_get_user_by_id(target_user_id)
    if not target_user:
        raise LookupError("Canonical identity missing")

    updated_subject = await auth_subjects_repo.set_role_authority(
        target_user_id,
        role=role,
    )
    if not updated_subject:
        raise LookupError("Canonical auth subject missing")

    await repo_revoke_refresh_tokens_for_user(target_user_id)
    await repo_insert_auth_event(
        actor_user_id=actor_user_id,
        subject_user_id=target_user_id,
        event_type=event_type,
        metadata={"role": role},
    )
    return updated_subject


async def grant_teacher_role(target_user_id: str, actor_user_id: str) -> dict[str, Any]:
    return await _set_teacher_role(
        target_user_id=target_user_id,
        actor_user_id=actor_user_id,
        role="teacher",
        event_type="teacher_role_granted",
    )


async def revoke_teacher_role(
    target_user_id: str,
    actor_user_id: str,
) -> dict[str, Any]:
    return await _set_teacher_role(
        target_user_id=target_user_id,
        actor_user_id=actor_user_id,
        role="learner",
        event_type="teacher_role_revoked",
    )


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
    del user_id, unread_only
    return []


async def mark_notification_read(
    notification_id: str, user_id: str, is_read: bool
) -> dict | None:
    del notification_id, user_id, is_read
    return None


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
