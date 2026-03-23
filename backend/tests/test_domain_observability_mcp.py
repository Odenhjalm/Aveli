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


async def test_domain_observability_mcp_inspect_user(async_client, monkeypatch):
    from app.routes import domain_observability_mcp
    from app.services.domain_observability import user_inspection

    async def _fake_get_user_by_id(_: str):
        return {
            "id": "user-123",
            "email": "teacher@example.com",
            "email_confirmed_at": "2026-03-23T12:00:00+00:00",
        }

    async def _fake_get_profile(_: str):
        return {
            "user_id": "user-123",
            "email": "teacher@example.com",
            "display_name": "Teacher",
            "onboarding_state": "registered_unverified",
            "role_v2": "teacher",
            "is_admin": False,
        }

    async def _fake_get_membership(_: str):
        return None

    async def _fake_list_courses(*, teacher_id: str, limit: int | None = None, **_: object):
        assert teacher_id == "user-123"
        assert limit == 25
        return [{"id": "course-b"}, {"id": "course-a"}]

    async def _fake_list_my_courses(_: str):
        return [{"id": "course-z"}]

    async def _fake_list_entitlements(_: str):
        return ["foundations-step1"]

    async def _fake_derive_onboarding_state(_: str):
        return "access_active_profile_complete"

    monkeypatch.setattr(
        user_inspection.auth_repo,
        "get_user_by_id",
        _fake_get_user_by_id,
        raising=True,
    )
    monkeypatch.setattr(
        user_inspection.profiles_repo,
        "get_profile",
        _fake_get_profile,
        raising=True,
    )
    monkeypatch.setattr(
        user_inspection.memberships_repo,
        "get_membership",
        _fake_get_membership,
        raising=True,
    )
    monkeypatch.setattr(
        user_inspection.courses_repo,
        "list_courses",
        _fake_list_courses,
        raising=True,
    )
    monkeypatch.setattr(
        user_inspection.courses_repo,
        "list_my_courses",
        _fake_list_my_courses,
        raising=True,
    )
    monkeypatch.setattr(
        user_inspection.course_entitlements_repo,
        "list_entitlements_for_user",
        _fake_list_entitlements,
        raising=True,
    )
    monkeypatch.setattr(
        user_inspection.onboarding_state,
        "derive_onboarding_state",
        _fake_derive_onboarding_state,
        raising=True,
    )
    monkeypatch.setattr(
        domain_observability_mcp.settings,
        "mcp_mode",
        "local",
        raising=False,
    )
    monkeypatch.setattr(
        domain_observability_mcp.settings,
        "domain_observability_mcp_enabled",
        True,
        raising=False,
    )

    initialize = await async_client.post(
        "/mcp/domain-observability",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )
    assert initialize.status_code == 200
    init_payload = initialize.json()
    assert init_payload["result"]["serverInfo"]["name"] == "aveli-domain-observability-mcp"

    tools_list = await async_client.post(
        "/mcp/domain-observability",
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tools_list.status_code == 200
    listed = tools_list.json()["result"]["tools"]
    assert {tool["name"] for tool in listed} == {"inspect_user", "inspect_media"}

    tool_call = await async_client.post(
        "/mcp/domain-observability",
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "inspect_user",
                "arguments": {"user_id": "user-123"},
            },
        },
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tool_call.status_code == 200
    parsed = json.loads(tool_call.json()["result"]["content"][0]["text"])
    assert parsed["subject"] == {"user_id": "user-123"}
    assert parsed["status"] == "warning"
    assert parsed["state_summary"]["role_state"] == "teacher"
    assert parsed["state_summary"]["authored_course_count"] == 2
    assert parsed["truth_sources"]["courses"]["authored_course_ids"] == [
        "course-a",
        "course-b",
    ]
    assert parsed["environment"] == {
        "mcp_mode": "local",
        "production_data": False,
        "access_mode": "read_only",
    }


async def test_domain_observability_mcp_inspect_media_asset(async_client, monkeypatch):
    from app.routes import domain_observability_mcp
    from app.services.domain_observability import media_inspection

    async def _fake_get_asset(asset_id: str):
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "asset_id": asset_id,
            "state_classification": "projected_ready",
            "detected_inconsistencies": [],
            "asset": {
                "asset_id": asset_id,
                "lesson_id": "lesson-123",
                "state": "ready",
            },
            "lesson_media_references": [{"lesson_media_id": "lm-1"}],
            "runtime_projection": [{"runtime_media_id": "rm-1"}],
        }

    async def _fake_get_media_failures(*, asset_id: str | None = None):
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "asset_id": asset_id,
            "media_failures": [],
            "summary": {},
        }

    async def _fake_get_worker_health():
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "worker_health": {
                "media_transcode": {"status": "ok"},
            },
        }

    monkeypatch.setattr(
        media_inspection.media_control_plane_observability,
        "get_asset",
        _fake_get_asset,
        raising=True,
    )
    monkeypatch.setattr(
        media_inspection.logs_observability,
        "get_media_failures",
        _fake_get_media_failures,
        raising=True,
    )
    monkeypatch.setattr(
        media_inspection.logs_observability,
        "get_worker_health",
        _fake_get_worker_health,
        raising=True,
    )
    monkeypatch.setattr(
        domain_observability_mcp.settings,
        "mcp_mode",
        "local",
        raising=False,
    )
    monkeypatch.setattr(
        domain_observability_mcp.settings,
        "domain_observability_mcp_enabled",
        True,
        raising=False,
    )

    await async_client.post(
        "/mcp/domain-observability",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )

    tool_call = await async_client.post(
        "/mcp/domain-observability",
        json={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "inspect_media",
                "arguments": {"asset_id": "asset-123"},
            },
        },
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tool_call.status_code == 200
    parsed = json.loads(tool_call.json()["result"]["content"][0]["text"])
    assert parsed["subject"] == {
        "mode": "asset",
        "asset_id": "asset-123",
        "lesson_id": "lesson-123",
    }
    assert parsed["status"] == "ok"
    assert parsed["state_summary"] == {
        "control_plane_state": "projected_ready",
        "asset_count": 1,
        "lesson_media_count": 1,
        "runtime_media_count": 1,
        "recent_failure_count": 0,
        "worker_status": "ok",
    }
    assert parsed["truth_sources"]["media_control_plane"]["asset"]["asset_id"] == "asset-123"
