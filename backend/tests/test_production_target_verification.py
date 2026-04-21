from __future__ import annotations

from pathlib import Path

from scripts.verify_production_target import (
    derive_project_ref_from_database_url,
    verify_production_target,
)


ROOT = Path(__file__).resolve().parents[2]
PRODUCTION_CONTRACT_PATH = ROOT / "actual_truth" / "contracts" / "production_deployment_contract.md"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_derive_project_ref_from_pooler_database_url_uses_postgres_username_suffix() -> None:
    value = (
        "postgresql://postgres.aiftpfyrqjhstcnblyhb:[REDACTED]"
        "@aws-1-eu-north-1.pooler.supabase.com:5432/postgres?sslmode=require"
    )

    assert derive_project_ref_from_database_url(value) == "aiftpfyrqjhstcnblyhb"


def test_verify_production_target_accepts_derived_runtime_authority_without_raw_secret_values() -> None:
    result = verify_production_target(
        {
            "surfaces": [
                {
                    "name": "DATABASE_URL",
                    "origin": "fly_logs",
                    "value": (
                        "postgresql://postgres.aiftpfyrqjhstcnblyhb:[REDACTED]"
                        "@aws-1-eu-north-1.pooler.supabase.com:5432/postgres?sslmode=require"
                    ),
                },
                {
                    "name": "SUPABASE_URL",
                    "origin": "runtime_env",
                    "value": "https://aiftpfyrqjhstcnblyhb.supabase.co",
                },
                {
                    "name": "SUPABASE_PROJECT_REF",
                    "origin": "repo_local",
                    "value": "ihirfhnpjtetdmdvqvyu",
                },
            ],
            "secret_digests": [
                {
                    "name": "DATABASE_URL",
                    "origin": "fly_secret_metadata",
                    "digest": "a" * 64,
                },
                {
                    "name": "SUPABASE_DB_URL",
                    "origin": "fly_secret_metadata",
                    "digest": "a" * 64,
                },
            ],
        }
    )

    assert result["status"] == "VERIFIED"
    assert result["classification"] == "DERIVED_RUNTIME_AUTHORITY"
    assert result["project_ref"] == "aiftpfyrqjhstcnblyhb"
    assert result["raw_secret_values_required"] is False
    assert result["blocked_forbidden_when_conditions_met"] is True
    assert result["failure_codes"] == []


def test_verify_production_target_rejects_conflicting_runtime_project_refs() -> None:
    result = verify_production_target(
        {
            "surfaces": [
                {
                    "name": "DATABASE_URL",
                    "origin": "runtime_env",
                    "value": (
                        "postgresql://postgres.aiftpfyrqjhstcnblyhb:[REDACTED]"
                        "@aws-1-eu-north-1.pooler.supabase.com:5432/postgres?sslmode=require"
                    ),
                },
                {
                    "name": "SUPABASE_URL",
                    "origin": "fly_logs",
                    "value": "https://ihirfhnpjtetdmdvqvy.supabase.co",
                },
                {
                    "name": "SUPABASE_PROJECT_REF",
                    "origin": "runtime_env",
                    "value": "ihirfhnpjtetdmdvqvy",
                },
            ],
            "secret_digests": [
                {
                    "name": "DATABASE_URL",
                    "origin": "fly_secret_metadata",
                    "digest": "a" * 64,
                },
                {
                    "name": "SUPABASE_DB_URL",
                    "origin": "fly_secret_metadata",
                    "digest": "a" * 64,
                },
            ],
        }
    )

    assert result["status"] == "UNVERIFIED"
    assert "conflicting_runtime_project_ref" in result["failure_codes"]
    assert result["classification"] is None


def test_verify_production_target_requires_matching_deployed_digests() -> None:
    result = verify_production_target(
        {
            "surfaces": [
                {
                    "name": "DATABASE_URL",
                    "origin": "runtime_env",
                    "value": (
                        "postgresql://postgres.aiftpfyrqjhstcnblyhb:[REDACTED]"
                        "@aws-1-eu-north-1.pooler.supabase.com:5432/postgres?sslmode=require"
                    ),
                },
                {
                    "name": "SUPABASE_URL",
                    "origin": "fly_logs",
                    "value": "https://aiftpfyrqjhstcnblyhb.supabase.co",
                },
            ],
            "secret_digests": [
                {
                    "name": "DATABASE_URL",
                    "origin": "fly_secret_metadata",
                    "digest": "a" * 64,
                },
                {
                    "name": "SUPABASE_DB_URL",
                    "origin": "fly_secret_metadata",
                    "digest": "b" * 64,
                },
            ],
        }
    )

    assert result["status"] == "UNVERIFIED"
    assert "deployed_digest_mismatch" in result["failure_codes"]
    assert result["classification"] is None


def test_production_deployment_contract_allows_derived_runtime_authority_verification() -> None:
    contract = _read(PRODUCTION_CONTRACT_PATH)

    required_snippets = (
        "Raw secret values MUST NOT be required for production target verification.",
        "VERIFIED (`DERIVED_RUNTIME_AUTHORITY`)",
        "runtime `DATABASE_URL` resolves to project ref `X`",
        "runtime `SUPABASE_URL` resolves to project ref `X`",
        "`DATABASE_URL` and `SUPABASE_DB_URL` are proven identical by deployed secret digest equality",
        "No conflicting project ref is observed across runtime authority surfaces",
        "verification must not classify the target as `BLOCKED`",
    )
    forbidden_snippets = (
        "The intended production Supabase project is `UNVERIFIED` until",
        "Public launch is blocked until the Supabase project-ref mismatch is resolved",
    )

    for snippet in required_snippets:
        assert snippet in contract

    for snippet in forbidden_snippets:
        assert snippet not in contract
