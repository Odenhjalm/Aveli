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


async def test_dev_operator_observability_mcp_initialize_and_tool_call(async_client, monkeypatch):
    from app.routes import dev_operator_observability_mcp

    async def _fake_dashboard():
        return {
            "artifact_type": "dev_operator_dashboard",
            "schema_version": "dev_operator_observability_v1",
            "generated_at_utc": "2026-04-17T12:00:00Z",
            "status": "DEGRADED",
            "authority_note": "observability_not_authority",
            "read_only": True,
            "authority_override": False,
            "data": {
                "overall_status": "DEGRADED",
                "subsystem_statuses": {"retrieval": {"status": "READY"}},
                "last_failure": {"found": False},
                "last_query_summary": {"available": True, "correlation_id": "phase3-correlation"},
                "active_build_summary": {"manifest_state": "ACTIVE_VERIFIED"},
                "correlation_summary": {"last_query_correlation_id": "phase3-correlation"},
            },
        }

    monkeypatch.setattr(
        dev_operator_observability_mcp.dev_operator_observability,
        "get_dev_operator_dashboard",
        _fake_dashboard,
        raising=True,
    )
    monkeypatch.setattr(
        dev_operator_observability_mcp.settings,
        "dev_operator_observability_mcp_enabled",
        True,
        raising=False,
    )

    initialize = await async_client.post(
        "/mcp/dev-operator",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )
    assert initialize.status_code == 200
    init_payload = initialize.json()
    assert init_payload["result"]["protocolVersion"] == "2025-11-25"
    assert init_payload["result"]["serverInfo"]["name"] == "aveli-dev-operator-mcp"

    tools_list = await async_client.post(
        "/mcp/dev-operator",
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tools_list.status_code == 200
    listed = tools_list.json()["result"]["tools"]
    assert {tool["name"] for tool in listed} == {
        "dev_operator_dashboard",
        "dev_operator_trace",
        "dev_operator_last_failure",
        "dev_operator_last_query",
    }

    tool_call = await async_client.post(
        "/mcp/dev-operator",
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "dev_operator_dashboard",
                "arguments": {},
            },
        },
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
            "x-correlation-id": "phase3-correlation",
        },
    )
    assert tool_call.status_code == 200
    result = tool_call.json()["result"]
    assert result["status"] == "ok"
    assert result["confidence"] == "high"
    assert result["request_id"] == "3"
    assert result["correlation_id"] == "phase3-correlation"
    assert result["tool_name"] == "dev_operator_dashboard"
    assert result["failure"] is None
    assert result["source"]["server"] == "aveli-dev-operator-mcp"
    assert result["data"]["artifact_type"] == "dev_operator_dashboard"
    assert result["data"]["read_only"] is True
    assert result["data"]["authority_override"] is False


async def test_dev_operator_trace_requires_correlation_id(async_client, monkeypatch):
    from app.routes import dev_operator_observability_mcp

    monkeypatch.setattr(
        dev_operator_observability_mcp.settings,
        "dev_operator_observability_mcp_enabled",
        True,
        raising=False,
    )
    await async_client.post(
        "/mcp/dev-operator",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )

    response = await async_client.post(
        "/mcp/dev-operator",
        json={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "dev_operator_trace",
                "arguments": {},
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
    assert result["tool_name"] == "dev_operator_trace"
    assert result["failure"]["message"] == "correlation_id is required"


async def test_dev_operator_observability_mcp_rejects_non_local_origin(async_client, monkeypatch):
    from app.routes import dev_operator_observability_mcp

    monkeypatch.setattr(
        dev_operator_observability_mcp.settings,
        "dev_operator_observability_mcp_enabled",
        True,
        raising=False,
    )
    response = await async_client.post(
        "/mcp/dev-operator",
        json=_initialize_payload(),
        headers={
            "Accept": "application/json, text/event-stream",
            "Origin": "https://evil.example",
        },
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Dev Operator MCP rejected the supplied Origin header"
