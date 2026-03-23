from __future__ import annotations

import json
import re
from typing import Any
from urllib.parse import urlsplit

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse

from ..config import settings
from ..services import media_control_plane_observability

router = APIRouter()

_DEFAULT_PROTOCOL_VERSION = "2025-11-25"
_FALLBACK_PROTOCOL_VERSION = "2025-03-26"
_PROTOCOL_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_LOCAL_HOSTS = {"127.0.0.1", "::1", "localhost", "testclient"}
_TOOL_DEFINITIONS = [
    {
        "name": "get_asset",
        "description": "Return the normalized control-plane snapshot for a media asset, including lesson references, runtime projections, timestamps, and detected inconsistencies.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "asset_id": {
                    "type": "string",
                    "description": "Media asset UUID.",
                }
            },
            "required": ["asset_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "trace_asset_lifecycle",
        "description": "Return a deterministic reconstructed lifecycle view for a media asset, including inferred snapshot transitions, observed resolution failures, and related structured log events.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "asset_id": {
                    "type": "string",
                    "description": "Media asset UUID.",
                }
            },
            "required": ["asset_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "list_orphaned_assets",
        "description": "Return a bounded inspection of unlinked control-plane assets missing lesson/runtime references, explicitly separating strict orphans, grace-window uploads, stalled assets, and home-upload runtime projection gaps.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "validate_runtime_projection",
        "description": "Validate runtime_media rows for a lesson against the expected lesson_media contract shape, current asset links, and canonical resolver behavior without mutating state.",
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
]


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
    if not settings.media_control_plane_mcp_enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    if not _client_is_local(request):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Media Control Plane MCP is restricted to local clients",
        )
    if not _origin_is_local(request.headers.get("origin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Media Control Plane MCP rejected the supplied Origin header",
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
    return {
        "content": [
            {
                "type": "text",
                "text": json.dumps(
                    normalized_payload,
                    ensure_ascii=False,
                    indent=2,
                    sort_keys=True,
                ),
            }
        ]
    }


def _tool_error(message: str) -> dict[str, Any]:
    return {
        "content": [
            {
                "type": "text",
                "text": json.dumps(
                    {"error": message},
                    ensure_ascii=False,
                    indent=2,
                    sort_keys=True,
                ),
            }
        ],
        "isError": True,
    }


def _unexpected_keys(arguments: dict[str, Any], allowed: set[str]) -> set[str]:
    return {key for key in arguments if key not in allowed}


def _required_string(arguments: dict[str, Any], field: str) -> str:
    value = arguments.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} is required")
    return value.strip()


async def _call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "get_asset":
        unexpected = _unexpected_keys(arguments, {"asset_id"})
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await media_control_plane_observability.get_asset(
            asset_id=_required_string(arguments, "asset_id")
        )

    if name == "trace_asset_lifecycle":
        unexpected = _unexpected_keys(arguments, {"asset_id"})
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await media_control_plane_observability.trace_asset_lifecycle(
            asset_id=_required_string(arguments, "asset_id")
        )

    if name == "list_orphaned_assets":
        unexpected = _unexpected_keys(arguments, set())
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await media_control_plane_observability.list_orphaned_assets()

    if name == "validate_runtime_projection":
        unexpected = _unexpected_keys(arguments, {"lesson_id"})
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await media_control_plane_observability.validate_runtime_projection(
            lesson_id=_required_string(arguments, "lesson_id")
        )

    raise KeyError(name)


@router.get("/mcp/media-control-plane")
async def media_control_plane_mcp_stream(request: Request) -> Response:
    _ensure_access_allowed(request)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/mcp/media-control-plane")
async def media_control_plane_mcp_endpoint(request: Request) -> Response:
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
                "serverInfo": {
                    "name": "aveli-media-control-plane-mcp",
                    "version": "0.1.0",
                },
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
        name = params.get("name")
        arguments = params.get("arguments") or {}
        if not isinstance(name, str) or not name.strip():
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
            tool_payload = await _call_tool(name=name, arguments=arguments)
        except KeyError:
            return _jsonrpc_error(
                request_id,
                code=-32601,
                message=f"Unknown tool: {name}",
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
