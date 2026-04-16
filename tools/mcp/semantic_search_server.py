"""Thin MCP transport wrapper for Aveli canonical retrieval."""

from __future__ import annotations

import json
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


class CanonicalRetrievalUnavailable(RuntimeError):
    def __init__(self) -> None:
        super().__init__(CANONICAL_RETRIEVAL_REQUIRED)
        self.classification = "STOP"


class CanonicalRetrievalStopped(RuntimeError):
    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.classification = "STOP"


def call_canonical_retrieval(query: str) -> Any:
    try:
        from search_code import handle_query_json
    except Exception as exc:
        raise CanonicalRetrievalUnavailable() from exc
    try:
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
                    "description": "Kanonisk Aveli-retrievaltransport.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "query": {"type": "string"},
                        },
                        "required": ["query"],
                    },
                }
            ]
        },
    }


def _validate_tool_call(params: dict) -> str:
    name = params.get("name")
    if name != "semantic_search":
        raise ValueError(f"Okant verktyg: {name}")

    args = params.get("arguments") or {}
    query = args.get("query")
    if not isinstance(query, str) or query == "":
        raise ValueError("query maste vara en icke-tom strang")
    return query


def _tools_call_response(request_id, params):
    query = _validate_tool_call(params)
    canonical_payload = call_canonical_retrieval(query)
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
