import uuid

import pytest
from fastapi import HTTPException

from app.services import context7_gate

pytestmark = pytest.mark.anyio("asyncio")


def _user(role: str = "teacher", *, is_admin: bool = False) -> dict:
    return {"id": str(uuid.uuid4()), "role_v2": role, "is_admin": is_admin}


def _base_payload(user_id: str, role: str = "teacher") -> dict:
    return {
        "context_version": "2025-02-18",
        "schema_version": "2025-02-01",
        "actor": {"id": user_id, "role": role, "scopes": ["ai:execute"]},
        "execution_policy": {
            "mode": "stub",
            "tools_allowed": ["supabase_readonly"],
            "write_allowed": role == "admin",
            "max_steps": 10,
            "max_seconds": 60,
            "redact_logs": True,
        },
    }


async def test_validator_requires_execution_policy():
    user = _user()
    payload = _base_payload(user["id"])
    payload.pop("execution_policy")

    with pytest.raises(HTTPException) as excinfo:
        context7_gate.validate_context_payload(payload, user=user)

    assert excinfo.value.status_code == 400
    assert "execution_policy" in str(excinfo.value.detail)


async def test_validator_rejects_unknown_tool():
    user = _user()
    payload = _base_payload(user["id"])
    payload["execution_policy"]["tools_allowed"] = ["bad-tool"]

    with pytest.raises(HTTPException) as excinfo:
        context7_gate.validate_context_payload(payload, user=user)

    assert excinfo.value.status_code == 400
    assert "unsupported tool" in str(excinfo.value.detail)


async def test_validator_rejects_write_allowed_for_non_admin():
    user = _user(role="teacher")
    payload = _base_payload(user["id"], role="teacher")
    payload["execution_policy"]["write_allowed"] = True

    with pytest.raises(HTTPException) as excinfo:
        context7_gate.validate_context_payload(payload, user=user)

    assert excinfo.value.status_code == 403
    assert "write_allowed" in str(excinfo.value.detail)
