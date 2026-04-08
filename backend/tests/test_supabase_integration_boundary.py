from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "actual_truth" / "contracts" / "supabase_integration_boundary_contract.md"
BASELINE_DIR = ROOT / "backend" / "supabase" / "baseline_slots"
AUTH_PATH = ROOT / "backend" / "app" / "auth.py"
MODELS_PATH = ROOT / "backend" / "app" / "models.py"
PROFILES_REPO_PATH = ROOT / "backend" / "app" / "repositories" / "profiles.py"
FRONTEND_DIRS = (ROOT / "frontend" / "lib", ROOT / "frontend" / "landing")
RUNTIME_DIRS = (ROOT / "backend" / "app", ROOT / "frontend" / "lib")
ALLOWED_FRONTEND_SUPABASE_STUBS = {
    ROOT / "frontend" / "landing" / "utils" / "supabase" / "client.ts",
    ROOT / "frontend" / "landing" / "utils" / "supabase" / "server.ts",
}


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _repo_relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _iter_code_files(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file() and path.suffix in {".py", ".dart", ".ts", ".tsx", ".js", ".jsx"}
    )


def test_supabase_boundary_contract_maps_infrastructure_only_responsibilities() -> None:
    contract = _read(CONTRACT_PATH)

    required_snippets = (
        "`auth.users` is identity-only",
        "`storage.objects` and `storage.buckets` are physical file persistence only",
        "Supabase-hosted Postgres is physical storage only",
        "`app.auth_subjects` owns onboarding state, roles, and admin/access flags",
        "`app.runtime_media` owns media runtime truth",
        "Frontend must use backend APIs only",
    )

    for snippet in required_snippets:
        assert snippet in contract


def test_baseline_keeps_supabase_external_dependencies_outside_canonical_domain_logic() -> None:
    forbidden_outside_foundation = (
        "auth.users",
        "storage.objects",
        "storage.buckets",
        "auth.uid(",
        "auth.role(",
    )

    for path in sorted(BASELINE_DIR.glob("*.sql")):
        if path.name == "0001_canonical_foundation.sql":
            continue

        source = _read(path)
        for forbidden in forbidden_outside_foundation:
            assert forbidden not in source, f"{_repo_relative(path)} contains {forbidden!r}"


def test_frontend_runtime_has_no_direct_supabase_clients() -> None:
    for root in FRONTEND_DIRS:
        for path in _iter_code_files(root):
            source = _read(path)
            if path in ALLOWED_FRONTEND_SUPABASE_STUBS:
                assert "backend-API" in source
                continue

            assert "@supabase/" not in source, _repo_relative(path)
            assert "package:supabase_flutter/supabase_flutter.dart" not in source, _repo_relative(path)
            assert "Supabase.instance.client" not in source, _repo_relative(path)


def test_backend_auth_and_profile_reads_do_not_use_supabase_auth_metadata_as_domain_fallback() -> None:
    auth_source = _read(AUTH_PATH)
    models_source = _read(MODELS_PATH)

    for forbidden in (
        "user_metadata",
        "app_metadata",
        'payload.get("display_name")',
        'payload.get("avatar_url")',
        'payload.get("name")',
    ):
        assert forbidden not in auth_source, forbidden

    for forbidden in ("raw_user_meta_data", "auth_avatar_url", "auth_picture_url"):
        assert forbidden not in models_source, forbidden


def test_profiles_repository_does_not_adapt_to_nonbaseline_profile_columns() -> None:
    source = _read(PROFILES_REPO_PATH)

    for forbidden in ("information_schema.columns", "SELECT column_name", "available_columns"):
        assert forbidden not in source, forbidden


def test_runtime_code_does_not_depend_on_legacy_supabase_schema_paths() -> None:
    forbidden_fragments = (
        "backend/supabase/migrations",
        "backend/supabase/ACTIVE_BASELINE",
        "20260320075542_remote_schema",
        "supabase_migrations.schema_migrations",
    )

    for root in RUNTIME_DIRS:
        for path in _iter_code_files(root):
            source = _read(path)
            for forbidden in forbidden_fragments:
                assert forbidden not in source, f"{_repo_relative(path)} references {forbidden}"
