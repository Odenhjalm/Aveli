from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any, Mapping, MutableMapping
from uuid import UUID

from fastapi import HTTPException, status

from context7.runtime import (
    ALLOWED_EXECUTION_TOOLS,
    Context7Object,
    ContextPermissionError,
    ContextValidationError,
    validate_context,
)

from .. import models, repositories

CONTEXT_VERSION = "2025-02-18"
SCHEMA_VERSION = "2025-02-01"

_ALLOWED_ROLES = {"admin", "teacher", "student"}


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _env_snapshot() -> dict[str, str | None]:
    return {
        "app_env": os.getenv("APP_ENV") or os.getenv("ENV") or os.getenv("ENVIRONMENT"),
        "backend_base_url": os.getenv("API_BASE_URL") or os.getenv("BACKEND_BASE_URL"),
    }


def _actor_role(user: Mapping[str, Any], *, is_teacher: bool) -> str:
    if user.get("is_admin"):
        return "admin"
    if is_teacher:
        return "teacher"
    return "student"


def _actor_scopes(role: str) -> list[str]:
    if role in {"admin", "teacher"}:
        return ["ai:execute"]
    return ["context:read"]


def _default_execution_policy(role: str) -> dict[str, Any]:
    return {
        "mode": "stub",
        "tools_allowed": sorted(ALLOWED_EXECUTION_TOOLS),
        "write_allowed": role == "admin",
        "max_steps": 10,
        "max_seconds": 60,
        "redact_logs": True,
    }


async def _ensure_course_access(course_id: str, *, user_id: str, role: str, is_teacher: bool) -> None:
    course = await models.get_course(course_id=course_id)
    if not course:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    if role in {"admin", "teacher"}:
        return

    snapshot = await models.course_access_snapshot(user_id, course_id)
    if not snapshot.get("has_access"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to course")


async def _ensure_seminar_access(seminar_id: str, *, user_id: str, role: str, is_teacher: bool) -> None:
    seminar = await repositories.get_seminar(seminar_id)
    if not seminar:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Seminar not found")

    host_id = str(seminar.get("host_id")) if seminar.get("host_id") else None
    if role == "admin" or (is_teacher and host_id == user_id):
        return

    allowed = await repositories.user_can_access_seminar(user_id, seminar_id)
    if not allowed:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to seminar")


async def _ensure_classroom_access(classroom_id: str) -> None:
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Classroom not found")


async def build_context(
    *,
    course_id: str | None,
    classroom_id: str | None,
    seminar_id: str | None,
    user: Mapping[str, Any],
) -> tuple[Context7Object, str]:
    user_id = str(user.get("id"))
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")

    is_teacher = await models.is_teacher_user(user_id)
    role = _actor_role(user, is_teacher=is_teacher)

    if not any([course_id, classroom_id, seminar_id]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one of course_id, classroom_id, seminar_id is required",
        )

    if course_id:
        await _ensure_course_access(course_id, user_id=user_id, role=role, is_teacher=is_teacher)
    if classroom_id:
        await _ensure_classroom_access(classroom_id)
    if seminar_id:
        await _ensure_seminar_access(seminar_id, user_id=user_id, role=role, is_teacher=is_teacher)

    actor_scopes = _actor_scopes(role)
    scope: MutableMapping[str, str] = {}
    if course_id:
        scope["course_id"] = course_id
    if classroom_id:
        scope["classroom_id"] = classroom_id
    if seminar_id:
        scope["seminar_id"] = seminar_id

    payload: dict[str, Any] = {
        "context_version": CONTEXT_VERSION,
        "schema_version": SCHEMA_VERSION,
        "build_timestamp": _utc_timestamp(),
        "environment": _env_snapshot(),
        "actor": {
            "id": user_id,
            "role": role,
            "scopes": actor_scopes,
        },
        "scope": scope,
        "permissions": {"scopes": actor_scopes},
        "constraints": {"readonly": role not in {"admin", "teacher"}},
        "execution_policy": _default_execution_policy(role),
    }

    required_scope = "ai:execute" if role in {"admin", "teacher"} else None

    try:
        return validate_context(
            payload,
            user_id=user_id,
            user_role=role,
            required_scope=required_scope,
            allowed_roles=set(_ALLOWED_ROLES),
        )
    except ContextPermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)) from exc
    except ContextValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


__all__ = ["build_context", "CONTEXT_VERSION", "SCHEMA_VERSION"]
