from __future__ import annotations

from pathlib import Path

import pytest

from backend.bootstrap import baseline_v2


def test_baseline_mode_defaults_to_v2(monkeypatch) -> None:
    monkeypatch.delenv("BASELINE_MODE", raising=False)

    assert baseline_v2.baseline_mode() == "V2"


def test_baseline_profile_defaults_to_local_dev_outside_cloud(monkeypatch) -> None:
    monkeypatch.delenv("BASELINE_PROFILE", raising=False)
    monkeypatch.delenv("APP_ENV", raising=False)
    for key in baseline_v2.CLOUD_RUNTIME_ENV_KEYS:
        monkeypatch.delenv(key, raising=False)

    assert baseline_v2.baseline_profile() == "local_dev"


def test_baseline_profile_defaults_to_hosted_supabase_in_cloud(monkeypatch) -> None:
    monkeypatch.delenv("BASELINE_PROFILE", raising=False)
    monkeypatch.setenv("APP_ENV", "production")

    assert baseline_v2.baseline_profile() == "hosted_supabase"


def test_baseline_profile_keeps_explicit_local_mode_with_supabase_infrastructure(
    monkeypatch,
) -> None:
    monkeypatch.delenv("BASELINE_PROFILE", raising=False)
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("MCP_MODE", "local")
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")

    assert baseline_v2.baseline_profile() == "local_dev"


def test_ensure_v2_baseline_rejects_unsupported_mode(monkeypatch) -> None:
    monkeypatch.setenv("BASELINE_MODE", "legacy")

    with pytest.raises(baseline_v2.BaselineV2Error, match="unsupported BASELINE_MODE"):
        baseline_v2.ensure_v2_baseline(
            "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local"
        )


def test_v2_slot_order_is_explicit_and_complete() -> None:
    lock = baseline_v2.verify_v2_lock()
    locked_filenames = tuple(
        str(entry["filename"]) for entry in lock["slots"]  # type: ignore[index]
    )
    actual_filenames = tuple(
        path.name for path in sorted(Path("backend/supabase/baseline_v2_slots").glob("V2_*.sql"))
    )

    assert locked_filenames == actual_filenames
    assert lock["replay_ownership"]["replay_owned_schemas"] == ["app"]  # type: ignore[index]


def test_v2_local_bootstrap_allows_inherited_cloud_flags(monkeypatch) -> None:
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("MCP_MODE", "local")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")

    baseline_v2._require_local_database(
        "postgresql://postgres:postgres@127.0.0.1:5432/aveli_projection_v2_clean_target"
    )


def test_v2_non_local_bootstrap_rejects_cloud_flags(monkeypatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("MCP_MODE", "local")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")

    with pytest.raises(baseline_v2.BaselineV2Error, match="cloud runtime flag detected"):
        baseline_v2._require_local_database(
            "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local"
        )


def test_v2_runtime_rejects_local_database_in_cloud(monkeypatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")

    with pytest.raises(baseline_v2.BaselineV2Error, match="local host"):
        baseline_v2.validate_runtime_database_url(
            "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local"
        )


def test_hosted_replay_requires_explicit_operator_opt_in(monkeypatch) -> None:
    monkeypatch.delenv("ALLOW_HOSTED_BASELINE_REPLAY", raising=False)

    with pytest.raises(baseline_v2.BaselineV2Error, match="ALLOW_HOSTED_BASELINE_REPLAY=1"):
        baseline_v2._assert_replay_profile_allowed("hosted_supabase")


def test_local_dev_reset_class_defaults_to_stateless_verification(monkeypatch) -> None:
    monkeypatch.delenv("BASELINE_RESET_CLASS", raising=False)

    assert (
        baseline_v2.baseline_reset_class("local_dev")
        == baseline_v2.STATELESS_VERIFICATION_RESET_CLASS
    )


def test_hosted_reset_class_requires_explicit_classification(monkeypatch) -> None:
    monkeypatch.delenv("BASELINE_RESET_CLASS", raising=False)

    assert baseline_v2.baseline_reset_class("hosted_supabase") is None


def test_hosted_destructive_replay_rejects_protected_or_missing_classification(
    monkeypatch,
) -> None:
    monkeypatch.delenv("BASELINE_RESET_CLASS", raising=False)

    with pytest.raises(
        baseline_v2.BaselineV2Error,
        match="destructive app-schema replay is forbidden",
    ):
        baseline_v2._assert_destructive_replay_allowed(
            "hosted_supabase",
            app_schema_empty=True,
        )

    monkeypatch.setenv("BASELINE_RESET_CLASS", "stateful_business")
    with pytest.raises(
        baseline_v2.BaselineV2Error,
        match="stateful_business",
    ):
        baseline_v2._assert_destructive_replay_allowed(
            "hosted_supabase",
            app_schema_empty=True,
        )


def test_hosted_destructive_replay_allows_explicit_stateless_verification(monkeypatch) -> None:
    monkeypatch.setenv("BASELINE_RESET_CLASS", "stateless_verification")

    baseline_v2._assert_destructive_replay_allowed(
        "hosted_supabase",
        app_schema_empty=True,
    )


def test_ensure_v2_baseline_allows_hosted_verify_without_destructive_replay_opt_in(
    monkeypatch,
) -> None:
    class _FakeConnection:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    monkeypatch.setenv("BASELINE_PROFILE", "hosted_supabase")
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")
    monkeypatch.delenv("ALLOW_HOSTED_BASELINE_REPLAY", raising=False)
    monkeypatch.delenv("BASELINE_RESET_CLASS", raising=False)
    monkeypatch.setattr(baseline_v2, "verify_v2_lock", lambda: {})
    monkeypatch.setattr(baseline_v2, "_schema_verification", lambda: {"expected_counts": {}})
    monkeypatch.setattr(baseline_v2, "_db_is_empty", lambda conn: False)
    monkeypatch.setattr(
        baseline_v2,
        "_verify_v2_schema",
        lambda conn: {"schema_hash": "hash", "counts": {}},
    )
    monkeypatch.setattr(
        baseline_v2.psycopg,
        "connect",
        lambda *args, **kwargs: _FakeConnection(),
    )

    status = baseline_v2.ensure_v2_baseline(
        "postgresql://postgres:postgres@db.example.com:5432/aveli_hosted"
    )

    assert status["profile"] == "hosted_supabase"
    assert status["state"] == "verified"


def test_ensure_v2_baseline_blocks_hosted_destructive_replay_without_stateless_class(
    monkeypatch,
) -> None:
    class _FakeConnection:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    monkeypatch.setenv("BASELINE_PROFILE", "hosted_supabase")
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")
    monkeypatch.setenv("ALLOW_HOSTED_BASELINE_REPLAY", "1")
    monkeypatch.delenv("BASELINE_RESET_CLASS", raising=False)
    monkeypatch.setattr(baseline_v2, "verify_v2_lock", lambda: {})
    monkeypatch.setattr(baseline_v2, "_schema_verification", lambda: {"expected_counts": {}})
    monkeypatch.setattr(baseline_v2, "_db_is_empty", lambda conn: True)
    monkeypatch.setattr(
        baseline_v2.psycopg,
        "connect",
        lambda *args, **kwargs: _FakeConnection(),
    )

    with pytest.raises(
        baseline_v2.BaselineV2Error,
        match="destructive app-schema replay is forbidden",
    ):
        baseline_v2.ensure_v2_baseline(
            "postgresql://postgres:postgres@db.example.com:5432/aveli_hosted"
        )


def test_ensure_v2_baseline_allows_hosted_destructive_replay_in_explicit_stateless_mode(
    monkeypatch,
) -> None:
    class _FakeConnection:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    replay_calls: list[str] = []

    monkeypatch.setenv("BASELINE_PROFILE", "hosted_supabase")
    monkeypatch.setenv("BASELINE_RESET_CLASS", "stateless_verification")
    monkeypatch.setenv("ALLOW_HOSTED_BASELINE_REPLAY", "1")
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")
    monkeypatch.setattr(baseline_v2, "verify_v2_lock", lambda: {})
    monkeypatch.setattr(baseline_v2, "_schema_verification", lambda: {"expected_counts": {}})
    monkeypatch.setattr(baseline_v2, "_db_is_empty", lambda conn: True)
    monkeypatch.setattr(
        baseline_v2,
        "_replay_v2",
        lambda conn, *, profile: replay_calls.append(profile),
    )
    monkeypatch.setattr(
        baseline_v2,
        "_verify_v2_schema",
        lambda conn: {"schema_hash": "hash", "counts": {}},
    )
    monkeypatch.setattr(
        baseline_v2.psycopg,
        "connect",
        lambda *args, **kwargs: _FakeConnection(),
    )

    status = baseline_v2.ensure_v2_baseline(
        "postgresql://postgres:postgres@db.example.com:5432/aveli_hosted"
    )

    assert replay_calls == ["hosted_supabase"]
    assert status["state"] == "replayed"


def test_schema_verifier_hashes_app_schema_and_checks_substrate_interface() -> None:
    source = Path("backend/bootstrap/baseline_v2.py").read_text(encoding="utf-8")

    assert "where n.nspname in ('app', 'auth', 'storage')" not in source
    assert "where table_schema in ('app', 'auth', 'storage')" not in source
    assert "_verify_substrate_interface(conn)" in source
    assert "schema_hash_algorithm" in source
    assert "app_schema_fingerprint_v2" in source
    assert "BASELINE_RESET_CLASS_ENV" in source
    assert "_assert_destructive_replay_allowed" in source


def test_run_server_invokes_v2_baseline_gate() -> None:
    source = Path("backend/bootstrap/run_server.py").read_text(encoding="utf-8")

    assert "ensure_runtime_execution_ready()" in source
    assert "verify_v2_runtime()" in source
    assert "ensure_v2_baseline()" not in source
    assert "BASELINE_MODE=" in source
    assert "BASELINE_PROFILE=" in source
    assert "SCHEMA_HASH=" in source
