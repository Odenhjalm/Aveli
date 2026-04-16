"""Semantic MCP server with E5 embeddings."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import List, Dict

REPO_ROOT = Path(__file__).resolve().parents[2]
SEARCH_PYTHON = REPO_ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"
INDEX_TOOLS_DIR = REPO_ROOT / "tools" / "index"

if Path(sys.executable).resolve() != SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: MCP semantic-search maste koras med kanonisk Windows-tolk: "
        f"{SEARCH_PYTHON}"
    )

if str(INDEX_TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(INDEX_TOOLS_DIR))

from sentence_transformers import SentenceTransformer
import torch
import numpy as np

try:
    from device_utils import resolve_index_device
except ModuleNotFoundError:
    from tools.index.device_utils import resolve_index_device

# ----------------------------------------
# CONFIG
# ----------------------------------------

SEARCH_SCRIPT_PATH = REPO_ROOT / "tools" / "index" / "search_code.py"

TOP_K = 10

# Runtime configuration
torch.set_num_threads(8)
DEVICE, DEVICE_SOURCE = resolve_index_device()

# ----------------------------------------
# MODEL (LOAD ONCE)
# ----------------------------------------

_MODEL = None

def get_model():
    global _MODEL
    if _MODEL is None:
        _MODEL = SentenceTransformer("intfloat/e5-large-v2", device=DEVICE)
    return _MODEL

# ----------------------------------------
# EMBEDDING HELPERS (E5 FORMAT)
# ----------------------------------------

def embed_query(query: str):
    model = get_model()
    query = "query: " + query
    return model.encode([query], normalize_embeddings=True)[0]

def embed_documents(docs: List[str]):
    model = get_model()
    docs = ["passage: " + d for d in docs]
    return model.encode(docs, normalize_embeddings=True)

# ----------------------------------------
# RUN BASE SEARCH WRAPPER
# ----------------------------------------

def _parse_results(stdout: str) -> List[Dict[str, str]]:
    results = []
    current_file = None
    current_lines = []

    file_prefix = re.compile(r"^FILE:\s*(.+?)\s*$")

    def flush():
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

        current_lines.append(line)

    flush()
    return results


def _run_base_search(query: str):
    proc = subprocess.run(
        [str(SEARCH_PYTHON), str(SEARCH_SCRIPT_PATH), query],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )

    output = proc.stdout or ""

    if proc.returncode != 0 and "FILE:" not in output:
        stderr = (proc.stderr or "").strip()
        raise RuntimeError(f"base search failed: {stderr}")

    return _parse_results(output)

# ----------------------------------------
# SEMANTIC RERANK
# ----------------------------------------

def semantic_rerank(query: str, results: List[Dict[str, str]]):
    if not results:
        return []

    query_emb = embed_query(query)

    texts = [r["snippet"] for r in results]
    doc_embs = embed_documents(texts)

    scores = np.dot(doc_embs, query_emb)

    ranked = sorted(
        zip(results, scores),
        key=lambda x: x[1],
        reverse=True
    )

    return [r for r, _ in ranked[:TOP_K]]

# ----------------------------------------
# JSON RPC HELPERS
# ----------------------------------------

def _write_json(payload: dict):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))
    sys.stdout.write("\n")
    sys.stdout.flush()


def _error(request_id, code: int, message: str, data=None):
    response = {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": code, "message": message},
    }
    if data is not None:
        response["error"]["data"] = data
    _write_json(response)

# ----------------------------------------
# MCP RESPONSES
# ----------------------------------------

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
                    "description": "Semantic search with E5 embeddings over repo.",
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


def _tools_call_response(request_id, params):
    name = params.get("name")
    args = params.get("arguments") or {}

    if name != "semantic_search":
        raise ValueError(f"Unknown tool: {name}")

    query = (args.get("query") or "").strip()
    if not query:
        raise ValueError("query must not be empty")

    base_results = _run_base_search(query)

    if not base_results:
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {"results": []},
        }

    ranked = semantic_rerank(query, base_results)

    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "results": ranked,
            "structuredContent": {"results": ranked},
            "content": [
                {
                    "type": "text",
                    "text": json.dumps({"results": ranked}, ensure_ascii=False),
                }
            ],
        },
    }

# ----------------------------------------
# MAIN LOOP
# ----------------------------------------

def main():
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue

        try:
            request = json.loads(raw)
        except json.JSONDecodeError:
            _error(None, -32700, "Parse error")
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
            except ValueError as e:
                _error(request_id, -32602, str(e))
            except Exception as e:
                _error(request_id, -32603, "Execution failed", str(e))
            continue

        if method == "shutdown":
            _write_json({"jsonrpc": "2.0", "id": request_id, "result": {}})
            return 0

        _error(request_id, -32601, f"Method not found: {method}")


if __name__ == "__main__":
    raise SystemExit(main())
