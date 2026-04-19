from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "actual_truth" / "contracts" / "supabase_integration_boundary_contract.md"
BASELINE_V2_LOCK_PATH = ROOT / "backend" / "supabase" / "baseline_v2_slots.lock.json"
AUTH_PATH = ROOT / "backend" / "app" / "auth.py"
MODELS_PATH = ROOT / "backend" / "app" / "models.py"
PROFILES_REPO_PATH = ROOT / "backend" / "app" / "repositories" / "profiles.py"
TOOL_DISPATCHER_PATH = ROOT / "backend" / "app" / "services" / "tool_dispatcher.py"
FRONTEND_DIRS = (ROOT / "frontend" / "lib", ROOT / "frontend" / "landing")
RUNTIME_DIRS = (ROOT / "backend" / "app", ROOT / "frontend" / "lib")
ALLOWED_FRONTEND_SUPABASE_STUBS = {
    ROOT / "frontend" / "landing" / "utils" / "supabase" / "client.ts",
    ROOT / "frontend" / "landing" / "utils" / "supabase" / "server.ts",
}
FRONTEND_SUPPORTING_FILES_WITHOUT_SUPABASE_RUNTIME_ENV = {
    ROOT / ".env.example": ("NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY"),
    ROOT / "README.md": ("NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY"),
    ROOT / "docker-compose.yml": ("NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY"),
    ROOT / "frontend" / ".env.web": (
        "SUPABASE_URL",
        "SUPABASE_PUBLISHABLE_API_KEY",
        "SUPABASE_PUBLIC_API_KEY",
        "SUPABASE_ANON_KEY",
    ),
    ROOT / "frontend" / "scripts" / "build_prod.sh": (
        "SUPABASE_URL",
        "SUPABASE_PUBLISHABLE_API_KEY",
        "SUPABASE_PUBLIC_API_KEY",
        "SUPABASE_ANON_KEY",
    ),
    ROOT / "frontend" / "scripts" / "guard_web_defines.sh": (
        "SUPABASE_URL",
        "SUPABASE_PUBLISHABLE_API_KEY",
        "SUPABASE_PUBLIC_API_KEY",
        "SUPABASE_ANON_KEY",
    ),
    ROOT / "frontend" / "scripts" / "netlify_build_web.sh": (
        "FLUTTER_SUPABASE_URL",
        "FLUTTER_SUPABASE_PUBLISHABLE_API_KEY",
        "FLUTTER_SUPABASE_PUBLIC_API_KEY",
        "FLUTTER_SUPABASE_ANON_KEY",
    ),
    ROOT / "netlify.toml": ("FLUTTER_SUPABASE_URL", "FLUTTER_SUPABASE_PUBLIC_API_KEY"),
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


def _baseline_v2_sql_paths() -> list[Path]:
    lock = json.loads(BASELINE_V2_LOCK_PATH.read_text(encoding="utf-8"))
    return [ROOT / entry["path"] for entry in lock["slots"]]


def test_supabase_boundary_contract_maps_infrastructure_only_responsibilities() -> None:
    contract = _read(CONTRACT_PATH)

    required_snippets = (
        "`auth.users` is identity-only",
        "`storage.objects` and `storage.buckets` are physical file persistence only",
        "Supabase-hosted Postgres is physical storage only",
        "`app.auth_subjects` is the canonical application subject authority",
        "app-level role subject fields",
        "`app.memberships` owns app-access truth",
        "`app.course_enrollments` owns protected course-content access truth",
        "Canonical schema authority is `backend/supabase/baseline_v2_slots`",
        "Canonical slot order, slot hashes, and schema verification marker are owned by",
        "`backend/supabase/baseline_v2_slots.lock.json`",
        "Frontend must use backend APIs only",
    )
    legacy_slot_dir = "/".join(("backend", "supabase", "baseline" + "_slots"))
    forbidden_snippets = (
        "admin/access flags",
        "app-level admin subject fields",
        "`app.runtime_media` owns media runtime truth",
        f"Canonical schema authority is `{legacy_slot_dir}`",
    )

    for snippet in required_snippets:
        assert snippet in contract

    for snippet in forbidden_snippets:
        assert snippet not in contract


def test_baseline_keeps_supabase_external_dependencies_outside_canonical_domain_logic() -> None:
    substrate_allowed_slots = {
        "V2_0011_auth_session_and_subject_authority.sql",
        "V2_0012_core_substrate_profiles_storage_referrals.sql",
    }
    forbidden_everywhere = ("auth.uid(", "auth.role(")
    forbidden_outside_substrate = ("auth.users", "storage.objects", "storage.buckets")

    for path in _baseline_v2_sql_paths():
        source = _read(path)
        for forbidden in forbidden_everywhere:
            assert forbidden not in source, f"{_repo_relative(path)} contains {forbidden!r}"

        if path.name in substrate_allowed_slots:
            continue

        for forbidden in forbidden_outside_substrate:
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


def test_frontend_supporting_files_do_not_require_supabase_runtime_env() -> None:
    for path, forbidden_fragments in FRONTEND_SUPPORTING_FILES_WITHOUT_SUPABASE_RUNTIME_ENV.items():
        if not path.exists():
            continue
        source = _read(path)
        for forbidden in forbidden_fragments:
            assert forbidden not in source, f"{_repo_relative(path)} references {forbidden}"


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


def test_tool_dispatcher_uses_canonical_identity_and_role_sources() -> None:
    source = _read(TOOL_DISPATCHER_PATH)

    required_fragments = (
        "JOIN auth.users u ON u.id = e.user_id",
        "JOIN app.auth_subjects a ON a.user_id = u.id",
        "COALESCE(p.display_name, u.email)",
        "a.role::text AS role",
        'detail="DATABASE_URL missing"',
    )
    forbidden_fragments = (
        "SUPABASE_DB_URL",
        "p.email",
    )

    for required in required_fragments:
        assert required in source, required

    for forbidden in forbidden_fragments:
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
