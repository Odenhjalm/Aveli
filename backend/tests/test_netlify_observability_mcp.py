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


async def test_netlify_observability_mcp_initialize_and_tool_call(async_client, monkeypatch):
    from app.routes import netlify_observability_mcp

    async def _fake_get_env_completeness():
        return {
            "artifact_type": "netlify_env_health",
            "schema_version": "netlify_observability_v1",
            "generated_at_utc": "2026-04-17T12:00:00Z",
            "status": "ok",
            "authority_note": "observability_not_authority",
            "data_sources": ["netlify.toml", "environment_presence_only"],
            "read_only": True,
            "authority_override": False,
            "netlify_api_mutations_used": False,
            "deploy_triggered": False,
            "forbidden_actions": ["deploy", "build_trigger", "env_set", "env_unset", "site_update"],
            "data": {
                "required_env": [
                    {"name": "FLUTTER_API_BASE_URL", "present": True, "value_exposed": False},
                ],
                "secret_values_exposed": False,
            },
            "mismatches": [],
            "issues": [],
        }

    monkeypatch.setattr(
        netlify_observability_mcp.netlify_observability,
        "get_env_completeness",
        _fake_get_env_completeness,
        raising=True,
    )
    monkeypatch.setattr(
        netlify_observability_mcp.settings,
        "netlify_observability_mcp_enabled",
        True,
        raising=False,
    )

    initialize = await async_client.post(
        "/mcp/netlify-observability",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )
    assert initialize.status_code == 200
    init_payload = initialize.json()
    assert init_payload["result"]["protocolVersion"] == "2025-11-25"
    assert init_payload["result"]["serverInfo"]["name"] == "aveli-netlify-observability-mcp"

    tools_list = await async_client.post(
        "/mcp/netlify-observability",
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tools_list.status_code == 200
    listed = tools_list.json()["result"]["tools"]
    assert {tool["name"] for tool in listed} == {
        "netlify_deploy_health",
        "netlify_build_health",
        "netlify_env_health",
        "netlify_connectivity_health",
    }

    tool_call = await async_client.post(
        "/mcp/netlify-observability",
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "netlify_env_health",
                "arguments": {"correlation_id": "phase2-correlation"},
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
    assert result["request_id"] == "3"
    assert result["correlation_id"] == "phase2-correlation"
    assert result["tool_name"] == "netlify_env_health"
    assert result["failure"] is None
    assert result["source"]["server"] == "aveli-netlify-observability-mcp"
    assert result["data"]["artifact_type"] == "netlify_env_health"
    assert result["data"]["read_only"] is True
    assert result["data"]["authority_override"] is False
    assert result["data"]["netlify_api_mutations_used"] is False
    assert result["data"]["deploy_triggered"] is False
    assert result["data"]["authority_note"] == "observability_not_authority"


async def test_netlify_observability_mcp_rejects_non_local_origin(async_client, monkeypatch):
    from app.routes import netlify_observability_mcp

    monkeypatch.setattr(
        netlify_observability_mcp.settings,
        "netlify_observability_mcp_enabled",
        True,
        raising=False,
    )
    response = await async_client.post(
        "/mcp/netlify-observability",
        json=_initialize_payload(),
        headers={
            "Accept": "application/json, text/event-stream",
            "Origin": "https://evil.example",
        },
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Netlify Observability MCP rejected the supplied Origin header"


async def test_netlify_observability_mcp_rejects_arguments(async_client, monkeypatch):
    from app.routes import netlify_observability_mcp

    monkeypatch.setattr(
        netlify_observability_mcp.settings,
        "netlify_observability_mcp_enabled",
        True,
        raising=False,
    )
    await async_client.post(
        "/mcp/netlify-observability",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )

    response = await async_client.post(
        "/mcp/netlify-observability",
        json={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "netlify_deploy_health",
                "arguments": {"deploy": True},
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
    assert result["source"]["server"] == "aveli-netlify-observability-mcp"
    assert result["tool_name"] == "netlify_deploy_health"
    assert result["failure"]["message"] == "Unexpected arguments: deploy"
