from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import tomllib
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
from uuid import UUID

from ..config import settings


SCHEMA_VERSION = "netlify_observability_v1"
AUTHORITY_NOTE = "observability_not_authority"
_RECENT_LIMIT = 5
_REQUIRED_NETLIFY_ENV = (
    "FLUTTER_API_BASE_URL",
    "FLUTTER_STRIPE_PUBLISHABLE_KEY",
    "FLUTTER_OAUTH_REDIRECT_WEB",
    "FLUTTER_SUBSCRIPTIONS_ENABLED",
)
_OPTIONAL_NETLIFY_ENV = (
    "FLUTTER_FRONTEND_URL",
    "FLUTTER_MERCHANT_DISPLAY_NAME",
    "FLUTTER_IMAGE_LOGGING",
    "FLUTTER_VERSION",
)

_REPO_ROOT = Path(__file__).resolve().parents[3]
_FRONTEND_ROOT = _REPO_ROOT / "frontend"
_NETLIFY_TOML = _REPO_ROOT / "netlify.toml"
_FRONTEND_NETLIFY_STATE = _FRONTEND_ROOT / ".netlify" / "state.json"
_FRONTEND_NETLIFY_CONFIG = _FRONTEND_ROOT / ".netlify" / "netlify.toml"
_FRONTEND_BUILD_SCRIPT = _FRONTEND_ROOT / "scripts" / "netlify_build_web.sh"
_FRONTEND_PROD_BUILD_SCRIPT = _FRONTEND_ROOT / "scripts" / "build_prod.sh"
_DEFAULT_PUBLISH_DIR = _FRONTEND_ROOT / "build" / "web"
_KNOWN_LOCAL_LOG_CANDIDATES = (
    _REPO_ROOT / "netlify-build.log",
    _FRONTEND_ROOT / "netlify-build.log",
    _REPO_ROOT / "logs" / "netlify-build.log",
    _FRONTEND_ROOT / ".netlify" / "build.log",
)


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _json_safe(value: Any) -> Any:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral() else float(value)
    if isinstance(value, Path):
        return _repo_relative(value)
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    return value


def _issue(code: str, source: str, message: str, *, severity: str = "error") -> dict[str, Any]:
    return {
        "code": code,
        "source": source,
        "message": message,
        "severity": severity,
    }


def _mismatch(code: str, source: str, message: str, rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "code": code,
        "source": source,
        "message": message,
        "row_count": len(rows),
        "rows": rows,
    }


def _status_from(issues: list[dict[str, Any]], mismatches: list[dict[str, Any]]) -> str:
    severities = {str(issue.get("severity") or "error") for issue in issues}
    if "error" in severities:
        return "blocked"
    if "warning" in severities or mismatches:
        return "warning"
    return "ok"


def _surface(
    artifact_type: str,
    *,
    data: dict[str, Any],
    issues: list[dict[str, Any]],
    mismatches: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    mismatches = mismatches or []
    return {
        "artifact_type": artifact_type,
        "schema_version": SCHEMA_VERSION,
        "generated_at_utc": _now_iso(),
        "status": _status_from(issues, mismatches),
        "authority_note": AUTHORITY_NOTE,
        "data_sources": [
            "netlify.toml",
            "frontend/.netlify/state.json",
            "frontend/.netlify/netlify.toml",
            "frontend/build/web",
            "environment_presence_only",
            "netlify_api_readonly_when_configured",
        ],
        "read_only": True,
        "authority_override": False,
        "netlify_api_mutations_used": False,
        "deploy_triggered": False,
        "forbidden_actions": ["deploy", "build_trigger", "env_set", "env_unset", "site_update"],
        "data": _json_safe(data),
        "mismatches": _json_safe(mismatches),
        "issues": issues,
    }


def _repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(_REPO_ROOT.resolve()).as_posix()
    except ValueError as exc:
        raise RuntimeError(f"Path escapes repository root: {path}") from exc


def _read_json(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if not path.exists():
        return {}, [
            _issue(
                "netlify_file_missing",
                _repo_relative(path),
                f"{_repo_relative(path)} is missing",
                severity="warning",
            )
        ]
    try:
        return json.loads(path.read_text(encoding="utf-8")), []
    except json.JSONDecodeError:
        return {}, [
            _issue(
                "netlify_json_invalid",
                _repo_relative(path),
                f"{_repo_relative(path)} is not valid JSON",
            )
        ]


def _read_toml(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if not path.exists():
        return {}, [
            _issue(
                "netlify_file_missing",
                _repo_relative(path),
                f"{_repo_relative(path)} is missing",
                severity="warning",
            )
        ]
    try:
        return tomllib.loads(path.read_text(encoding="utf-8")), []
    except tomllib.TOMLDecodeError:
        return {}, [
            _issue(
                "netlify_toml_invalid",
                _repo_relative(path),
                f"{_repo_relative(path)} is not valid TOML",
            )
        ]


def _read_text_preview(path: Path, *, max_bytes: int = 20_000) -> tuple[str | None, list[dict[str, Any]]]:
    if not path.exists():
        return None, [
            _issue(
                "netlify_file_missing",
                _repo_relative(path),
                f"{_repo_relative(path)} is missing",
                severity="warning",
            )
        ]
    if path.stat().st_size > max_bytes:
        return None, [
            _issue(
                "netlify_log_too_large",
                _repo_relative(path),
                f"{_repo_relative(path)} exceeds the read-only preview limit",
                severity="warning",
            )
        ]
    try:
        return path.read_text(encoding="utf-8"), []
    except UnicodeDecodeError:
        return None, [
            _issue(
                "netlify_text_not_utf8",
                _repo_relative(path),
                f"{_repo_relative(path)} is not UTF-8 readable",
            )
        ]


def _file_info(path: Path) -> dict[str, Any]:
    exists = path.exists()
    info: dict[str, Any] = {
        "path": _repo_relative(path),
        "exists": exists,
    }
    if exists and path.is_file():
        stat = path.stat()
        info["size_bytes"] = stat.st_size
        info["modified_at_utc"] = datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat()
    return info


def _resolve_publish_dir(config: dict[str, Any]) -> Path:
    build = config.get("build") if isinstance(config.get("build"), dict) else {}
    base = str(build.get("base") or "frontend").strip() or "frontend"
    publish = str(build.get("publish") or "build/web").strip() or "build/web"
    base_path = (_REPO_ROOT / base).resolve()
    publish_path = (base_path / publish).resolve()
    _repo_relative(publish_path)
    return publish_path


def _load_local_netlify_config() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    config, issues = _read_toml(_NETLIFY_TOML)
    build = config.get("build") if isinstance(config.get("build"), dict) else {}
    return {
        "config_path": _repo_relative(_NETLIFY_TOML),
        "base": build.get("base"),
        "command": build.get("command"),
        "publish": build.get("publish"),
        "redirect_count": len(config.get("redirects") or []),
        "header_count": len(config.get("headers") or []),
        "parsed": bool(config),
    }, issues


def _site_id_from_state() -> tuple[str | None, dict[str, Any], list[dict[str, Any]]]:
    state, issues = _read_json(_FRONTEND_NETLIFY_STATE)
    state_site_id = str(state.get("siteId") or "").strip() or None
    configured_site_id = (settings.netlify_site_id or "").strip() or None
    site_id = configured_site_id or state_site_id
    return site_id, {
        "state_path": _repo_relative(_FRONTEND_NETLIFY_STATE),
        "state_file_exists": _FRONTEND_NETLIFY_STATE.exists(),
        "site_id_configured_in_env": configured_site_id is not None,
        "site_id_configured_in_state": state_site_id is not None,
        "site_id_source": "settings.netlify_site_id" if configured_site_id else "frontend/.netlify/state.json" if state_site_id else None,
    }, issues


def _netlify_api_config(site_id: str | None) -> dict[str, Any]:
    return {
        "site_id_present": bool(site_id),
        "auth_token_present": bool(settings.netlify_auth_token),
        "api_base_url": settings.netlify_api_base_url,
        "remote_read_enabled": bool(site_id and settings.netlify_auth_token),
    }


def _request_netlify_json(path: str) -> Any:
    base_url = str(settings.netlify_api_base_url or "https://api.netlify.com/api/v1").rstrip("/")
    token = settings.netlify_auth_token
    if not token:
        raise RuntimeError("NETLIFY_AUTH_TOKEN is not configured")
    request = Request(
        f"{base_url}{path}",
        method="GET",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "aveli-netlify-observability/1.0",
        },
    )
    with urlopen(request, timeout=5) as response:  # nosec B310 - read-only operator diagnostics
        raw = response.read()
    return json.loads(raw.decode("utf-8"))


async def _safe_netlify_json(source: str, path: str) -> tuple[Any | None, list[dict[str, Any]]]:
    try:
        return await asyncio.to_thread(_request_netlify_json, path), []
    except HTTPError as exc:
        return None, [
            _issue(
                "netlify_api_http_error",
                source,
                f"Netlify API read failed with HTTP {exc.code}",
                severity="warning",
            )
        ]
    except (URLError, TimeoutError, json.JSONDecodeError, RuntimeError) as exc:
        return None, [
            _issue(
                "netlify_api_read_unavailable",
                source,
                f"Netlify API read unavailable: {exc.__class__.__name__}",
                severity="warning",
            )
        ]


async def _latest_remote_deploy(site_id: str | None) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    if not site_id or not settings.netlify_auth_token:
        return None, [
            _issue(
                "netlify_remote_deploy_status_unconfigured",
                "netlify_api",
                "NETLIFY_AUTH_TOKEN and site id are required for live deploy status",
                severity="warning",
            )
        ]
    deploys, issues = await _safe_netlify_json(
        "netlify_api.deploys",
        f"/sites/{quote(site_id, safe='')}/deploys?per_page={_RECENT_LIMIT}",
    )
    if not isinstance(deploys, list) or not deploys:
        return None, issues + [
            _issue(
                "netlify_remote_deploy_missing",
                "netlify_api.deploys",
                "No Netlify deploys were returned",
                severity="warning",
            )
        ]
    latest = deploys[0]
    if not isinstance(latest, dict):
        return None, issues
    return _summarize_deploy(latest), issues


def _summarize_deploy(deploy: dict[str, Any]) -> dict[str, Any]:
    summary = deploy.get("summary") if isinstance(deploy.get("summary"), dict) else {}
    messages = summary.get("messages") if isinstance(summary.get("messages"), list) else []
    return {
        "id": deploy.get("id"),
        "build_id": deploy.get("build_id"),
        "state": deploy.get("state"),
        "context": deploy.get("context"),
        "branch": deploy.get("branch"),
        "commit_ref": deploy.get("commit_ref"),
        "created_at": deploy.get("created_at"),
        "updated_at": deploy.get("updated_at"),
        "published_at": deploy.get("published_at"),
        "deploy_time": deploy.get("deploy_time"),
        "url_present": bool(deploy.get("url") or deploy.get("ssl_url")),
        "admin_url_present": bool(deploy.get("admin_url")),
        "manual_deploy": deploy.get("manual_deploy"),
        "error_message": deploy.get("error_message"),
        "summary_status": summary.get("status"),
        "summary_messages": [
            {
                "type": message.get("type"),
                "title": message.get("title"),
                "description": message.get("description"),
            }
            for message in messages
            if isinstance(message, dict)
        ],
    }


def _local_build_output(publish_dir: Path) -> dict[str, Any]:
    build_commit = (publish_dir / ".build_commit").read_text(encoding="utf-8").strip() if (publish_dir / ".build_commit").exists() else None
    build_number = (publish_dir / ".build_number").read_text(encoding="utf-8").strip() if (publish_dir / ".build_number").exists() else None
    last_build_id = (publish_dir / ".last_build_id").read_text(encoding="utf-8").strip() if (publish_dir / ".last_build_id").exists() else None
    return {
        "publish_dir": _repo_relative(publish_dir),
        "publish_dir_exists": publish_dir.exists(),
        "index_html": _file_info(publish_dir / "index.html"),
        "main_bundle": _file_info(publish_dir / "main.dart.js"),
        "redirects": _file_info(publish_dir / "_redirects"),
        "version_json": _file_info(publish_dir / "version.json"),
        "build_commit": build_commit,
        "build_number": build_number,
        "last_build_id": last_build_id,
    }


def _env_presence(keys: tuple[str, ...]) -> list[dict[str, Any]]:
    return [
        {
            "name": key,
            "present": bool((os.environ.get(key) or "").strip()),
            "value_exposed": False,
        }
        for key in keys
    ]


async def get_deploy_status() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    mismatches: list[dict[str, Any]] = []
    config, config_issues = _read_toml(_NETLIFY_TOML)
    config_summary, summary_issues = _load_local_netlify_config()
    issues.extend(config_issues)
    issues.extend(summary_issues)
    site_id, state_summary, state_issues = _site_id_from_state()
    issues.extend(state_issues)
    publish_dir = _resolve_publish_dir(config) if config else _DEFAULT_PUBLISH_DIR
    local_build = _local_build_output(publish_dir)

    remote_latest, remote_issues = await _latest_remote_deploy(site_id)
    issues.extend(remote_issues)
    if remote_latest and local_build.get("build_commit") and remote_latest.get("commit_ref"):
        if local_build["build_commit"] != remote_latest["commit_ref"]:
            mismatches.append(
                _mismatch(
                    "netlify_local_build_commit_differs_from_latest_deploy",
                    "frontend/build/web_to_netlify_api.deploys",
                    "Local frontend build commit differs from the latest observed Netlify deploy",
                    [
                        {
                            "local_build_commit": local_build["build_commit"],
                            "latest_deploy_commit": remote_latest["commit_ref"],
                        }
                    ],
                )
            )

    return _surface(
        "netlify_deploy_status",
        data={
            "local_config": config_summary,
            "site_link": state_summary,
            "api": _netlify_api_config(site_id),
            "local_build_output": local_build,
            "remote_latest_deploy": remote_latest,
        },
        issues=issues,
        mismatches=mismatches,
    )


async def get_build_logs() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    site_id, state_summary, state_issues = _site_id_from_state()
    issues.extend(state_issues)
    remote_latest, remote_issues = await _latest_remote_deploy(site_id)
    issues.extend(remote_issues)

    local_logs: list[dict[str, Any]] = []
    for candidate in _KNOWN_LOCAL_LOG_CANDIDATES:
        if not candidate.exists():
            continue
        preview, preview_issues = _read_text_preview(candidate)
        issues.extend(preview_issues)
        local_logs.append(
            {
                "path": _repo_relative(candidate),
                "size_bytes": candidate.stat().st_size,
                "preview": preview,
            }
        )

    if not local_logs and not (remote_latest and remote_latest.get("summary_messages")):
        issues.append(
            _issue(
                "netlify_build_log_source_missing",
                "netlify_build_logs",
                "No local build log file or remote deploy summary messages are available",
                severity="warning",
            )
        )

    return _surface(
        "netlify_build_logs",
        data={
            "site_link": state_summary,
            "local_log_files": local_logs,
            "remote_latest_deploy_log_summary": {
                "deploy_id": remote_latest.get("id") if remote_latest else None,
                "build_id": remote_latest.get("build_id") if remote_latest else None,
                "state": remote_latest.get("state") if remote_latest else None,
                "messages": remote_latest.get("summary_messages") if remote_latest else [],
            },
            "full_remote_log_downloaded": False,
        },
        issues=issues,
    )


async def get_env_completeness() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    required = _env_presence(_REQUIRED_NETLIFY_ENV)
    optional = _env_presence(_OPTIONAL_NETLIFY_ENV)
    missing = [item["name"] for item in required if not item["present"]]
    if missing:
        issues.append(
            _issue(
                "netlify_required_env_missing",
                "process_environment",
                f"Required Netlify build env vars missing from current process: {', '.join(missing)}",
                severity="warning",
            )
        )

    config_summary, config_issues = _load_local_netlify_config()
    issues.extend(config_issues)
    if config_summary.get("base") != "frontend":
        issues.append(
            _issue(
                "netlify_build_base_unexpected",
                "netlify.toml",
                "Netlify build base is expected to be frontend",
                severity="warning",
            )
        )
    if config_summary.get("command") != "bash scripts/netlify_build_web.sh":
        issues.append(
            _issue(
                "netlify_build_command_unexpected",
                "netlify.toml",
                "Netlify build command differs from the canonical frontend build script",
                severity="warning",
            )
        )
    if config_summary.get("publish") != "build/web":
        issues.append(
            _issue(
                "netlify_publish_dir_unexpected",
                "netlify.toml",
                "Netlify publish directory differs from build/web relative to frontend",
                severity="warning",
            )
        )

    return _surface(
        "netlify_env_completeness",
        data={
            "local_config": config_summary,
            "required_env": required,
            "optional_env": optional,
            "remote_env_values_read": False,
            "secret_values_exposed": False,
        },
        issues=issues,
    )


async def get_frontend_backend_connectivity() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    config, config_issues = _read_toml(_NETLIFY_TOML)
    issues.extend(config_issues)
    publish_dir = _resolve_publish_dir(config) if config else _DEFAULT_PUBLISH_DIR
    local_build = _local_build_output(publish_dir)
    api_base_url_present = bool((os.environ.get("API_BASE_URL") or os.environ.get("FLUTTER_API_BASE_URL") or "").strip())
    frontend_base_url_present = bool((settings.frontend_base_url or os.environ.get("FLUTTER_FRONTEND_URL") or "").strip())

    required_files = [
        local_build["index_html"],
        local_build["main_bundle"],
        local_build["redirects"],
        local_build["version_json"],
    ]
    missing_files = [item["path"] for item in required_files if not item["exists"]]
    if missing_files:
        issues.append(
            _issue(
                "netlify_frontend_artifact_missing",
                "frontend/build/web",
                f"Frontend build artifacts are missing: {', '.join(missing_files)}",
                severity="warning",
            )
        )
    if not api_base_url_present:
        issues.append(
            _issue(
                "netlify_backend_api_url_missing",
                "process_environment",
                "API_BASE_URL/FLUTTER_API_BASE_URL is missing from current process",
                severity="warning",
            )
        )
    if not frontend_base_url_present:
        issues.append(
            _issue(
                "netlify_frontend_url_missing",
                "settings.frontend_base_url",
                "Frontend URL is not configured",
                severity="warning",
            )
        )

    return _surface(
        "netlify_frontend_backend_connectivity",
        data={
            "connectivity_mode": "configuration_and_artifact_readiness",
            "live_http_probe_performed": False,
            "api_base_url_present": api_base_url_present,
            "frontend_base_url_present": frontend_base_url_present,
            "local_build_output": local_build,
            "backend_health_endpoint": "/healthz",
            "frontend_rewrite_expected": "/* -> /index.html",
        },
        issues=issues,
    )


async def get_netlify_observability_summary() -> dict[str, Any]:
    deploy_status = await get_deploy_status()
    build_logs = await get_build_logs()
    env_completeness = await get_env_completeness()
    connectivity = await get_frontend_backend_connectivity()
    surfaces = {
        "deploy_status": deploy_status,
        "build_logs": build_logs,
        "env_completeness": env_completeness,
        "frontend_backend_connectivity": connectivity,
    }
    issues = [
        _issue(
            "netlify_observability_surface_not_ok",
            key,
            f"{key} status is {surface.get('status')}",
            severity="warning" if surface.get("status") == "warning" else "error",
        )
        for key, surface in surfaces.items()
        if surface.get("status") != "ok"
    ]
    mismatches = [
        item
        for surface in surfaces.values()
        for item in surface.get("mismatches", [])
    ]
    return _surface(
        "netlify_observability_summary",
        data={
            "surface_status": {
                key: surface.get("status")
                for key, surface in surfaces.items()
            },
            "remote_read_enabled": bool(settings.netlify_auth_token and (settings.netlify_site_id or _FRONTEND_NETLIFY_STATE.exists())),
        },
        issues=issues,
        mismatches=mismatches,
    )
