"""Thin MCP transport wrapper for Aveli canonical retrieval."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
INDEX_TOOL_ROOT = REPO_ROOT / "tools" / "index"
SEARCH_PYTHON = REPO_ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"
CANONICAL_RETRIEVAL_REQUIRED = "FEL: MCP kraver kanoniskt retrieval-granssnitt"

if Path(sys.executable).resolve() != SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: MCP semantic-search maste koras med kanonisk Windows-tolk: "
        f"{SEARCH_PYTHON}"
    )

if str(INDEX_TOOL_ROOT) not in sys.path:
    sys.path.insert(0, str(INDEX_TOOL_ROOT))

from retrieval_observability import (
    RETRIEVAL_ARTIFACT_HEALTH_PATH,
    RETRIEVAL_DEPENDENCY_HEALTH_PATH,
    RETRIEVAL_LAST_BUILD_STATUS_PATH,
    RETRIEVAL_MODEL_HEALTH_PATH,
    RETRIEVAL_RUNTIME_HEALTH_PATH,
    RetrievalObservabilityError,
    base_surface,
    display_path,
    load_json_object,
    read_last_query_trace,
    read_recent_query_traces,
)


class CanonicalRetrievalUnavailable(RuntimeError):
    def __init__(self) -> None:
        super().__init__(CANONICAL_RETRIEVAL_REQUIRED)
        self.classification = "STOP"


class CanonicalRetrievalStopped(RuntimeError):
    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.classification = "STOP"


def _string_request_id(request_id: Any) -> str:
    if request_id is None:
        return "semantic-mcp-request"
    normalized = str(request_id).strip()
    return normalized or "semantic-mcp-request"


def _resolve_mcp_correlation_id(request_id: str) -> str:
    for env_var in ("AVELI_RETRIEVAL_CORRELATION_ID", "AVELI_CORRELATION_ID", "MCP_CORRELATION_ID", "CORRELATION_ID"):
        value = os.environ.get(env_var, "").strip()
        if value:
            return value
    return request_id


def _with_retrieval_trace_env(request_id: str, correlation_id: str):
    class RetrievalTraceEnv:
        def __enter__(self):
            self.previous = {
                "AVELI_RETRIEVAL_REQUEST_ID": os.environ.get("AVELI_RETRIEVAL_REQUEST_ID"),
                "AVELI_RETRIEVAL_CORRELATION_ID": os.environ.get("AVELI_RETRIEVAL_CORRELATION_ID"),
            }
            os.environ["AVELI_RETRIEVAL_REQUEST_ID"] = request_id
            os.environ["AVELI_RETRIEVAL_CORRELATION_ID"] = correlation_id

        def __exit__(self, exc_type, exc, tb):
            for key, value in self.previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

    return RetrievalTraceEnv()


def call_canonical_retrieval(query: str, *, request_id: str, correlation_id: str) -> Any:
    try:
        from search_code import handle_query_json
    except Exception as exc:
        raise CanonicalRetrievalUnavailable() from exc
    try:
        with _with_retrieval_trace_env(request_id, correlation_id):
            return json.loads(handle_query_json(query))
    except SystemExit as exc:
        message = str(exc) or CANONICAL_RETRIEVAL_REQUIRED
        raise CanonicalRetrievalStopped(message) from exc


def _write_json(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))
    sys.stdout.write("\n")
    sys.stdout.flush()


def _error(request_id, code: int, message: str, data=None) -> dict:
    response = {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": code, "message": message},
    }
    if data is not None:
        response["error"]["data"] = data
    return response


def _initialize_response(request_id):
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {
                "name": "aveli-semantic-search",
                "version": "0.2.0",
            },
        },
    }


def _tools_list_response(request_id):
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "tools": [
                {
                    "name": "semantic_search",
                    "description": "Kanonisk Aveli-retrievaltransport med evidence envelope.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "query": {"type": "string"},
                        },
                        "required": ["query"],
                        "additionalProperties": False,
                    },
                },
                {
                    "name": "retrieval_runtime_health",
                    "description": "Las kanonisk retrieval runtime health telemetry.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "name": "retrieval_last_query_trace",
                    "description": "Las senaste kanoniska retrieval query trace.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "name": "retrieval_recent_query_traces",
                    "description": "Las senaste kanoniska retrieval query traces.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "limit": {"type": "integer", "minimum": 1, "maximum": 50},
                        },
                        "additionalProperties": False,
                    },
                },
                {
                    "name": "semantic_mcp_health",
                    "description": "Las semantic MCP health sammanstalld fran observability-filer.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                }
            ]
        },
    }


def _unexpected_keys(arguments: dict[str, Any], allowed: set[str]) -> set[str]:
    return {key for key in arguments if key not in allowed}


def _require_no_arguments(arguments: dict[str, Any]) -> None:
    unexpected = _unexpected_keys(arguments, set())
    if unexpected:
        raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")


def _validate_tool_call(params: dict) -> tuple[str, dict[str, Any]]:
    name = params.get("name")
    known_tools = {
        "semantic_search",
        "retrieval_runtime_health",
        "retrieval_last_query_trace",
        "retrieval_recent_query_traces",
        "semantic_mcp_health",
    }
    if name not in known_tools:
        raise ValueError(f"Okant verktyg: {name}")

    args = params.get("arguments") or {}
    if not isinstance(args, dict):
        raise ValueError("arguments maste vara ett JSON-objekt")

    if name != "retrieval_recent_query_traces":
        allowed = {"query"} if name == "semantic_search" else set()
        unexpected = _unexpected_keys(args, allowed)
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")

    if name == "retrieval_recent_query_traces":
        unexpected = _unexpected_keys(args, {"limit"})
        if unexpected:
            raise ValueError(f"Unexpected arguments: {', '.join(sorted(unexpected))}")
        if "limit" in args:
            limit = args["limit"]
            if not isinstance(limit, int) or isinstance(limit, bool) or limit < 1 or limit > 50:
                raise ValueError("limit maste vara ett heltal mellan 1 och 50")

    if name != "semantic_search":
        return name, args

    query = args.get("query")
    if not isinstance(query, str) or query == "":
        raise ValueError("query maste vara en icke-tom strang")
    return name, args


def _read_health_file(path: Path) -> dict[str, Any]:
    try:
        return load_json_object(path, display_path(path))
    except RetrievalObservabilityError as exc:
        raise CanonicalRetrievalStopped(str(exc)) from exc


def _last_trace_surface() -> dict[str, Any]:
    trace = read_last_query_trace()
    payload = base_surface("retrieval_last_query_trace", "PASS" if trace else "NO_DATA")
    payload["data"] = {"trace": trace}
    return payload


def _recent_traces_surface(limit: int) -> dict[str, Any]:
    traces = read_recent_query_traces(limit=limit)
    payload = base_surface("retrieval_recent_query_traces", "PASS" if traces else "NO_DATA")
    payload["data"] = {"limit": limit, "traces": traces}
    return payload


def _semantic_mcp_health_surface() -> dict[str, Any]:
    health_files = {
        "retrieval_runtime_health": RETRIEVAL_RUNTIME_HEALTH_PATH,
        "retrieval_artifact_health": RETRIEVAL_ARTIFACT_HEALTH_PATH,
        "retrieval_model_health": RETRIEVAL_MODEL_HEALTH_PATH,
        "retrieval_dependency_health": RETRIEVAL_DEPENDENCY_HEALTH_PATH,
        "retrieval_last_build_status": RETRIEVAL_LAST_BUILD_STATUS_PATH,
    }
    file_status = {
        name: {
            "path": display_path(path),
            "exists": path.exists(),
            "status": _read_health_file(path).get("status") if path.exists() else "MISSING",
        }
        for name, path in health_files.items()
    }
    payload = base_surface(
        "semantic_mcp_health",
        "PASS" if all(item["exists"] for item in file_status.values()) else "BLOCKED",
    )
    payload.update(
        {
            "server_name": "aveli-semantic-search",
            "transport": "stdio",
            "canonical_interpreter": display_path(SEARCH_PYTHON),
            "tools": [
                "semantic_search",
                "retrieval_runtime_health",
                "retrieval_last_query_trace",
                "retrieval_recent_query_traces",
                "semantic_mcp_health",
            ],
            "health_files": file_status,
        }
    )
    return payload


def _tool_payload(name: str, arguments: dict[str, Any], request_id: Any) -> dict[str, Any]:
    if name == "semantic_search":
        request_id_text = _string_request_id(request_id)
        correlation_id = _resolve_mcp_correlation_id(request_id_text)
        evidence = call_canonical_retrieval(
            arguments["query"],
            request_id=request_id_text,
            correlation_id=correlation_id,
        )
        return {
            "status": "ok",
            "request_id": request_id_text,
            "correlation_id": correlation_id,
            "tool_name": "semantic_search",
            "data": {"evidence": evidence},
            "failure": None,
        }
    if name == "retrieval_runtime_health":
        _require_no_arguments(arguments)
        return _read_health_file(RETRIEVAL_RUNTIME_HEALTH_PATH)
    if name == "retrieval_last_query_trace":
        _require_no_arguments(arguments)
        return _last_trace_surface()
    if name == "retrieval_recent_query_traces":
        return _recent_traces_surface(int(arguments.get("limit", 10)))
    if name == "semantic_mcp_health":
        _require_no_arguments(arguments)
        return _semantic_mcp_health_surface()
    raise ValueError(f"Okant verktyg: {name}")


def _tools_call_response(request_id, params):
    name, arguments = _validate_tool_call(params)
    canonical_payload = _tool_payload(name, arguments, request_id)
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": canonical_payload,
    }


def _exception_response(request_id, exc: Exception) -> dict:
    classification = getattr(exc, "classification", "STOP")
    message = str(exc) or "FEL: MCP-anrop stoppades"
    return _error(
        request_id,
        -32000,
        message,
        {
            "classification": classification,
            "message": message,
        },
    )


def main():
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue

        try:
            request = json.loads(raw)
        except json.JSONDecodeError:
            _write_json(_error(None, -32700, "FEL: JSON-RPC kunde inte tolkas"))
            continue

        request_id = request.get("id")
        method = request.get("method")

        if method == "initialize":
            _write_json(_initialize_response(request_id))
            continue

        if method == "tools/list":
            _write_json(_tools_list_response(request_id))
            continue

        if method == "tools/call":
            try:
                _write_json(_tools_call_response(request_id, request.get("params") or {}))
            except ValueError as exc:
                _write_json(_error(request_id, -32602, str(exc)))
            except Exception as exc:
                _write_json(_exception_response(request_id, exc))
            continue

        if method == "shutdown":
            _write_json({"jsonrpc": "2.0", "id": request_id, "result": {}})
            return 0

        _write_json(_error(request_id, -32601, f"FEL: okand metod: {method}"))


if __name__ == "__main__":
    raise SystemExit(main())
