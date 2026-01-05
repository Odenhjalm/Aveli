from __future__ import annotations

from typing import Any, Mapping

from fastapi import HTTPException, status

_ALLOWED_ACTIONS: dict[str, set[str]] = {
    "supabase_readonly": {"query", "get"},
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


def dispatch_stub(*, tool: str, action: str, args: Mapping[str, Any] | None) -> Mapping[str, Any]:
    # Stubbed tool execution placeholder
    return {"stub": True, "tool": tool, "action": action, "args": args or {}}


__all__ = ["enforce_tool_allowed", "dispatch_stub"]
