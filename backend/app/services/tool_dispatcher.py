from __future__ import annotations

import os
import re
from typing import Any, Mapping, Sequence

import psycopg
from fastapi import HTTPException, status

_READONLY_OPTIONS = "-c default_transaction_read_only=on -c statement_timeout=3000"
_ALLOWED_ACTIONS: dict[str, set[str]] = {
    "supabase_readonly": {
        "query",
        "list_intro_courses",
        "get_course_by_id",
        "get_course_by_slug",
        "list_seminars",
        "get_seminar_by_id",
    },
}
_FORBIDDEN_KEYWORDS = {
    "INSERT",
    "UPDATE",
    "DELETE",
    "ALTER",
    "DROP",
    "CREATE",
    "GRANT",
    "REVOKE",
    "TRUNCATE",
    "COPY",
    "VACUUM",
    "ANALYZE",
    "CALL",
    "DO",
}


def enforce_tool_allowed(*, tool: str, action: str, tools_allowed: list[str]) -> None:
    normalized_tool = tool.strip()
    normalized_action = action.strip()
    if not normalized_tool or normalized_tool not in tools_allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Tool '{tool}' is not allowed by execution policy",
        )

    allowed_actions = _ALLOWED_ACTIONS.get(normalized_tool, set())
    if normalized_action not in allowed_actions:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Action '{action}' is not supported for tool '{tool}'",
        )


def _require_db_url() -> str:
    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="SUPABASE_DB_URL missing")
    return db_url


def _with_cursor():
    db_url = _require_db_url()
    return psycopg.connect(db_url, options=_READONLY_OPTIONS)


def _strip_leading_comments(sql: str) -> str:
    pattern = r"^\s*(?:--[^\n]*\n|/\*.*?\*/\s*)*"
    return re.sub(pattern, "", sql, flags=re.S)


def _sanitize_select_query(raw_sql: str) -> tuple[str, bool]:
    if not raw_sql or not isinstance(raw_sql, str):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="sql is required")

    stripped = _strip_leading_comments(raw_sql).strip()
    if not stripped:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="sql is required")

    if ";" in stripped:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only single SELECT statements are allowed")

    upper = stripped.upper()
    if not (upper.startswith("SELECT") or upper.startswith("WITH")):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only SELECT is allowed")

    for kw in _FORBIDDEN_KEYWORDS:
        if re.search(rf"\b{kw}\b", upper):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only SELECT is allowed")

    has_limit = re.search(r"\bLIMIT\b", upper) is not None
    final_sql = stripped if has_limit else f"{stripped} LIMIT 100"
    return final_sql, not has_limit


def _validated_limit(args: Mapping[str, Any] | None, *, default: int = 20, maximum: int = 100) -> int:
    if args is None or args.get("limit") is None:
        return default
    try:
        value = int(args.get("limit"))
    except (TypeError, ValueError):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="limit must be an integer")
    if value <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="limit must be positive")
    return min(value, maximum)


def _fetch_rows(sql: str, params: Sequence[Any], *, limit_cap: int) -> Mapping[str, Any]:
    try:
        with _with_cursor() as conn:
            with conn.cursor(row_factory=psycopg.rows.dict_row) as cur:  # type: ignore[attr-defined]
                cur.execute(sql, params)
                rows = cur.fetchmany(limit_cap + 1)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Database query failed")

    truncated = len(rows) > limit_cap
    rows = rows[:limit_cap]
    return {
        "stub": False,
        "row_count": len(rows),
        "truncated": truncated,
        "rows": rows,
    }


def _fetch_single(sql: str, params: Sequence[Any]) -> Mapping[str, Any]:
    result = _fetch_rows(sql, params, limit_cap=1)
    if result["row_count"] == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    return result


def _run_supabase_readonly_query(args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    sql = None if args is None else args.get("sql")
    final_sql, added_limit = _sanitize_select_query(sql)

    try:
        with _with_cursor() as conn:
            with conn.cursor(row_factory=psycopg.rows.dict_row) as cur:  # type: ignore[attr-defined]
                cur.execute(final_sql)
                rows = cur.fetchmany(101)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Database query failed")

    truncated = len(rows) > 100 or (added_limit and len(rows) == 100)
    rows = rows[:100]
    return {
        "stub": False,
        "row_count": len(rows),
        "truncated": truncated,
        "rows": rows,
    }


def _list_intro_courses(args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    limit = _validated_limit(args)
    sql = """
        SELECT id,
               slug,
               title,
               description,
               cover_url,
               video_url,
               branch,
               is_free_intro,
               is_published,
               price_amount_cents,
               currency,
               created_at,
               updated_at
          FROM app.courses
         WHERE is_published = true
           AND is_free_intro = true
         ORDER BY updated_at DESC
         LIMIT %s
    """
    return _fetch_rows(sql, (limit,), limit_cap=limit)


def _get_course_by_id(args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    if not args or not args.get("course_id"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="course_id is required")
    course_id = str(args.get("course_id"))
    sql = """
        SELECT id,
               slug,
               title,
               description,
               cover_url,
               video_url,
               branch,
               is_free_intro,
               is_published,
               price_amount_cents,
               currency,
               created_at,
               updated_at
          FROM app.courses
         WHERE id = %s
         LIMIT 1
    """
    return _fetch_single(sql, (course_id,))


def _get_course_by_slug(args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    if not args or not args.get("slug"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="slug is required")
    slug = str(args.get("slug"))
    sql = """
        SELECT id,
               slug,
               title,
               description,
               cover_url,
               video_url,
               branch,
               is_free_intro,
               is_published,
               price_amount_cents,
               currency,
               created_at,
               updated_at
          FROM app.courses
         WHERE slug = %s
         LIMIT 1
    """
    return _fetch_single(sql, (slug,))


def _list_seminars(args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    limit = _validated_limit(args)
    sql = """
        SELECT s.id,
               s.host_id,
               s.title,
               s.description,
               s.status,
               s.scheduled_at,
               s.duration_minutes,
               s.livekit_room,
               s.created_at,
               s.updated_at,
               p.display_name AS host_display_name
          FROM app.seminars s
     LEFT JOIN app.profiles p ON p.user_id = s.host_id
         WHERE s.status IN ('scheduled', 'live')
         ORDER BY s.scheduled_at NULLS LAST, s.created_at DESC
         LIMIT %s
    """
    return _fetch_rows(sql, (limit,), limit_cap=limit)


def _get_seminar_by_id(args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    if not args or not args.get("seminar_id"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="seminar_id is required")
    seminar_id = str(args.get("seminar_id"))
    sql = """
        SELECT s.id,
               s.host_id,
               s.title,
               s.description,
               s.status,
               s.scheduled_at,
               s.duration_minutes,
               s.livekit_room,
               s.livekit_metadata,
               s.created_at,
               s.updated_at,
               p.display_name AS host_display_name
          FROM app.seminars s
     LEFT JOIN app.profiles p ON p.user_id = s.host_id
         WHERE s.id = %s
         LIMIT 1
    """
    return _fetch_single(sql, (seminar_id,))


def dispatch_tool_action(*, tool: str, action: str, args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    if tool == "supabase_readonly":
        if action == "query":
            return _run_supabase_readonly_query(args)
        if action == "list_intro_courses":
            return _list_intro_courses(args)
        if action == "get_course_by_id":
            return _get_course_by_id(args)
        if action == "get_course_by_slug":
            return _get_course_by_slug(args)
        if action == "list_seminars":
            return _list_seminars(args)
        if action == "get_seminar_by_id":
            return _get_seminar_by_id(args)

    # Fallback stub for future handlers
    return {
        "stub": True,
        "tool": tool,
        "action": action,
        "args": args or {},
    }


__all__ = ["enforce_tool_allowed", "dispatch_tool_action"]
