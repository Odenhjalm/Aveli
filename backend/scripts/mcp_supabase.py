#!/usr/bin/env python3
"""
Small helper CLI to talk to the Supabase MCP server defined in .vscode/mcp.json.

Examples (after `set -a && source .env`):
  python scripts/mcp_supabase.py list-tools
  python scripts/mcp_supabase.py call-tool listTables
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Optional

import requests

CONFIG_PATH = Path(__file__).resolve().parents[2] / ".vscode" / "mcp.json"
PROTOCOL_VERSION = "2025-06-18"
USER_AGENT = "mcp-supabase-cli/0.1"


class MCPClient:
    """Minimal JSON-RPC client for an MCP HTTP endpoint."""

    def __init__(self, server_name: str, token: Optional[str]) -> None:
        self.base_url = self._load_server_url(server_name)
        self.session = requests.Session()
        self.req_id = 0
        self.session_id: Optional[str] = None
        self.token = token or os.getenv("SUPABASE_PAT")
        if not self.token:
            raise SystemExit(
                "Missing token: export SUPABASE_PAT or pass --token to the script."
            )
        self.server_info = self.initialize()

    @staticmethod
    def _load_server_url(server_name: str) -> str:
        if not CONFIG_PATH.exists():
            raise SystemExit(f"Missing MCP config: {CONFIG_PATH}")
        config = json.loads(CONFIG_PATH.read_text())
        try:
            return config["mcpServers"][server_name]["url"]
        except KeyError as exc:
            raise SystemExit(
                f"Server '{server_name}' not found in {CONFIG_PATH}"
            ) from exc

    def _request(self, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        self.req_id += 1
        payload: Dict[str, Any] = {
            "jsonrpc": "2.0",
            "id": self.req_id,
            "method": method,
        }
        if params:
            payload["params"] = params

        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "User-Agent": USER_AGENT,
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        response = self.session.post(
            self.base_url, json=payload, headers=headers, timeout=30
        )
        try:
            response.raise_for_status()
        except requests.HTTPError as err:
            raise SystemExit(
                f"HTTP {response.status_code} from MCP server: {response.text}"
            ) from err
        data = response.json()
        if "error" in data:
            err_obj = data["error"]
            raise SystemExit(
                f"MCP error {err_obj.get('code')}: {err_obj.get('message')}"
            )
        session_id = response.headers.get("mcp-session-id")
        if session_id:
            self.session_id = session_id
        return data["result"]

    def initialize(self) -> Dict[str, Any]:
        params = {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": {"name": "mcp-supabase.py", "version": "0.1"},
        }
        return self._request("initialize", params)

    def list_tools(self, cursor: Optional[str]) -> Dict[str, Any]:
        params: Dict[str, Any] = {}
        if cursor:
            params["cursor"] = cursor
        return self._request("tools/list", params or None)

    def call_tool(self, name: str, arguments: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        params: Dict[str, Any] = {"name": name}
        if arguments:
            params["arguments"] = arguments
        return self._request("tools/call", params)


def print_json(data: Dict[str, Any]) -> None:
    json.dump(data, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Query the Supabase MCP endpoint defined in .vscode/mcp.json."
    )
    parser.add_argument(
        "--server",
        default="supabase",
        help="Server key inside .vscode/mcp.json (default: supabase)",
    )
    parser.add_argument(
        "--token",
        help="Override SUPABASE_PAT (default: read from environment)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    tools_parser = subparsers.add_parser(
        "list-tools", help="Call tools/list and print the JSON output."
    )
    tools_parser.add_argument(
        "--cursor",
        help="Optional cursor returned from a previous call.",
    )

    call_parser = subparsers.add_parser(
        "call-tool", help="Invoke a tool exposed by the MCP server."
    )
    call_parser.add_argument("name")
    call_parser.add_argument(
        "--args",
        help="Inline JSON arguments for the tool (e.g. '{\"table\":\"profiles\"}').",
    )
    call_parser.add_argument(
        "--args-file",
        help="Path to a JSON file with tool arguments.",
    )

    tables_parser = subparsers.add_parser(
        "list-tables",
        help="Convenience wrapper around the Supabase list_tables tool.",
    )
    tables_parser.add_argument(
        "--schemas",
        nargs="+",
        help="Schemas to include (default: app public).",
    )
    return parser


def load_json_arg(args: argparse.Namespace) -> Optional[Dict[str, Any]]:
    if args.args_file:
        path = Path(args.args_file)
        try:
            return json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc
    if args.args:
        try:
            return json.loads(args.args)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid JSON in --args: {exc}") from exc
    return None


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    client = MCPClient(args.server, args.token)
    if args.command == "list-tools":
        result = client.list_tools(args.cursor)
    elif args.command == "call-tool":
        result = client.call_tool(args.name, load_json_arg(args))
    elif args.command == "list-tables":
        schemas = args.schemas or ["app", "public"]
        result = client.call_tool("list_tables", {"schemas": schemas})
    else:
        parser.error("Unknown command")
        return
    print_json(result)


if __name__ == "__main__":
    main()
