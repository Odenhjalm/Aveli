from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "backend" / "supabase" / "baseline_v2_slots.lock.json"
LEGACY_LOCK_PATH = ROOT / "backend" / "supabase" / "baseline_slots.lock.json"


def _sha256_lf(path: Path) -> str:
    source = path.read_text(encoding="utf-8")
    normalized = source.replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def _load_lock() -> dict:
    return json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def _load_manifest() -> dict:
    return json.loads((ROOT / "actual_truth" / "aveli_system_manifest.json").read_text(encoding="utf-8"))


def test_baseline_v2_lock_is_complete_ordered_and_lf_hashed() -> None:
    lock = _load_lock()

    assert lock["manifest_version"] == 3
    assert lock["status"] == "CANONICAL"
    assert lock["baseline_dir"] == "backend/supabase/baseline_v2_slots"
    assert lock["hash_strategy"] == "sha256_lf_normalized_utf8"
    assert lock["replay_ownership"]["replay_owned_schemas"] == ["app"]
    assert lock["replay_ownership"]["external_substrate_schemas"] == ["auth", "storage"]
    assert set(lock["execution_profiles"]) == {"local_dev", "hosted_supabase"}
    assert lock["execution_profiles"]["hosted_supabase"]["substrate_action"] == (
        "verify_provider_owned_interface_only"
    )
    assert lock["schema_verification"]["schema_scope"] == "app_owned_schema_only"
    assert lock["schema_verification"]["schema_hash_algorithm"] == (
        "backend.bootstrap.baseline_v2.app_schema_fingerprint_v2"
    )
    assert lock["schema_verification"]["expected_schema_hash"]
    assert "app_tables" not in lock["schema_verification"]["expected_counts"]

    slots = lock["slots"]
    assert len(slots) == 20
    assert [entry["slot"] for entry in slots] == list(range(1, 21))

    locked_filenames = [entry["filename"] for entry in slots]
    actual_filenames = [
        path.name
        for path in sorted((ROOT / "backend" / "supabase" / "baseline_v2_slots").glob("V2_*.sql"))
    ]
    assert locked_filenames == actual_filenames

    for entry in slots:
        path = ROOT / entry["path"]
        assert path.name == entry["filename"]
        assert _sha256_lf(path) == entry["sha256"]

    local_substrate_files = lock["local_dev_substrate_files"]
    assert [entry["path"] for entry in local_substrate_files] == [
        "ops/sql/minimal_auth_substrate.sql",
        "ops/sql/minimal_storage_substrate.sql",
    ]
    for entry in local_substrate_files:
        assert _sha256_lf(ROOT / entry["path"]) == entry["sha256"]


def test_manifest_declares_destructive_reset_guard_policy() -> None:
    manifest = _load_manifest()
    guard = manifest["baseline_v2_authority_freeze"]["reset_guard"]

    assert guard["environment_classification_authority"] == "BASELINE_RESET_CLASS"
    assert guard["allowed_classes"] == ["stateless_verification", "stateful_business"]
    assert guard["local_dev_default_class"] == "stateless_verification"
    assert guard["hosted_supabase_default"] == "fail_closed_until_explicit_classification"
    assert guard["destructive_app_schema_replay_allowed_only_for"] == "stateless_verification"
    assert guard["protected_business_state"] == [
        "app.memberships",
        "app.orders",
        "app.payments",
        "app.referral_codes",
        "app.course_enrollments",
    ]


def test_canonical_v2_slots_do_not_recreate_provider_owned_substrate() -> None:
    lock = _load_lock()
    provider_owned_ddl = (
        r"create\s+schema\s+(if\s+not\s+exists\s+)?auth\b",
        r"create\s+schema\s+(if\s+not\s+exists\s+)?storage\b",
        r"create\s+table\s+(if\s+not\s+exists\s+)?auth\.",
        r"create\s+table\s+(if\s+not\s+exists\s+)?storage\.",
    )

    for entry in lock["slots"]:
        path = ROOT / entry["path"]
        source = path.read_text(encoding="utf-8").lower()
        for pattern in provider_owned_ddl:
            assert re.search(pattern, source) is None, path.relative_to(ROOT).as_posix()


def test_legacy_baseline_lock_is_archived_only() -> None:
    legacy_lock = json.loads(LEGACY_LOCK_PATH.read_text(encoding="utf-8"))

    assert legacy_lock["status"] == "ARCHIVED_LEGACY_NON_AUTHORITATIVE"
    assert legacy_lock["superseded_by"] == "backend/supabase/baseline_v2_slots.lock.json"
    assert legacy_lock["runtime_replay_allowed"] is False


def test_bootstrap_gate_is_v2_lock_only_and_rejects_legacy_overrides() -> None:
    source = (ROOT / "backend" / "scripts" / "bootstrap_gate.py").read_text(encoding="utf-8")

    assert "BASELINE_V2_LOCK_FILE" in source
    assert "verify_v2_lock()" in source
    assert "reject_legacy_baseline_inputs()" in source
    assert "BASELINE_OVERRIDE_ENV_KEYS" in source
    assert "collect_runtime_status()" in source
    assert "validate_runtime_database_url(database_url)" in source
    assert "READY_FOR_BASELINE_RUNTIME" in source
    assert "state[\"DB_STATUS\"] = verify_database(database_url)" in source
    assert source.index("state[\"SLOT_COUNT\"] = str(verify_baseline())") < source.index(
        "state[\"DB_STATUS\"] = verify_database(database_url)"
    )


def test_runtime_entrypoints_use_canonical_bootstrap_only() -> None:
    fly_config = (ROOT / "fly.toml").read_text(encoding="utf-8")
    dockerfile = (ROOT / "backend" / "Dockerfile").read_text(encoding="utf-8")
    start_backend = (ROOT / "backend" / "scripts" / "start_backend.sh").read_text(
        encoding="utf-8"
    )
    dev_backend = (ROOT / "backend" / "scripts" / "dev_backend.sh").read_text(encoding="utf-8")
    verify_all = (ROOT / "ops" / "verify_all.sh").read_text(encoding="utf-8")
    run_server = (ROOT / "backend" / "bootstrap" / "run_server.py").read_text(encoding="utf-8")
    run_worker = (ROOT / "backend" / "bootstrap" / "run_worker.py").read_text(encoding="utf-8")

    assert 'app = "python -m backend.bootstrap.run_server"' in fly_config
    assert "python -m backend.bootstrap.run_worker" in fly_config
    assert "uvicorn" not in fly_config
    assert "python -m app.services.mvp_worker" not in fly_config

    assert 'CMD ["python", "-m", "backend.bootstrap.run_server"]' in dockerfile
    assert "PYTHONPATH=/app:/app/backend" in dockerfile
    assert "uvicorn" not in dockerfile

    assert 'exec "$AVELI_BACKEND_PYTHON" -m backend.bootstrap.run_server' in start_backend
    assert 'exec "${BACKEND_DIR}/scripts/start_backend.sh"' in dev_backend
    assert "uvicorn" not in dev_backend

    assert "-m backend.bootstrap.run_server" in verify_all
    assert "uvicorn" not in verify_all

    assert "ensure_runtime_execution_ready()" in run_server
    assert "verify_v2_runtime()" in run_server
    assert "ensure_v2_baseline()" not in run_server

    assert "ensure_runtime_execution_ready()" in run_worker
    assert "verify_v2_runtime()" in run_worker
    assert 'runpy.run_module("app.services.mvp_worker", run_name="__main__")' in run_worker


def test_replay_v2_is_the_only_lock_driven_replay_entrypoint() -> None:
    replay_v2 = (ROOT / "backend" / "scripts" / "replay_v2.sh").read_text(encoding="utf-8")
    replay_legacy = (ROOT / "backend" / "scripts" / "replay_baseline.sh").read_text(encoding="utf-8")
    ops_bootstrap = (ROOT / "ops" / "bootstrap_baseline.sh").read_text(encoding="utf-8")
    dev_reset = (ROOT / "backend" / "scripts" / "dev_reset.sh").read_text(encoding="utf-8")

    assert "verify_v2_lock" in replay_v2
    assert 'export BASELINE_MODE="V2"' in replay_v2
    assert 'export BASELINE_PROFILE="$requested_profile"' in replay_v2
    assert "Hosted Supabase replay requires ALLOW_HOSTED_BASELINE_REPLAY=1" in replay_v2
    assert "BASELINE_MODE=${requested_mode} is not allowed" in replay_v2
    assert "backend.bootstrap.baseline_v2" in replay_v2
    assert "glob(" not in replay_v2

    assert "Legacy baseline replay is disabled" in replay_legacy
    assert "exit 1" in replay_legacy

    assert "replay_v2.sh" in ops_bootstrap
    assert "replay_v2.sh" in dev_reset


def test_active_authority_surfaces_do_not_use_legacy_baseline_authority() -> None:
    active_files = [
        ROOT / "README.md",
        ROOT / "backend" / "README.md",
        ROOT / "backend" / "supabase" / "migrations" / "README.md",
        ROOT / "codex" / "AVELI_OPERATING_SYSTEM.md",
        ROOT / "codex" / "AVELI_EXECUTION_POLICY.md",
        ROOT / "actual_truth" / "AVELI_DATABASE_BASELINE_MANIFEST.md",
        ROOT / "actual_truth" / "Aveli_System_Decisions.md",
        ROOT / "actual_truth" / "aveli_system_manifest.json",
        ROOT / "actual_truth" / "rule_layers" / "DECISIONS.md",
        ROOT / "fly.toml",
        ROOT / "backend" / "Dockerfile",
    ]

    for directory in (
        ROOT / "actual_truth" / "contracts",
        ROOT / "backend" / "bootstrap",
        ROOT / "backend" / "scripts",
        ROOT / "backend" / "tests",
        ROOT / "ops",
    ):
        active_files.extend(
            path
            for path in directory.rglob("*")
            if path.is_file()
            and path.suffix in {".md", ".json", ".py", ".sh", ".ps1", ".toml"}
            and path != Path(__file__).resolve()
        )

    forbidden_tokens = (
        "backend/supabase/baseline_slots",
        "backend\\supabase\\baseline_slots",
        "baseline_slots.lock.json",
    )
    allowed_legacy_markers = (
        "ARCHIVED_LEGACY_NON_AUTHORITATIVE",
        "archived legacy and non-authoritative",
    )

    violations: list[str] = []
    for path in sorted(set(active_files)):
        source = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(source.splitlines(), start=1):
            if any(token in line for token in forbidden_tokens) and not any(
                marker in line for marker in allowed_legacy_markers
            ):
                violations.append(f"{path.relative_to(ROOT).as_posix()}:{line_number}: {line.strip()}")

    assert violations == []
