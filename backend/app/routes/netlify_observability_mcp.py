from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlsplit

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse

from ..config import settings
from ..services import netlify_observability

router = APIRouter()

_DEFAULT_PROTOCOL_VERSION = "2025-11-25"
_FALLBACK_PROTOCOL_VERSION = "2025-03-26"
_PROTOCOL_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_LOCAL_HOSTS = {"127.0.0.1", "::1", "localhost", "testclient"}
_CORRELATION_ARGUMENT = "correlation_id"
_READ_ONLY_TOOL_SCHEMA = {
    "type": "object",
    "properties": {
        _CORRELATION_ARGUMENT: {
            "type": "string",
            "description": "Optional cross-system correlation id for observability only.",
        }
    },
    "additionalProperties": False,
}
_TOOL_DEFINITIONS = [
    {
        "name": "netlify_deploy_health",
        "description": "Return read-only Netlify deploy status diagnostics from local project state and optional read-only Netlify API data.",
        "inputSchema": _READ_ONLY_TOOL_SCHEMA,
    },
    {
        "name": "netlify_build_health",
        "description": "Return read-only Netlify build log and deploy summary diagnostics without triggering builds or deploys.",
        "inputSchema": _READ_ONLY_TOOL_SCHEMA,
    },
    {
        "name": "netlify_env_health",
        "description": "Return read-only Netlify build environment completeness diagnostics without exposing secret values.",
        "inputSchema": _READ_ONLY_TOOL_SCHEMA,
    },
    {
        "name": "netlify_connectivity_health",
        "description": "Return read-only frontend/backend connectivity readiness from Netlify config and frontend build artifacts.",
        "inputSchema": _READ_ONLY_TOOL_SCHEMA,
    },
]
_MCP_SERVER_NAME = "aveli-netlify-observability-mcp"


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
    if not settings.netlify_observability_mcp_enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    if not _client_is_local(request):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Netlify Observability MCP is restricted to local clients",
        )
    if not _origin_is_local(request.headers.get("origin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Netlify Observability MCP rejected the supplied Origin header",
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


def _string_request_id(request_id: Any) -> str:
    if isinstance(request_id, str) and request_id.strip():
        return request_id.strip()
    if request_id is None:
        return ""
    return str(request_id)


def _resolve_correlation_id(request: Request, request_id: Any, arguments: dict[str, Any]) -> str:
    argument_value = arguments.get(_CORRELATION_ARGUMENT)
    if isinstance(argument_value, str) and argument_value.strip():
        return argument_value.strip()
    header_value = request.headers.get("x-correlation-id") or request.headers.get("x-request-id")
    if header_value and header_value.strip():
        return header_value.strip()
    request_id_text = _string_request_id(request_id)
    return request_id_text or "unassigned"


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


def _tool_success(payload: dict[str, Any], *, request_id: Any, correlation_id: str, tool_name: str) -> dict[str, Any]:
    return _contract_response(
        status="ok",
        data=payload,
        query=None,
    ) | {
        "confidence": "high",
        "request_id": _string_request_id(request_id),
        "correlation_id": correlation_id,
        "tool_name": tool_name,
        "failure": None,
    }


def _tool_error(message: str, *, request_id: Any, correlation_id: str, tool_name: str | None) -> dict[str, Any]:
    return _contract_response(
        status="error",
        data={},
        query=None,
    ) | {
        "confidence": "low",
        "request_id": _string_request_id(request_id),
        "correlation_id": correlation_id,
        "tool_name": tool_name,
        "failure": {"code": "tool_call_failed", "message": message},
    }


def _unexpected_keys(arguments: dict[str, Any], allowed: set[str]) -> set[str]:
    return {key for key in arguments if key not in allowed}


async def _call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    unexpected = _unexpected_keys(arguments, {_CORRELATION_ARGUMENT})
    if unexpected:
        raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")

    if name in {"netlify_deploy_health", "get_netlify_deploy_status"}:
        return await netlify_observability.get_deploy_status()
    if name in {"netlify_build_health", "get_netlify_build_logs"}:
        return await netlify_observability.get_build_logs()
    if name in {"netlify_env_health", "get_netlify_env_completeness"}:
        return await netlify_observability.get_env_completeness()
    if name in {"netlify_connectivity_health", "get_netlify_frontend_backend_connectivity"}:
        return await netlify_observability.get_frontend_backend_connectivity()
    if name == "get_netlify_observability_summary":
        return await netlify_observability.get_netlify_observability_summary()
    raise KeyError(name)


@router.get("/mcp/netlify-observability")
async def netlify_observability_mcp_stream(request: Request) -> Response:
    _ensure_access_allowed(request)
    return JSONResponse(
        content=_contract_response(
            status="ok",
            data={},
            query="GET /mcp/netlify-observability",
        )
        | {"confidence": "low"},
        headers=_response_headers(_FALLBACK_PROTOCOL_VERSION),
    )


@router.post("/mcp/netlify-observability")
async def netlify_observability_mcp_endpoint(request: Request) -> Response:
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
                "serverInfo": {"name": _MCP_SERVER_NAME, "version": "0.1.0"},
            },
            protocol_version=protocol_version,
        )

    if method == "notifications/initialized":
        return _jsonrpc_result(request_id, {}, protocol_version=protocol_version)

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
            return _jsonrpc_result(
                request_id,
                _tool_error(
                    "Tool name is required",
                    request_id=request_id,
                    correlation_id=_resolve_correlation_id(request, request_id, {}),
                    tool_name=None,
                ),
                protocol_version=protocol_version,
            )
        tool_name = tool_name.strip("'\"")
        if not tool_name:
            return _jsonrpc_result(
                request_id,
                _tool_error(
                    "Tool name is required",
                    request_id=request_id,
                    correlation_id=_resolve_correlation_id(request, request_id, {}),
                    tool_name=None,
                ),
                protocol_version=protocol_version,
            )
        if not isinstance(arguments, dict):
            return _jsonrpc_result(
                request_id,
                _tool_error(
                    "Tool arguments must be an object",
                    request_id=request_id,
                    correlation_id=_resolve_correlation_id(request, request_id, {}),
                    tool_name=tool_name,
                ),
                protocol_version=protocol_version,
            )
        correlation_id = _resolve_correlation_id(request, request_id, arguments)
        try:
            payload = await _call_tool(name=tool_name, arguments=arguments)
        except KeyError:
            return _jsonrpc_result(
                request_id,
                _tool_error(
                    f"Unknown tool: {tool_name}",
                    request_id=request_id,
                    correlation_id=correlation_id,
                    tool_name=tool_name,
                ),
                protocol_version=protocol_version,
            )
        except ValueError as exc:
            return _jsonrpc_result(
                request_id,
                _tool_error(
                    str(exc),
                    request_id=request_id,
                    correlation_id=correlation_id,
                    tool_name=tool_name,
                ),
                protocol_version=protocol_version,
            )
        except Exception as exc:  # pragma: no cover - defensive boundary
            return _jsonrpc_result(
                request_id,
                _tool_error(
                    str(exc),
                    request_id=request_id,
                    correlation_id=correlation_id,
                    tool_name=tool_name,
                ),
                protocol_version=protocol_version,
            )
        return _jsonrpc_result(
            request_id,
            _tool_success(
                payload,
                request_id=request_id,
                correlation_id=correlation_id,
                tool_name=tool_name,
            ),
            protocol_version=protocol_version,
        )

    return _jsonrpc_error(
        request_id,
        code=-32601,
        message="Method not found",
        protocol_version=protocol_version,
    )
