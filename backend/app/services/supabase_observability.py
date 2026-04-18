from __future__ import annotations

from datetime import datetime, timezone
from time import perf_counter
from typing import Any, Sequence

from psycopg import errors
from psycopg.rows import dict_row

from ..config import settings
from ..db import pool


SCHEMA_VERSION = "supabase_observability_v1"
AUTHORITY_NOTE = "observability_not_authority"
_CONFIGURED_BUCKETS = (
    "media_source_bucket",
    "media_profile_bucket",
    "media_public_bucket",
)
_DOMAIN_TABLES = (
    "app.auth_subjects",
    "app.profiles",
    "app.memberships",
    "app.courses",
    "app.lessons",
    "app.lesson_contents",
    "app.lesson_media",
    "app.media_assets",
    "app.orders",
    "app.payments",
    "app.course_enrollments",
)


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _json_safe(value: Any) -> Any:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    return value


def _surface(surface: str, *, status: str, data: dict[str, Any], issues: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "artifact_type": surface,
        "schema_version": SCHEMA_VERSION,
        "generated_at_utc": _now_iso(),
        "status": status,
        "authority_note": AUTHORITY_NOTE,
        "data_sources": ["supabase_database_readonly"],
        "read_only": True,
        "authority_override": False,
        "data": _json_safe(data),
        "issues": issues,
    }


def _issue(code: str, source: str, message: str, *, severity: str = "error") -> dict[str, Any]:
    return {
        "code": code,
        "source": source,
        "message": message,
        "severity": severity,
    }


def _status_from_issues(issues: list[dict[str, Any]]) -> str:
    severities = {str(issue.get("severity") or "error") for issue in issues}
    if "error" in severities:
        return "blocked"
    if "warning" in severities:
        return "warning"
    return "ok"


async def _fetch_all(sql: str, params: Sequence[Any] = ()) -> list[dict[str, Any]]:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute("SET TRANSACTION READ ONLY")
            await cur.execute(sql, params)
            rows = await cur.fetchall()
        await conn.rollback()
    return [_json_safe(dict(row)) for row in rows]


async def _fetch_one(sql: str, params: Sequence[Any] = ()) -> dict[str, Any]:
    rows = await _fetch_all(sql, params)
    return rows[0] if rows else {}


async def _safe_fetch_one(source: str, sql: str, params: Sequence[Any] = ()) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    try:
        return await _fetch_one(sql, params), []
    except (errors.UndefinedTable, errors.UndefinedColumn) as exc:
        return {}, [
            _issue(
                "supabase_schema_unavailable",
                source,
                f"{source} schema is unavailable",
                severity="warning",
            )
        ]
    except Exception as exc:
        return {}, [
            _issue(
                "supabase_read_failed",
                source,
                f"{source} read failed: {exc.__class__.__name__}",
            )
        ]


async def _safe_fetch_all(source: str, sql: str, params: Sequence[Any] = ()) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    try:
        return await _fetch_all(sql, params), []
    except (errors.UndefinedTable, errors.UndefinedColumn):
        return [], [
            _issue(
                "supabase_schema_unavailable",
                source,
                f"{source} schema is unavailable",
                severity="warning",
            )
        ]
    except Exception as exc:
        return [], [
            _issue(
                "supabase_read_failed",
                source,
                f"{source} read failed: {exc.__class__.__name__}",
            )
        ]


async def get_connection_health() -> dict[str, Any]:
    started = perf_counter()
    issues: list[dict[str, Any]] = []
    config = {
        "supabase_url_configured": settings.supabase_url is not None,
        "database_url_configured": settings.database_url is not None,
        "anon_key_configured": bool(settings.supabase_anon_key),
        "service_role_key_configured": bool(settings.supabase_service_role_key),
        "jwks_url_configured": bool(settings.supabase_jwks_url),
        "jwt_secret_configured": bool(settings.supabase_jwt_secrets),
        "mcp_mode": settings.mcp_mode,
    }
    if settings.database_url is None:
        issues.append(
            _issue(
                "database_url_missing",
                "settings.database_url",
                "DATABASE_URL/SUPABASE_DB_URL is not configured",
            )
        )
        return _surface(
            "supabase_connection_health",
            status=_status_from_issues(issues),
            data={"config": config, "database": {}},
            issues=issues,
        )

    database, query_issues = await _safe_fetch_one(
        "supabase.connection",
        """
        SELECT
          current_database() AS database_name,
          current_schema() AS current_schema,
          current_setting('server_version') AS postgres_version
        """,
    )
    issues.extend(query_issues)
    database["latency_ms"] = round((perf_counter() - started) * 1000.0, 3)
    return _surface(
        "supabase_connection_health",
        status=_status_from_issues(issues),
        data={"config": config, "database": database},
        issues=issues,
    )


async def get_auth_state() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    auth_users, auth_user_issues = await _safe_fetch_one(
        "auth.users",
        """
        SELECT
          COUNT(*)::int AS user_count,
          COUNT(*) FILTER (
            WHERE email_confirmed_at IS NOT NULL OR confirmed_at IS NOT NULL
          )::int AS verified_user_count,
          COUNT(*) FILTER (
            WHERE email_confirmed_at IS NULL AND confirmed_at IS NULL
          )::int AS unverified_user_count
        FROM auth.users
        """,
    )
    issues.extend(auth_user_issues)

    auth_subjects, auth_subject_issues = await _safe_fetch_one(
        "app.auth_subjects",
        """
        SELECT
          COUNT(*)::int AS subject_count,
          COUNT(*) FILTER (WHERE role = 'admin'::app.auth_subject_role)::int AS admin_subject_count
        FROM app.auth_subjects
        """,
    )
    issues.extend(auth_subject_issues)

    role_counts, role_issues = await _safe_fetch_all(
        "app.auth_subjects.role",
        """
        SELECT role::text AS role, COUNT(*)::int AS count
        FROM app.auth_subjects
        GROUP BY role
        ORDER BY role
        """,
    )
    issues.extend(role_issues)

    onboarding_counts, onboarding_issues = await _safe_fetch_all(
        "app.auth_subjects.onboarding_state",
        """
        SELECT onboarding_state, COUNT(*)::int AS count
        FROM app.auth_subjects
        GROUP BY onboarding_state
        ORDER BY onboarding_state
        """,
    )
    issues.extend(onboarding_issues)

    alignment, alignment_issues = await _safe_fetch_one(
        "auth.users_to_app.auth_subjects",
        """
        SELECT
          COUNT(*) FILTER (WHERE u.id IS NULL)::int AS auth_subjects_without_auth_user,
          COUNT(*) FILTER (WHERE a.user_id IS NULL)::int AS auth_users_without_auth_subject
        FROM auth.users u
        FULL OUTER JOIN app.auth_subjects a
          ON a.user_id = u.id
        """,
    )
    issues.extend(alignment_issues)

    return _surface(
        "supabase_auth_state",
        status=_status_from_issues(issues),
        data={
            "auth_users": auth_users,
            "auth_subjects": auth_subjects,
            "role_counts": role_counts,
            "onboarding_counts": onboarding_counts,
            "alignment": alignment,
        },
        issues=issues,
    )


async def _table_count(table_name: str) -> tuple[str, dict[str, Any], list[dict[str, Any]]]:
    row, issues = await _safe_fetch_one(
        table_name,
        f"SELECT COUNT(*)::int AS row_count FROM {table_name}",
    )
    return table_name, row, issues


async def get_domain_projection_health() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    table_counts: dict[str, Any] = {}
    for table_name in _DOMAIN_TABLES:
        _, row, table_issues = await _table_count(table_name)
        table_counts[table_name] = row
        issues.extend(table_issues)

    profile_alignment, profile_alignment_issues = await _safe_fetch_one(
        "app.profiles_to_app.auth_subjects",
        """
        SELECT COUNT(*)::int AS profiles_without_auth_subject
        FROM app.profiles p
        LEFT JOIN app.auth_subjects a
          ON a.user_id = p.user_id
        WHERE a.user_id IS NULL
        """,
    )
    issues.extend(profile_alignment_issues)

    membership_alignment, membership_alignment_issues = await _safe_fetch_one(
        "app.memberships.active_duplicates",
        """
        SELECT COUNT(*)::int AS users_with_multiple_active_memberships
        FROM (
          SELECT user_id
          FROM app.memberships
          WHERE lower(status) IN ('active', 'trialing')
          GROUP BY user_id
          HAVING COUNT(*) > 1
        ) duplicate_memberships
        """,
    )
    issues.extend(membership_alignment_issues)

    course_projection, course_projection_issues = await _safe_fetch_one(
        "app.courses_to_app.auth_subjects",
        """
        SELECT COUNT(*)::int AS courses_without_teacher_subject
        FROM app.courses c
        LEFT JOIN app.auth_subjects a
          ON a.user_id = c.teacher_id
        WHERE c.teacher_id IS NOT NULL
          AND a.user_id IS NULL
        """,
    )
    issues.extend(course_projection_issues)

    return _surface(
        "supabase_domain_projection_health",
        status=_status_from_issues(issues),
        data={
            "table_counts": table_counts,
            "projection_checks": {
                "profiles": profile_alignment,
                "memberships": membership_alignment,
                "courses": course_projection,
            },
        },
        issues=issues,
    )


async def get_domain_projections() -> dict[str, Any]:
    return await get_domain_projection_health()


async def get_storage_health() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    configured_buckets = {
        name: getattr(settings, name)
        for name in _CONFIGURED_BUCKETS
    }

    buckets, bucket_issues = await _safe_fetch_all(
        "storage.buckets",
        """
        SELECT
          b.id AS bucket_id,
          b.public,
          COUNT(o.id)::int AS object_count
        FROM storage.buckets b
        LEFT JOIN storage.objects o
          ON o.bucket_id = b.id
        GROUP BY b.id, b.public
        ORDER BY b.id
        """,
    )
    issues.extend(bucket_issues)

    media_references, media_reference_issues = await _safe_fetch_one(
        "app.media_assets.storage_references",
        """
        SELECT
          COUNT(*) FILTER (
            WHERE storage_bucket IS NOT NULL AND original_object_path IS NOT NULL
          )::int AS source_reference_count,
          COUNT(*) FILTER (
            WHERE storage_bucket IS NOT NULL AND playback_object_path IS NOT NULL
          )::int AS playback_reference_count
        FROM app.media_assets
        """,
    )
    issues.extend(media_reference_issues)

    missing_source_objects, missing_source_issues = await _safe_fetch_one(
        "app.media_assets_to_storage.objects.source",
        """
        SELECT COUNT(*)::int AS missing_source_object_count
        FROM app.media_assets m
        LEFT JOIN storage.objects o
          ON o.bucket_id = m.storage_bucket
         AND o.name = m.original_object_path
        WHERE m.storage_bucket IS NOT NULL
          AND m.original_object_path IS NOT NULL
          AND o.id IS NULL
        """,
    )
    issues.extend(missing_source_issues)

    return _surface(
        "supabase_storage_health",
        status=_status_from_issues(issues),
        data={
            "configured_buckets": configured_buckets,
            "buckets": buckets,
            "media_references": media_references,
            "storage_catalog_checks": {
                "source_objects": missing_source_objects,
            },
        },
        issues=issues,
    )


async def get_storage_state() -> dict[str, Any]:
    return await get_storage_health()
