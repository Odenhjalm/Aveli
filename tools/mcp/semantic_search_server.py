#!/usr/bin/env python3
"""Minimal stdio MCP server exposing semantic repository search."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "tools" / "index" / "semantic_search.sh"


def _build_env() -> dict[str, str]:
    env = os.environ.copy()
    search_bin = REPO_ROOT / ".repo_index" / ".search_venv" / "bin"
    env["PATH"] = f"{search_bin}:{env.get('PATH', '')}"
    return env


def _parse_results(stdout: str) -> list[dict[str, str]]:
    results: list[dict[str, str]] = []
    current_file: str | None = None
    current_lines: list[str] = []

    file_prefix = re.compile(r"^FILE:\s*(.+?)\s*$")

    def flush() -> None:
        nonlocal current_file, current_lines
        if current_file is None:
            return
        snippet = "\n".join(current_lines).strip()
        results.append({"file": current_file, "snippet": snippet})
        current_file = None
        current_lines = []

    for line in stdout.splitlines():
        match = file_prefix.match(line)
        if match:
            flush()
            current_file = match.group(1)
            continue

        if current_file is None:
            continue

        # Keep output directly following FILE: as snippet context.
        current_lines.append(line)

    flush()
    return results


def _run_search(query: str) -> list[dict[str, str]]:
    proc = subprocess.run(
        [str(SCRIPT_PATH), query],
        capture_output=True,
        text=True,
        env=_build_env(),
        cwd=str(REPO_ROOT),
    )

    output = (proc.stdout or "")

    if proc.returncode != 0 and "FILE:" not in output:
        stderr = (proc.stderr or "").strip()
        raise RuntimeError(f"semantic search failed ({proc.returncode}): {stderr}")

    return _parse_results(output)


def _write_json(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))
    sys.stdout.write("\n")
    sys.stdout.flush()


def _error(request_id, code: int, message: str, data: object | None = None) -> None:
    response = {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {
            "code": code,
            "message": message,
        },
    }
    if data is not None:
        response["error"]["data"] = data
    _write_json(response)


def _tools_list_response(request_id):
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "tools": [
                {
                    "name": "semantic_search",
                    "description": "Execute semantic search across the repository index and return file path snippets.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "query": {"type": "string", "description": "Search query text."}
                        },
                        "required": ["query"],
                    },
                }
            ]
        },
    }


def _initialize_response(request_id):
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {}
            },
            "serverInfo": {
                "name": "aveli-semantic-search",
                "version": "0.1.0",
            },
        },
    }


def _tools_call_response(request_id, params: dict):
    name = params.get("name")
    args = params.get("arguments") or {}

    if name != "semantic_search":
        raise ValueError(f"Unknown tool: {name}")

    if not isinstance(args, dict):
        raise ValueError("arguments must be an object")

    query = (args.get("query") or "").strip()
    if not query:
        raise ValueError("query must be a non-empty string")

    results = _run_search(query)
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps({"results": results}, ensure_ascii=False),
                }
            ],
            "structuredContent": {"results": results},
            "results": results,
        },
    }


def main() -> int:
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue

        try:
            request = json.loads(raw)
        except json.JSONDecodeError:
            _write_json(
                {
                    "jsonrpc": "2.0",
                    "error": {"code": -32700, "message": "Parse error"},
                }
            )
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
            params = request.get("params") or {}
            try:
                _write_json(_tools_call_response(request_id, params))
            except ValueError as exc:
                _error(request_id, -32602, str(exc))
            except Exception as exc:
                _error(request_id, -32603, "Search execution failed", str(exc))
            continue

        if method == "shutdown":
            _write_json({"jsonrpc": "2.0", "id": request_id, "result": {}})
            return 0

        _error(request_id, -32601, f"Method not found: {method}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
