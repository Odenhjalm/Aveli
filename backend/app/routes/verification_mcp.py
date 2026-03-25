from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlsplit

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse

from ..config import settings
from ..services import verification_observability

router = APIRouter()

_DEFAULT_PROTOCOL_VERSION = "2025-11-25"
_FALLBACK_PROTOCOL_VERSION = "2025-03-26"
_PROTOCOL_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_LOCAL_HOSTS = {"127.0.0.1", "::1", "localhost", "testclient"}
_TOOL_DEFINITIONS = [
    {
        "name": "verify_lesson_media_truth",
        "description": "Verify a lesson's authored lesson_media, runtime projection, canonical resolver result, and recent media failure signals without manual correlation.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "lesson_id": {
                    "type": "string",
                    "description": "Lesson UUID.",
                }
            },
            "required": ["lesson_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "verify_course_cover_truth",
        "description": "Verify a course cover against canonical cover resolution, media control-plane asset truth, and recent media failure signals.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "course_id": {
                    "type": "string",
                    "description": "Course UUID.",
                }
            },
            "required": ["course_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "verify_phase2_truth_alignment",
        "description": "Run a bounded high-level phase-2 alignment verification across sampled lesson media and course cover cases, worker health, and recent errors.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "get_test_cases",
        "description": "Return bounded deterministic lesson and course ids that are good candidates for verification tool calls.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
]
_MCP_SERVER_NAME = "aveli-verification-mcp"


def _client_is_local(request: Request) -> bool:
    client_host = (request.client.host if request.client else "") or ""
    return client_host in _LOCAL_HOSTS


def _origin_is_local(origin: str | None) -> bool:
    if not origin:
        return True
    try:
        parsed = urlsplit(origin)
    except ValueError:
        return False
    return (parsed.hostname or "").strip().lower() in _LOCAL_HOSTS


def _ensure_access_allowed(request: Request) -> None:
    if not settings.verification_mcp_enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    if not _client_is_local(request):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Verification MCP is restricted to local clients",
        )
    if not _origin_is_local(request.headers.get("origin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Verification MCP rejected the supplied Origin header",
        )


def _resolve_protocol_version(request: Request, initialize_version: str | None = None) -> str:
    candidate = initialize_version or request.headers.get("MCP-Protocol-Version")
    if not candidate:
        return _DEFAULT_PROTOCOL_VERSION if initialize_version else _FALLBACK_PROTOCOL_VERSION
    normalized = str(candidate).strip()
    if not _PROTOCOL_DATE_RE.fullmatch(normalized):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid MCP-Protocol-Version header",
        )
    return normalized


def _response_headers(protocol_version: str) -> dict[str, str]:
    return {"MCP-Protocol-Version": protocol_version}


def _contract_response(*, status: str, data: dict[str, Any], query: str | None) -> dict[str, Any]:
    source = {"server": _MCP_SERVER_NAME, "timestamp": datetime.now(timezone.utc).isoformat()}
    if query:
        source["query"] = query
    payload = {
        "status": status,
        "data": data,
        "source": source,
    }
    return payload


def _jsonrpc_result(request_id: Any, result: dict[str, Any], *, protocol_version: str) -> JSONResponse:
    return JSONResponse(
        content={"jsonrpc": "2.0", "id": request_id, "result": result},
        headers=_response_headers(protocol_version),
    )


def _jsonrpc_error(
    request_id: Any,
    *,
    code: int,
    message: str,
    protocol_version: str,
    http_status: int = status.HTTP_200_OK,
) -> JSONResponse:
    return JSONResponse(
        status_code=http_status,
        content={
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": code, "message": message},
        },
        headers=_response_headers(protocol_version),
    )


def _tool_success(payload: dict[str, Any]) -> dict[str, Any]:
    normalized_payload = dict(payload)
    normalized_payload.setdefault("environment", settings.mcp_environment)
    return _contract_response(
        status="ok",
        data=normalized_payload,
        query="tools/call",
    ) | {"confidence": "high"}


def _tool_error(message: str) -> dict[str, Any]:
    return _contract_response(
        status="error",
        data={"error": message},
        query="tools/call",
    ) | {"confidence": "low"}


def _unexpected_keys(arguments: dict[str, Any], allowed: set[str]) -> set[str]:
    return {key for key in arguments if key not in allowed}


def _required_string(arguments: dict[str, Any], field: str) -> str:
    value = arguments.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} is required")
    return value.strip()


async def _call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "verify_lesson_media_truth":
        unexpected = _unexpected_keys(arguments, {"lesson_id"})
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await verification_observability.verify_lesson_media_truth(
            lesson_id=_required_string(arguments, "lesson_id")
        )

    if name == "verify_course_cover_truth":
        unexpected = _unexpected_keys(arguments, {"course_id"})
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await verification_observability.verify_course_cover_truth(
            course_id=_required_string(arguments, "course_id")
        )

    if name == "verify_phase2_truth_alignment":
        unexpected = _unexpected_keys(arguments, set())
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await verification_observability.verify_phase2_truth_alignment()

    if name == "get_test_cases":
        unexpected = _unexpected_keys(arguments, set())
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await verification_observability.get_test_cases()

    raise KeyError(name)


@router.get("/mcp/verification")
async def verification_mcp_stream(request: Request) -> Response:
    _ensure_access_allowed(request)
    return JSONResponse(
        content=_contract_response(
            status="ok",
            data={},
            query="GET /mcp/verification",
        )
        | {"confidence": "low"},
        headers=_response_headers(_FALLBACK_PROTOCOL_VERSION),
    )


@router.post("/mcp/verification")
async def verification_mcp_endpoint(request: Request) -> Response:
    _ensure_access_allowed(request)
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        return _jsonrpc_error(
            None,
            code=-32700,
            message="Parse error",
            protocol_version=_FALLBACK_PROTOCOL_VERSION,
            http_status=status.HTTP_400_BAD_REQUEST,
        )

    if not isinstance(payload, dict):
        return _jsonrpc_error(
            None,
            code=-32600,
            message="Batch requests are not supported",
            protocol_version=_FALLBACK_PROTOCOL_VERSION,
            http_status=status.HTTP_400_BAD_REQUEST,
        )

    method = payload.get("method")
    request_id = payload.get("id")

    if "id" not in payload:
        return Response(
            status_code=status.HTTP_202_ACCEPTED,
            headers=_response_headers(_FALLBACK_PROTOCOL_VERSION),
        )

    if not isinstance(method, str) or not method.strip():
        return _jsonrpc_error(
            request_id,
            code=-32600,
            message="Invalid request",
            protocol_version=_FALLBACK_PROTOCOL_VERSION,
        )

    params = payload.get("params") or {}
    if not isinstance(params, dict):
        return _jsonrpc_error(
            request_id,
            code=-32602,
            message="Request params must be an object",
            protocol_version=_FALLBACK_PROTOCOL_VERSION,
        )

    protocol_version = _resolve_protocol_version(
        request,
        initialize_version=(
            str(params.get("protocolVersion"))
            if method == "initialize" and params.get("protocolVersion") is not None
            else None
        ),
    )

    if method == "initialize":
        return _jsonrpc_result(
            request_id,
            {
                "protocolVersion": protocol_version,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "aveli-verification-mcp", "version": "0.1.0"},
            },
            protocol_version=protocol_version,
        )

    if method == "notifications/initialized":
        return _jsonrpc_result(
            request_id,
            {},
            protocol_version=protocol_version,
        )

    if method == "tools/list":
        return _jsonrpc_result(
            request_id,
            {"tools": _TOOL_DEFINITIONS},
            protocol_version=protocol_version,
        )

    if method == "tools/call":
        tool_name = params.get("name")
        arguments = params.get("arguments") or {}
        if not isinstance(tool_name, str) or not tool_name.strip():
            return _jsonrpc_error(
                request_id,
                code=-32602,
                message="Tool name is required",
                protocol_version=protocol_version,
            )
        tool_name = tool_name.strip("'\"")
        if not tool_name:
            return _jsonrpc_error(
                request_id,
                code=-32602,
                message="Tool name is required",
                protocol_version=protocol_version,
            )
        if not isinstance(arguments, dict):
            return _jsonrpc_error(
                request_id,
                code=-32602,
                message="Tool arguments must be an object",
                protocol_version=protocol_version,
            )
        try:
            tool_payload = await _call_tool(name=tool_name, arguments=arguments)
        except KeyError:
            return _jsonrpc_error(
                request_id,
                code=-32601,
                message=f"Unknown tool: {tool_name}",
                protocol_version=protocol_version,
            )
        except ValueError as exc:
            return _jsonrpc_error(
                request_id,
                code=-32602,
                message=str(exc),
                protocol_version=protocol_version,
            )
        except Exception as exc:  # pragma: no cover - defensive boundary
            return _jsonrpc_result(
                request_id,
                _tool_error(str(exc)),
                protocol_version=protocol_version,
            )
        return _jsonrpc_result(
            request_id,
            _tool_success(tool_payload),
            protocol_version=protocol_version,
        )

    return _jsonrpc_error(
        request_id,
        code=-32601,
        message=f"Method not found: {method}",
        protocol_version=protocol_version,
    )
