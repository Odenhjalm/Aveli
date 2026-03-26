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


async def test_media_control_plane_mcp_initialize_and_tool_call(async_client, monkeypatch):
    from app.routes import media_control_plane_mcp

    async def _fake_get_asset(*, asset_id: str):
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "asset_id": asset_id,
            "state_classification": "projected_ready",
            "detected_inconsistencies": [],
            "asset": {
                "asset_id": asset_id,
                "state": "ready",
                "purpose": "lesson_audio",
            },
            "lesson_media_references": [],
            "runtime_projection": [],
            "storage_verification": {"storage_catalog_available": True, "checks": []},
            "correlation": {
                "asset_ids": [asset_id],
                "lesson_ids": [],
                "lesson_media_ids": [],
                "runtime_media_ids": [],
                "timestamps": [],
                "state_transitions": [],
            },
            "truncation": {
                "lesson_media_references_truncated": False,
                "runtime_projection_truncated": False,
            },
        }

    monkeypatch.setattr(
        media_control_plane_mcp.media_control_plane_observability,
        "get_asset",
        _fake_get_asset,
        raising=True,
    )
    monkeypatch.setattr(
        media_control_plane_mcp.settings,
        "mcp_mode",
        "local",
        raising=False,
    )
    monkeypatch.setattr(
        media_control_plane_mcp.settings,
        "media_control_plane_mcp_enabled",
        True,
        raising=False,
    )

    initialize = await async_client.post(
        "/mcp/media-control-plane",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )
    assert initialize.status_code == 200
    init_payload = initialize.json()
    assert init_payload["result"]["protocolVersion"] == "2025-11-25"
    assert (
        init_payload["result"]["serverInfo"]["name"]
        == "aveli-media-control-plane-mcp"
    )

    tools_list = await async_client.post(
        "/mcp/media-control-plane",
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tools_list.status_code == 200
    listed = tools_list.json()["result"]["tools"]
    assert {tool["name"] for tool in listed} == {
        "get_asset",
        "trace_asset_lifecycle",
        "list_orphaned_assets",
        "validate_runtime_projection",
    }

    tool_call = await async_client.post(
        "/mcp/media-control-plane",
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "get_asset",
                "arguments": {"asset_id": "asset-123"},
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
    assert result["source"]["server"] == "aveli-media-control-plane-mcp"
    assert result["data"]["asset"]["asset_id"] == "asset-123"
    assert result["data"]["state_classification"] == "projected_ready"


async def test_media_control_plane_mcp_rejects_non_local_origin(async_client, monkeypatch):
    from app.routes import media_control_plane_mcp

    monkeypatch.setattr(
        media_control_plane_mcp.settings,
        "media_control_plane_mcp_enabled",
        True,
        raising=False,
    )
    response = await async_client.post(
        "/mcp/media-control-plane",
        json=_initialize_payload(),
        headers={
            "Accept": "application/json, text/event-stream",
            "Origin": "https://evil.example",
        },
    )

    assert response.status_code == 403
    assert (
        response.json()["detail"]
        == "Media Control Plane MCP rejected the supplied Origin header"
    )


async def test_media_control_plane_mcp_missing_asset_id_returns_jsonrpc_error(
    async_client, monkeypatch
):
    from app.routes import media_control_plane_mcp

    monkeypatch.setattr(
        media_control_plane_mcp.settings,
        "media_control_plane_mcp_enabled",
        True,
        raising=False,
    )
    await async_client.post(
        "/mcp/media-control-plane",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )

    response = await async_client.post(
        "/mcp/media-control-plane",
        json={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "get_asset",
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
    assert result["source"]["server"] == "aveli-media-control-plane-mcp"
    assert result["data"] == {"error": "asset_id is required"}
