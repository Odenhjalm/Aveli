from __future__ import annotations

import logging
import time
import uuid
from typing import Any
from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, ValidationError

from ..auth import CurrentUser
from ..permissions import TeacherUser
from ..services import context7_builder, context7_gate
from ..services.tool_dispatcher import dispatch_tool_action, enforce_tool_allowed

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/ai", tags=["ai"])

EXECUTION_MAX_STEPS_LIMIT = 100
EXECUTION_MAX_SECONDS_LIMIT = 300


class AIExecuteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    context: dict[str, Any] | None = None
    input: str


class AIExecuteResponse(BaseModel):
    ok: bool
    context_hash: str
    context_version: str
    schema_version: str


class AIExecuteBuiltRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input: str
    course_id: UUID | None = None
    classroom_id: UUID | None = None
    seminar_id: UUID | None = None


class BuiltFrom(BaseModel):
    course_id: UUID | None = None
    classroom_id: UUID | None = None
    seminar_id: UUID | None = None


class ExecutionPolicySummary(BaseModel):
    mode: str
    tools_allowed: list[str]
    write_allowed: bool
    max_steps: int
    max_seconds: int


class AIExecuteBuiltResponse(BaseModel):
    ok: bool
    context_hash: str
    context_version: str
    schema_version: str
    built_from: BuiltFrom
    policy: ExecutionPolicySummary


class AIToolCallRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input: str
    course_id: UUID | None = None
    classroom_id: UUID | None = None
    seminar_id: UUID | None = None
    tool: str
    action: str
    args: dict[str, Any] | None = None


class AIToolCallResponse(BaseModel):
    ok: bool
    context_hash: str
    tool: str
    action: str
    result: dict[str, Any]


class AIPlanExecuteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input: str
    course_id: UUID | None = None
    classroom_id: UUID | None = None
    seminar_id: UUID | None = None
    args: dict[str, Any] | None = None


class PlanStep(BaseModel):
    tool: str
    action: str
    args: dict[str, Any] | None = None
    result_summary: str


class AIPlanExecuteResponse(BaseModel):
    ok: bool
    context_hash: str
    steps: list[PlanStep]
    final: dict[str, Any]


class AIPlanExecuteV1Request(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input: str
    course_id: UUID | None = None
    user_id: UUID | None = None
    limit: int | None = None


class PlanStepV1(BaseModel):
    tool: str
    action: str
    args: dict[str, Any] | None = None
    result_summary: dict[str, Any]


class AIPlanExecuteV1Response(BaseModel):
    ok: bool
    context_hash: str
    intent: str | None = None
    steps: list[PlanStepV1]
    final: dict[str, Any]
    supported_intents: list[str] | None = None
    message: str | None = None





def _request_id(request: Request) -> str:
    return (
        getattr(request.state, "request_id", None)
        or request.headers.get("X-Request-ID")
        or uuid.uuid4().hex
    )

@router.post("/execute", response_model=AIExecuteResponse)
async def execute_ai(  # type: ignore[valid-type]
    payload: AIExecuteRequest,
    request: Request,
    current: TeacherUser,
):
    request_id = _request_id(request)

    if not payload.context:
        logger.warning(
            "Context7 payload missing",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="context is required"
        )

    result = context7_gate.validate_context_payload(
        payload.context,
        user=current,
        request_id=request_id,
    )

    context_obj = result["context"]
    return AIExecuteResponse(
        ok=True,
        context_hash=result["context_hash"],
        context_version=context_obj.context_version,
        schema_version=context_obj.schema_version,
    )


@router.post("/execute-built", response_model=AIExecuteBuiltResponse)
async def execute_ai_with_built_context(request: Request, current: CurrentUser):
    request_id = _request_id(request)
    try:
        raw_payload = await request.json()
    except Exception as exc:  # pragma: no cover - surfaced in tests
        logger.warning(
            "Context7 execute-built invalid JSON",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON payload"
        ) from exc

    try:
        payload = AIExecuteBuiltRequest.model_validate(raw_payload)
    except ValidationError as exc:
        logger.warning(
            "Context7 execute-built payload rejected",
            extra={
                "request_id": request_id,
                "user_id": str(current.get("id")),
                "errors": exc.errors(),
            },
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=exc.errors()) from exc

    try:
        built_context, _ = await context7_builder.build_context(
            course_id=str(payload.course_id) if payload.course_id else None,
            classroom_id=str(payload.classroom_id) if payload.classroom_id else None,
            seminar_id=str(payload.seminar_id) if payload.seminar_id else None,
            user=current,
        )
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover - unexpected
        logger.exception(
            "Context7 execute-built failed",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to build context") from exc

    context_payload = built_context.model_dump(mode="json", exclude_none=True)
    gate_result = context7_gate.validate_context_payload(
        context_payload,
        user=current,
        request_id=request_id,
        required_scope="ai:execute",
        allowed_roles={"admin", "teacher", "student"},
    )

    context_obj = gate_result["context"]
    context_hash = gate_result["context_hash"]
    scope_payload = context_payload.get("scope") if isinstance(context_payload.get("scope"), dict) else {}

    policy = getattr(context_obj, "execution_policy", None)
    if not policy:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy missing")
    if policy.mode != "stub":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy.mode must be 'stub'")
    if policy.max_steps <= 0 or policy.max_steps > EXECUTION_MAX_STEPS_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="execution_policy.max_steps exceeds allowed limits",
        )
    if policy.max_seconds <= 0 or policy.max_seconds > EXECUTION_MAX_SECONDS_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="execution_policy.max_seconds exceeds allowed limits",
        )

    logger.info(
        "Context7 execute-built validated",
        extra={
            "request_id": request_id,
            "user_id": str(current.get("id")),
            "actor_role": getattr(context_obj.actor, "role", None),
            "course_id": scope_payload.get("course_id") if scope_payload else None,
            "classroom_id": scope_payload.get("classroom_id") if scope_payload else None,
            "seminar_id": scope_payload.get("seminar_id") if scope_payload else None,
            "context_hash": context_hash,
        },
    )

    return AIExecuteBuiltResponse(
        ok=True,
        context_hash=context_hash,
        context_version=context_obj.context_version,
        schema_version=context_obj.schema_version,
        built_from=BuiltFrom(
            course_id=payload.course_id,
            classroom_id=payload.classroom_id,
            seminar_id=payload.seminar_id,
        ),
        policy=ExecutionPolicySummary(
            mode=policy.mode,
            tools_allowed=policy.tools_allowed,
            write_allowed=policy.write_allowed,
            max_steps=policy.max_steps,
            max_seconds=policy.max_seconds,
        ),
    )


@router.post("/tool-call", response_model=AIToolCallResponse)
async def tool_call(request: Request, current: CurrentUser):
    request_id = _request_id(request)
    try:
        raw_payload = await request.json()
    except Exception as exc:  # pragma: no cover - surfaced in tests
        logger.warning(
            "Context7 tool-call invalid JSON",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON payload") from exc

    try:
        payload = AIToolCallRequest.model_validate(raw_payload)
    except ValidationError as exc:
        logger.warning(
            "Context7 tool-call payload rejected",
            extra={
                "request_id": request_id,
                "user_id": str(current.get("id")),
                "errors": exc.errors(),
            },
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=exc.errors()) from exc

    if not any([payload.course_id, payload.classroom_id, payload.seminar_id]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one of course_id, classroom_id, seminar_id is required",
        )

    built_context, _ = await context7_builder.build_context(
        course_id=str(payload.course_id) if payload.course_id else None,
        classroom_id=str(payload.classroom_id) if payload.classroom_id else None,
        seminar_id=str(payload.seminar_id) if payload.seminar_id else None,
        user=current,
    )

    context_payload = built_context.model_dump(mode="json", exclude_none=True)
    gate_result = context7_gate.validate_context_payload(
        context_payload,
        user=current,
        request_id=request_id,
        required_scope="ai:execute",
        allowed_roles={"admin", "teacher", "student"},
    )

    context_obj = gate_result["context"]
    context_hash = gate_result["context_hash"]

    policy = getattr(context_obj, "execution_policy", None)
    if not policy:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy missing")

    enforce_tool_allowed(
        tool=payload.tool,
        action=payload.action,
        tools_allowed=policy.tools_allowed,
    )

    result = dispatch_tool_action(tool=payload.tool, action=payload.action, args=payload.args, actor_role=getattr(context_obj.actor, "role", None), scope=context_payload.get("scope") if isinstance(context_payload.get("scope"), dict) else {})

    return AIToolCallResponse(
        ok=True,
        context_hash=context_hash,
        tool=payload.tool,
        action=payload.action,
        result=dict(result),
    )


@router.post("/plan-and-execute", response_model=AIPlanExecuteResponse)
async def plan_and_execute(request: Request, current: CurrentUser):
    request_id = _request_id(request)
    try:
        raw_payload = await request.json()
    except Exception as exc:  # pragma: no cover - surfaced in tests
        logger.warning(
            "Context7 plan-and-execute invalid JSON",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON payload") from exc

    try:
        payload = AIPlanExecuteRequest.model_validate(raw_payload)
    except ValidationError as exc:
        logger.warning(
            "Context7 plan-and-execute payload rejected",
            extra={
                "request_id": request_id,
                "user_id": str(current.get("id")),
                "errors": exc.errors(),
            },
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=exc.errors()) from exc

    if not any([payload.course_id, payload.classroom_id, payload.seminar_id]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one of course_id, classroom_id, seminar_id is required",
        )

    built_context, _ = await context7_builder.build_context(
        course_id=str(payload.course_id) if payload.course_id else None,
        classroom_id=str(payload.classroom_id) if payload.classroom_id else None,
        seminar_id=str(payload.seminar_id) if payload.seminar_id else None,
        user=current,
    )

    context_payload = built_context.model_dump(mode="json", exclude_none=True)
    gate_result = context7_gate.validate_context_payload(
        context_payload,
        user=current,
        request_id=request_id,
        required_scope="ai:execute",
        allowed_roles={"admin", "teacher", "student"},
    )

    context_obj = gate_result["context"]
    context_hash = gate_result["context_hash"]

    policy = getattr(context_obj, "execution_policy", None)
    if not policy:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy missing")
    if policy.mode != "stub":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy.mode must be 'stub'")
    if policy.max_steps <= 0 or policy.max_steps > EXECUTION_MAX_STEPS_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="execution_policy.max_steps exceeds allowed limits",
        )
    if policy.max_seconds <= 0 or policy.max_seconds > EXECUTION_MAX_SECONDS_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="execution_policy.max_seconds exceeds allowed limits",
        )

    start_time = time.monotonic()

    def enforce_time_limit() -> None:
        if time.monotonic() - start_time > policy.max_seconds:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="execution_policy.max_seconds exceeded",
            )

    steps: list[PlanStep] = []
    lower_input = payload.input.lower()

    if "select" not in lower_input:
        enforce_time_limit()
        return AIPlanExecuteResponse(
            ok=True,
            context_hash=context_hash,
            steps=steps,
            final={"message": "Only SELECT queries via supabase_readonly.query are supported"},
        )

    if policy.max_steps < 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="execution_policy.max_steps exceeded",
        )

    enforce_time_limit()

    tool = "supabase_readonly"
    action = "query"

    enforce_tool_allowed(
        tool=tool,
        action=action,
        tools_allowed=policy.tools_allowed,
    )

    result = dispatch_tool_action(tool=tool, action=action, args=payload.args, actor_role=getattr(context_obj.actor, "role", None), scope=context_payload.get("scope") if isinstance(context_payload.get("scope"), dict) else {})

    steps.append(
        PlanStep(
            tool=tool,
            action=action,
            args=payload.args or {},
            result_summary=f"row_count={result.get('row_count', 0)}, truncated={result.get('truncated', False)}",
        )
    )

    enforce_time_limit()

    if len(steps) > policy.max_steps:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="execution_policy.max_steps exceeded",
        )

    return AIPlanExecuteResponse(
        ok=True,
        context_hash=context_hash,
        steps=steps,
        final=dict(result),
    )

SUPPORTED_INTENTS_V1 = [
    "list_course_students",
    "get_user_summary",
    "get_course_progress",
    "list_intro_courses",
]


@router.post("/plan-and-execute-v1", response_model=AIPlanExecuteV1Response)
async def plan_and_execute_v1(request: Request, current: CurrentUser):
    request_id = _request_id(request)
    try:
        raw_payload = await request.json()
    except Exception as exc:  # pragma: no cover - surfaced in tests
        logger.warning(
            "Context7 plan-and-execute-v1 invalid JSON",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON payload") from exc

    try:
        payload = AIPlanExecuteV1Request.model_validate(raw_payload)
    except ValidationError as exc:
        logger.warning(
            "Context7 plan-and-execute-v1 payload rejected",
            extra={
                "request_id": request_id,
                "user_id": str(current.get("id")),
                "errors": exc.errors(),
            },
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=exc.errors()) from exc

    if not payload.course_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="course_id is required",
        )

    built_context, _ = await context7_builder.build_context(
        course_id=str(payload.course_id),
        classroom_id=None,
        seminar_id=None,
        user=current,
    )

    context_payload = built_context.model_dump(mode="json", exclude_none=True)
    gate_result = context7_gate.validate_context_payload(
        context_payload,
        user=current,
        request_id=request_id,
        required_scope="ai:execute",
        allowed_roles={"admin", "teacher", "student"},
    )

    context_obj = gate_result["context"]
    context_hash = gate_result["context_hash"]
    actor_role = getattr(context_obj.actor, "role", None)
    scope_payload = context_payload.get("scope") if isinstance(context_payload.get("scope"), dict) else {}

    policy = getattr(context_obj, "execution_policy", None)
    if not policy:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy missing")
    if policy.mode != "stub":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy.mode must be 'stub'")
    if policy.max_steps <= 0 or policy.max_steps > EXECUTION_MAX_STEPS_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="execution_policy.max_steps exceeds allowed limits",
        )
    if policy.max_seconds <= 0 or policy.max_seconds > EXECUTION_MAX_SECONDS_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="execution_policy.max_seconds exceeds allowed limits",
        )
    if "supabase_readonly" not in policy.tools_allowed:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Tool supabase_readonly not allowed")

    start_time = time.monotonic()

    def enforce_time_limit() -> None:
        if time.monotonic() - start_time > policy.max_seconds:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="execution_policy.max_seconds exceeded",
            )

    def intent_response_ok_false(message: str):
        return AIPlanExecuteV1Response(
            ok=False,
            context_hash=context_hash,
            intent=None,
            steps=[],
            final={},
            supported_intents=SUPPORTED_INTENTS_V1,
            message=message,
        )

    lower_input = payload.input.lower().strip()
    intent = None
    action_args: dict[str, Any] = {}
    tool = "supabase_readonly"
    action = None

    if "list students" in lower_input or lower_input == "students":
        intent = "list_course_students"
        if not payload.course_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="course_id is required")
        action_args = {"course_id": str(payload.course_id), "limit": payload.limit}
        action = "list_course_students"
    elif "user summary" in lower_input or "summary user" in lower_input:
        intent = "get_user_summary"
        if not payload.user_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="user_id is required")
        action_args = {"user_id": str(payload.user_id)}
        action = "get_user_summary"
    elif "course progress" in lower_input or lower_input == "progress":
        intent = "get_course_progress"
        if not payload.user_id or not payload.course_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="user_id and course_id are required")
        action_args = {"user_id": str(payload.user_id), "course_id": str(payload.course_id)}
        action = "get_course_progress"
    elif "intro courses" in lower_input or "list intro courses" in lower_input:
        intent = "list_intro_courses"
        action_args = {"limit": payload.limit}
        action = "list_intro_courses"

    if intent is None or action is None:
        enforce_time_limit()
        return intent_response_ok_false("Supported: list students, user summary, course progress, intro courses")

    if policy.max_steps < 1:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy.max_steps exceeded")

    enforce_time_limit()

    result = dispatch_tool_action(
        tool=tool,
        action=action,
        args=action_args,
        actor_role=actor_role,
        scope=scope_payload,
    )

    steps = [
        PlanStepV1(
            tool=tool,
            action=action,
            args=action_args,
            result_summary={
                "row_count": result.get("row_count", 0),
                "truncated": result.get("truncated", False),
            },
        )
    ]

    enforce_time_limit()

    if len(steps) > policy.max_steps:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="execution_policy.max_steps exceeded")

    return AIPlanExecuteV1Response(
        ok=True,
        context_hash=context_hash,
        intent=intent,
        steps=steps,
        final=dict(result),
    )
