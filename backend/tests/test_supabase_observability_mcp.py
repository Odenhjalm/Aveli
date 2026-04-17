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


async def test_supabase_observability_mcp_initialize_and_tool_call(async_client, monkeypatch):
    from app.routes import supabase_observability_mcp

    async def _fake_get_connection_health():
        return {
            "artifact_type": "supabase_connection_health",
            "schema_version": "supabase_observability_v1",
            "generated_at_utc": "2026-04-17T12:00:00Z",
            "status": "ok",
            "authority_note": "observability_not_authority",
            "data_sources": ["supabase_database_readonly"],
            "read_only": True,
            "authority_override": False,
            "data": {
                "config": {
                    "supabase_url_configured": True,
                    "database_url_configured": True,
                },
                "database": {"latency_ms": 1.5},
            },
            "issues": [],
        }

    monkeypatch.setattr(
        supabase_observability_mcp.supabase_observability,
        "get_connection_health",
        _fake_get_connection_health,
        raising=True,
    )
    monkeypatch.setattr(
        supabase_observability_mcp.settings,
        "supabase_observability_mcp_enabled",
        True,
        raising=False,
    )

    initialize = await async_client.post(
        "/mcp/supabase-observability",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )
    assert initialize.status_code == 200
    init_payload = initialize.json()
    assert init_payload["result"]["protocolVersion"] == "2025-11-25"
    assert init_payload["result"]["serverInfo"]["name"] == "aveli-supabase-observability-mcp"

    tools_list = await async_client.post(
        "/mcp/supabase-observability",
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tools_list.status_code == 200
    listed = tools_list.json()["result"]["tools"]
    assert {tool["name"] for tool in listed} == {
        "get_supabase_connection_health",
        "get_supabase_auth_state",
        "get_supabase_domain_projections",
        "get_supabase_storage_state",
    }

    tool_call = await async_client.post(
        "/mcp/supabase-observability",
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "get_supabase_connection_health",
                "arguments": {},
            },
        },
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tool_call.status_code == 200
    result = tool_call.json()["result"]
    assert result["status"] == "ok"
    assert result["confidence"] == "high"
    assert result["source"]["server"] == "aveli-supabase-observability-mcp"
    assert result["data"]["artifact_type"] == "supabase_connection_health"
    assert result["data"]["read_only"] is True
    assert result["data"]["authority_override"] is False
    assert result["data"]["authority_note"] == "observability_not_authority"


async def test_supabase_observability_mcp_rejects_non_local_origin(async_client, monkeypatch):
    from app.routes import supabase_observability_mcp

    monkeypatch.setattr(
        supabase_observability_mcp.settings,
        "supabase_observability_mcp_enabled",
        True,
        raising=False,
    )
    response = await async_client.post(
        "/mcp/supabase-observability",
        json=_initialize_payload(),
        headers={
            "Accept": "application/json, text/event-stream",
            "Origin": "https://evil.example",
        },
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Supabase Observability MCP rejected the supplied Origin header"


async def test_supabase_observability_mcp_rejects_arguments(async_client, monkeypatch):
    from app.routes import supabase_observability_mcp

    monkeypatch.setattr(
        supabase_observability_mcp.settings,
        "supabase_observability_mcp_enabled",
        True,
        raising=False,
    )
    await async_client.post(
        "/mcp/supabase-observability",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )

    response = await async_client.post(
        "/mcp/supabase-observability",
        json={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "get_supabase_storage_state",
                "arguments": {"write": True},
            },
        },
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )

    assert response.status_code == 200
    result = response.json()["result"]
    assert result["status"] == "error"
    assert result["confidence"] == "low"
    assert result["source"]["server"] == "aveli-supabase-observability-mcp"
    assert result["data"]["error"] == "Unexpected arguments: write"
