import asyncio
import pytest

import scripts.qa_teacher_smoke as qa_smoke
from scripts.qa_teacher_smoke import DEFAULT_BASE_URL, resolve_base_url


def test_resolve_base_url_prefers_cli(monkeypatch):
    monkeypatch.setenv("QA_BASE_URL", "http://env-qa")
    monkeypatch.setenv("API_BASE_URL", "http://env-api")
    assert resolve_base_url("http://cli") == "http://cli"


def test_resolve_base_url_env_order(monkeypatch):
    monkeypatch.setenv("QA_BASE_URL", "http://env-qa")
    monkeypatch.setenv("API_BASE_URL", "http://env-api")
    assert resolve_base_url() == "http://env-qa"
    monkeypatch.delenv("QA_BASE_URL")
    assert resolve_base_url() == "http://env-api"
    monkeypatch.delenv("API_BASE_URL")
    assert resolve_base_url() == DEFAULT_BASE_URL


def test_ensure_active_service_seeds_in_dev(monkeypatch):
    sequence = {"listed": 0}

    async def fake_list(*_, **__):
        sequence["listed"] += 1
        return [] if sequence["listed"] == 1 else [{"id": "new-id"}]

    async def fake_profile(*_, **__):
        return {"user_id": "user-123"}

    async def fake_seed(user_id):
        sequence["seeded"] = user_id
        return "new-id"

    monkeypatch.setattr(qa_smoke, "_list_services", fake_list)
    monkeypatch.setattr(qa_smoke, "_fetch_profile", fake_profile)
    monkeypatch.setattr(qa_smoke, "_seed_dev_service", fake_seed)

    service = asyncio.run(qa_smoke._ensure_active_service(None, "token", "development"))
    assert service["id"] == "new-id"
    assert sequence["seeded"] == "user-123"


def test_ensure_active_service_fails_in_prod(monkeypatch, capsys):
    async def fake_list(*_, **__):
        return []

    monkeypatch.setattr(qa_smoke, "_list_services", fake_list)

    with pytest.raises(SystemExit):
        asyncio.run(qa_smoke._ensure_active_service(None, "token", "production"))

    out = capsys.readouterr().out
    assert "No active services found" in out
