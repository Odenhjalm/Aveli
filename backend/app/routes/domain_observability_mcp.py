from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlsplit

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse

from ..config import settings
from ..services import domain_observability

router = APIRouter()

_DEFAULT_PROTOCOL_VERSION = "2025-11-25"
_FALLBACK_PROTOCOL_VERSION = "2025-03-26"
_PROTOCOL_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_LOCAL_HOSTS = {"127.0.0.1", "::1", "localhost", "testclient"}
_TOOL_DEFINITIONS = [
    {
        "name": "inspect_user",
        "description": "Return a deterministic user-domain snapshot covering auth, profile, onboarding, membership, authored courses, enrolled courses, and entitlements.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "user_id": {
                    "type": "string",
                    "description": "User UUID.",
                }
            },
            "required": ["user_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "inspect_media",
        "description": "Return a deterministic domain-level media inspection for either one asset or one lesson's media set using existing control-plane and logs truth.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "asset_id": {
                    "type": "string",
                    "description": "Optional media asset UUID.",
                },
                "lesson_id": {
                    "type": "string",
                    "description": "Optional lesson UUID.",
                },
            },
            "additionalProperties": False,
        },
    },
]
_MCP_SERVER_NAME = "aveli-domain-observability-mcp"


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
    if not settings.domain_observability_mcp_enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    if not _client_is_local(request):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Domain Observability MCP is restricted to local clients",
        )
    if not _origin_is_local(request.headers.get("origin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Domain Observability MCP rejected the supplied Origin header",
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
    return {
        "status": status,
        "data": data,
        "source": source,
    }


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


def _optional_string(arguments: dict[str, Any], field: str) -> str | None:
    value = arguments.get(field)
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError(f"{field} must be a string")
    normalized = value.strip()
    return normalized or None


async def _call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "inspect_user":
        unexpected = _unexpected_keys(arguments, {"user_id"})
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        return await domain_observability.inspect_user(
            user_id=_required_string(arguments, "user_id")
        )

    if name == "inspect_media":
        unexpected = _unexpected_keys(arguments, {"asset_id", "lesson_id"})
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        asset_id = _optional_string(arguments, "asset_id")
        lesson_id = _optional_string(arguments, "lesson_id")
        if bool(asset_id) == bool(lesson_id):
            raise ValueError("Exactly one of asset_id or lesson_id is required")
        return await domain_observability.inspect_media(
            asset_id=asset_id,
            lesson_id=lesson_id,
        )

    raise KeyError(name)


@router.get("/mcp/domain-observability")
async def domain_observability_mcp_stream(request: Request) -> Response:
    _ensure_access_allowed(request)
    return JSONResponse(
        content=_contract_response(
            status="ok",
            data={},
            query="GET /mcp/domain-observability",
        )
        | {"confidence": "low"},
        headers=_response_headers(_FALLBACK_PROTOCOL_VERSION),
    )


@router.post("/mcp/domain-observability")
async def domain_observability_mcp_endpoint(request: Request) -> Response:
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

    if method == "initialize":
        params = payload.get("params") or {}
        initialize_version = params.get("protocolVersion")
        protocol_version = _resolve_protocol_version(request, initialize_version)
        return _jsonrpc_result(
            request_id,
            {
                "protocolVersion": protocol_version,
                "serverInfo": {
                    "name": "aveli-domain-observability-mcp",
                    "version": "0.1.0",
                },
                "capabilities": {"tools": {}},
            },
            protocol_version=protocol_version,
        )

    try:
        protocol_version = _resolve_protocol_version(request)
    except HTTPException as exc:
        return _jsonrpc_error(
            request_id,
            code=-32600,
            message=exc.detail,
            protocol_version=_FALLBACK_PROTOCOL_VERSION,
            http_status=exc.status_code,
        )

    if method == "notifications/initialized":
        return Response(
            status_code=status.HTTP_202_ACCEPTED,
            headers=_response_headers(protocol_version),
        )

    if method == "tools/list":
        return _jsonrpc_result(
            request_id,
            {"tools": _TOOL_DEFINITIONS},
            protocol_version=protocol_version,
        )

    if method == "tools/call":
        params = payload.get("params") or {}
        tool_name = params.get("name")
        arguments = params.get("arguments") or {}
        if not isinstance(tool_name, str) or not tool_name:
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
            tool_payload = await _call_tool(tool_name, arguments)
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
        except Exception as exc:  # pragma: no cover - defensive transport guard
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
