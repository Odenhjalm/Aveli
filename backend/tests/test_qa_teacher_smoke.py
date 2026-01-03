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
