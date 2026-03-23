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


async def test_verification_mcp_initialize_and_tool_call(async_client, monkeypatch):
    from app.routes import verification_mcp

    async def _fake_get_test_cases():
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "verification": {"tool": "get_test_cases", "version": "1"},
            "verdict": "pass",
            "confidence": "high",
            "violations": [],
            "course_cover_cases": [
                {
                    "course_id": "course-123",
                    "slug": "course-123",
                    "title": "Course 123",
                    "why": "course has cover_media_id",
                }
            ],
            "lesson_media_cases": [
                {
                    "lesson_id": "lesson-123",
                    "course_id": "course-123",
                    "course_title": "Course 123",
                    "lesson_title": "Lesson 123",
                    "why": "lesson has lesson_media kind=audio",
                }
            ],
            "recommended_calls": [
                {
                    "tool": "verify_lesson_media_truth",
                    "arguments": {"lesson_id": "lesson-123"},
                }
            ],
            "summary": {
                "course_cover_case_count": 1,
                "lesson_media_case_count": 1,
                "error_count": 0,
                "warning_count": 0,
            },
            "sources_consulted": [
                "courses.list_courses",
                "courses.list_course_lessons",
                "courses.list_lesson_media",
            ],
        }

    monkeypatch.setattr(
        verification_mcp.verification_observability,
        "get_test_cases",
        _fake_get_test_cases,
        raising=True,
    )
    monkeypatch.setattr(
        verification_mcp.settings,
        "mcp_mode",
        "local",
        raising=False,
    )

    initialize = await async_client.post(
        "/mcp/verification",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )
    assert initialize.status_code == 200
    init_payload = initialize.json()
    assert init_payload["result"]["protocolVersion"] == "2025-11-25"
    assert init_payload["result"]["serverInfo"]["name"] == "aveli-verification-mcp"

    tools_list = await async_client.post(
        "/mcp/verification",
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        headers={
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )
    assert tools_list.status_code == 200
    listed = tools_list.json()["result"]["tools"]
    assert {tool["name"] for tool in listed} == {
        "verify_lesson_media_truth",
        "verify_course_cover_truth",
        "verify_phase2_truth_alignment",
        "get_test_cases",
    }

    tool_call = await async_client.post(
        "/mcp/verification",
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "get_test_cases", "arguments": {}},
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
    assert parsed["recommended_calls"][0]["tool"] == "verify_lesson_media_truth"
    assert parsed["environment"] == {
        "mcp_mode": "local",
        "production_data": False,
        "access_mode": "read_only",
    }


async def test_verification_mcp_rejects_non_local_origin(async_client):
    response = await async_client.post(
        "/mcp/verification",
        json=_initialize_payload(),
        headers={
            "Accept": "application/json, text/event-stream",
            "Origin": "https://evil.example",
        },
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Verification MCP rejected the supplied Origin header"


async def test_verification_mcp_missing_lesson_id_returns_jsonrpc_error(async_client):
    await async_client.post(
        "/mcp/verification",
        json=_initialize_payload(),
        headers={"Accept": "application/json, text/event-stream"},
    )

    response = await async_client.post(
        "/mcp/verification",
        json={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "verify_lesson_media_truth",
                "arguments": {},
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
    assert payload["error"]["message"] == "lesson_id is required"
