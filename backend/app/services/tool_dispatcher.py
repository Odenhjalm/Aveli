from __future__ import annotations

import os
import re
from typing import Any, Mapping

import psycopg
from fastapi import HTTPException, status

_READONLY_OPTIONS = "-c default_transaction_read_only=on -c statement_timeout=3000"
_ALLOWED_ACTIONS: dict[str, set[str]] = {
    "supabase_readonly": {"query", "get"},
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


def _run_supabase_readonly_query(args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    sql = None if args is None else args.get("sql")
    final_sql, added_limit = _sanitize_select_query(sql)

    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="SUPABASE_DB_URL missing")

    try:
        with psycopg.connect(db_url, options=_READONLY_OPTIONS) as conn:
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


def dispatch_tool_action(*, tool: str, action: str, args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    if tool == "supabase_readonly" and action == "query":
        return _run_supabase_readonly_query(args)

    # Fallback stub for future handlers
    return {
        "stub": True,
        "tool": tool,
        "action": action,
        "args": args or {},
    }


__all__ = ["enforce_tool_allowed", "dispatch_tool_action"]
