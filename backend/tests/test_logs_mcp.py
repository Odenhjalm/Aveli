import json

import pytest


pytestmark = pytest.mark.anyio("asyncio")


def _initialize_payload() -> dict:
    return {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "pytest", "version": "0.1"},
        },
    }


async def test_logs_mcp_initialize_and_tool_call(async_client, monkeypatch):
    from app.routes import logs_mcp

    async def _fake_get_worker_health():
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "worker_health": {
                "media_transcode": {"status": "ok"},
                "livekit_webhooks": {"status": "ok"},
                "membership_expiry_warnings": {"status": "ok"},
            },
            "safety": {"logs_mcp_enabled": True, "log_buffer_max_events": 500},
        }

    monkeypatch.setattr(
        logs_mcp.logs_observability,
        "get_worker_health",
        _fake_get_worker_health,
        raising=True,
    )
    monkeypatch.setattr(logs_mcp.settings, "mcp_mode", "local", raising=False)

    initialize = await async_client.post(
        "/mcp/logs",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )
    assert initialize.status_code == 200
    init_payload = initialize.json()
    assert init_payload["result"]["protocolVersion"] == "2025-11-25"
    assert init_payload["result"]["serverInfo"]["name"] == "aveli-logs-mcp"

    tools_list = await async_client.post(
        "/mcp/logs",
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tools_list.status_code == 200
    listed = tools_list.json()["result"]["tools"]
    assert {tool["name"] for tool in listed} == {
        "get_recent_errors",
        "get_media_failures",
        "get_cleanup_activity",
        "get_worker_health",
    }

    tool_call = await async_client.post(
        "/mcp/logs",
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "get_worker_health", "arguments": {}},
        },
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tool_call.status_code == 200
    content = tool_call.json()["result"]["content"]
    assert len(content) == 1
    parsed = json.loads(content[0]["text"])
    assert parsed["worker_health"]["media_transcode"]["status"] == "ok"
    assert parsed["environment"] == {
        "mcp_mode": "local",
        "production_data": False,
        "access_mode": "read_only",
    }


async def test_logs_mcp_rejects_non_local_origin(async_client):
    response = await async_client.post(
        "/mcp/logs",
        json=_initialize_payload(),
        headers={
            "Accept": "application/json, text/event-stream",
            "Origin": "https://evil.example",
        },
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Logs MCP rejected the supplied Origin header"


async def test_logs_mcp_invalid_window_returns_jsonrpc_error(async_client):
    await async_client.post(
        "/mcp/logs",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )

    response = await async_client.post(
        "/mcp/logs",
        json={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "get_cleanup_activity",
                "arguments": {"window": "90d"},
            },
        },
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["error"]["code"] == -32602
    assert "Unsupported window" in payload["error"]["message"]


async def test_logs_mcp_notification_returns_accepted(async_client):
    response = await async_client.post(
        "/mcp/logs",
        json={"jsonrpc": "2.0", "method": "notifications/initialized"},
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )

    assert response.status_code == 202
