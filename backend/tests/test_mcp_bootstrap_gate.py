from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


pytestmark = pytest.mark.skipif(sys.platform != "win32", reason="bootstrap gate is verified on Windows")

ROOT = Path(__file__).resolve().parents[2]
GATE_SOURCE = ROOT / "ops" / "mcp_bootstrap_gate.ps1"

VALID_ENV = """SUPABASE_PROJECT_REF=expectedprojectref123
SUPABASE_PAT=sbp_abcdefghijklmnopqrstuvwxyz
CONTEXT7_URL=https://context7.example.com/mcp
CONTEXT7_TOKEN=ctx_abcdefghijklmnopqrstuvwxyz
FIGMA_ACCESS_TOKEN=figma_abcdefghijklmnopqrstuvwxyz
STRIPE_SECRET_KEY=sk_test_abcdefghijklmnopqrstuvwxyz
"""


def _powershell_executable() -> str:
    executable = shutil.which("powershell.exe")
    if executable is None:
        pytest.skip("powershell.exe is not available")
    return executable


def _node_runtime_available() -> None:
    if shutil.which("node") is None or shutil.which("npx") is None:
        pytest.skip("node and npx are required for the bootstrap gate")


def _valid_mcp_config(*, supabase_project_ref: str = "expectedprojectref123") -> str:
    return json.dumps(
        {
            "servers": {
                "aveli-logs": {
                    "type": "http",
                    "url": "http://127.0.0.1:8080/mcp/logs",
                },
                "aveli-media-control-plane": {
                    "type": "http",
                    "url": "http://127.0.0.1:8080/mcp/media-control-plane",
                },
                "aveli-domain-observability": {
                    "type": "http",
                    "url": "http://127.0.0.1:8080/mcp/domain-observability",
                },
                "aveli-verification": {
                    "type": "http",
                    "url": "http://127.0.0.1:8080/mcp/verification",
                },
                "context7": {
                    "type": "http",
                    "url": "https://context7.example.com/mcp",
                    "headers": {
                        "Authorization": "Bearer ${CONTEXT7_TOKEN}",
                    },
                },
                "supabase": {
                    "type": "http",
                    "url": f"https://{supabase_project_ref}.supabase.co",
                },
                "playwright": {
                    "type": "stdio",
                    "command": "npx",
                    "args": ["@playwright/mcp@latest"],
                },
                "figma": {
                    "type": "stdio",
                    "command": "npx",
                    "args": [
                        "figma-developer-mcp",
                        "--stdio",
                        "--figma-api-key",
                        "${FIGMA_ACCESS_TOKEN}",
                    ],
                },
            }
        }
    )


def _write_fixture(tmp_path: Path, *, env_text: str, mcp_text: str) -> Path:
    fixture_root = tmp_path / "fixture"
    (fixture_root / "ops").mkdir(parents=True)
    (fixture_root / ".vscode").mkdir(parents=True)
    shutil.copy2(GATE_SOURCE, fixture_root / "ops" / "mcp_bootstrap_gate.ps1")
    (fixture_root / ".env").write_text(env_text, encoding="utf-8")
    (fixture_root / ".vscode" / "mcp.json").write_text(mcp_text, encoding="utf-8")
    return fixture_root


def _run_gate(fixture_root: Path) -> subprocess.CompletedProcess[str]:
    _node_runtime_available()
    return subprocess.run(
        [
            _powershell_executable(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(fixture_root / "ops" / "mcp_bootstrap_gate.ps1"),
        ],
        cwd=str(fixture_root),
        capture_output=True,
        text=True,
        check=False,
    )


def test_gate_source_contains_no_runtime_http_probing() -> None:
    source = GATE_SOURCE.read_text(encoding="utf-8")

    assert "Invoke-WebRequest" not in source
    assert "healthz" not in source
    assert "/mcp/" not in source
    assert "BackendBaseUrl" not in source


def test_gate_malformed_json_fails_with_sanitized_message_only(tmp_path: Path) -> None:
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text="""{
  "servers": {
    "context7": {
      "type": "http",
      "url": "https://context7.example.com/mcp",
      "headers": {
        "Authorization": "Bearer ctx_secret_value_1234567890"
      },
    },
    "figma": {
      "type": "stdio",
      "command": "npx",
      "args": ["figma-developer-mcp", "--stdio", "--figma-api-key", "figma_secret_value_1234567890"]
    }
  }
}""",
    )

    result = _run_gate(fixture_root)
    combined_output = f"{result.stdout}\n{result.stderr}"

    assert result.returncode == 1
    assert result.stdout.strip() == ""
    assert result.stderr.strip() == "invalid mcp.json (malformed JSON)"
    assert "ctx_secret_value_1234567890" not in combined_output
    assert "figma_secret_value_1234567890" not in combined_output
    assert '"Authorization"' not in combined_output
    assert '"args"' not in combined_output


def test_gate_fails_when_supabase_pat_is_missing(tmp_path: Path) -> None:
    fixture_root = _write_fixture(
        tmp_path,
        env_text="""SUPABASE_PROJECT_REF=expectedprojectref123
CONTEXT7_URL=https://context7.example.com
CONTEXT7_TOKEN=ctx_abcdefghijklmnopqrstuvwxyz
FIGMA_ACCESS_TOKEN=figma_abcdefghijklmnopqrstuvwxyz
""",
        mcp_text=_valid_mcp_config(),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "Missing required env key: SUPABASE_PAT"


def test_gate_fails_when_supabase_project_does_not_match(tmp_path: Path) -> None:
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=_valid_mcp_config(supabase_project_ref="differentprojectref999"),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "supabase project mismatch"


def test_gate_fails_when_context7_url_does_not_match_env(tmp_path: Path) -> None:
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV.replace(
            "CONTEXT7_URL=https://context7.example.com/mcp",
            "CONTEXT7_URL=https://context7.expected.example/mcp",
        ),
        mcp_text=_valid_mcp_config(),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "context7 url mismatch"


def test_gate_rejects_context7_auth_without_binding(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    del config["servers"]["context7"]["headers"]
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "context7 auth not bound to CONTEXT7_TOKEN"


def test_gate_rejects_context7_auth_mismatch(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["context7"]["headers"]["Authorization"] = "Bearer ctx_abcdefghijklmnopqrstuvwxyz"
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "context7 auth not bound to CONTEXT7_TOKEN"


def test_gate_rejects_context7_placeholder_with_wrong_format(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["context7"]["headers"]["Authorization"] = "Token ${CONTEXT7_TOKEN}"
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "mcp.json contains unresolved placeholders"


def test_gate_rejects_placeholder_in_wrong_field(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["context7"]["metadata"] = "${CONTEXT7_TOKEN}"
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "mcp.json contains unresolved placeholders"


def test_gate_fails_when_required_mcp_server_is_null(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["aveli-logs"] = None
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "invalid MCP server config: aveli-logs"


def test_gate_passes_valid_config_without_backend_runtime(tmp_path: Path) -> None:
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=_valid_mcp_config(),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 0
    assert result.stdout.strip() == "MCP_BOOTSTRAP_GATE_OK"
    assert result.stderr.strip() == ""


def test_gate_validates_optional_stripe_header_against_env(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["stripe"] = {
        "type": "http",
        "url": "https://mcp.stripe.com",
        "headers": {
            "Authorization": "Bearer ${STRIPE_SECRET_KEY}",
        },
    }
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 0
    assert result.stdout.strip() == "MCP_BOOTSTRAP_GATE_OK"
    assert result.stderr.strip() == ""


def test_gate_rejects_optional_stripe_header_mismatch(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["stripe"] = {
        "type": "http",
        "url": "https://mcp.stripe.com",
        "headers": {
            "Authorization": "Bearer sk_test_different_value_1234567890",
        },
    }
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "stripe auth not bound to STRIPE_SECRET_KEY"


def test_gate_rejects_optional_stripe_placeholder_with_wrong_format(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["stripe"] = {
        "type": "http",
        "url": "https://mcp.stripe.com",
        "headers": {
            "Authorization": "Token ${STRIPE_SECRET_KEY}",
        },
    }
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "mcp.json contains unresolved placeholders"


def test_gate_rejects_optional_stripe_server_without_auth(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["stripe"] = {
        "type": "http",
        "url": "https://mcp.stripe.com",
    }
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "stripe auth not bound to STRIPE_SECRET_KEY"


def test_gate_fails_when_http_server_is_missing_url(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    del config["servers"]["context7"]["url"]
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "invalid MCP server config: context7"


def test_gate_fails_when_optional_netlify_server_is_misconfigured(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["netlify"] = {
        "command": "npx",
        "args": ["-y", "@netlify/mcp"],
    }
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "invalid MCP server config: netlify"


@pytest.mark.parametrize(
    ("field_name", "expected_error"),
    [
        ("command", "invalid MCP server config: figma"),
        ("args", "invalid MCP server config: figma"),
    ],
)
def test_gate_fails_when_stdio_server_is_missing_required_fields(
    tmp_path: Path,
    field_name: str,
    expected_error: str,
) -> None:
    config = json.loads(_valid_mcp_config())
    del config["servers"]["figma"][field_name]
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == expected_error


def test_gate_rejects_figma_arg_when_it_does_not_match_env(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["figma"]["args"][-1] = "figma_different_value_1234567890"
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "figma auth not bound to FIGMA_ACCESS_TOKEN"


def test_gate_rejects_unapproved_placeholder_bindings(tmp_path: Path) -> None:
    config = json.loads(_valid_mcp_config())
    config["servers"]["figma"]["args"][-1] = "${UNAPPROVED_TOKEN}"
    fixture_root = _write_fixture(
        tmp_path,
        env_text=VALID_ENV,
        mcp_text=json.dumps(config),
    )

    result = _run_gate(fixture_root)

    assert result.returncode == 1
    assert result.stderr.strip() == "mcp.json contains unresolved placeholders"
