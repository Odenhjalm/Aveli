from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any, Awaitable

from ..config import settings
from . import (
    logs_observability,
    netlify_observability,
    stripe_observability,
    supabase_observability,
)


SCHEMA_VERSION = "dev_operator_observability_v1"
AUTHORITY_NOTE = "observability_not_authority"

_REPO_ROOT = Path(__file__).resolve().parents[3]
_RETRIEVAL_OBSERVABILITY_ROOT = _REPO_ROOT / ".repo_index" / "observability"
_INDEX_MANIFEST_PATH = _REPO_ROOT / ".repo_index" / "index_manifest.json"
_PROMOTION_RESULT_PATH = _REPO_ROOT / ".repo_index" / "promotion_result.json"
_B01_RESULT_ROOT = _REPO_ROOT / "actual_truth" / "DETERMINED_TASKS" / "retrieval_index_build_execution"

_RETRIEVAL_HEALTH_FILES = {
    "retrieval_runtime_health": _RETRIEVAL_OBSERVABILITY_ROOT / "retrieval_runtime_health.json",
    "retrieval_artifact_health": _RETRIEVAL_OBSERVABILITY_ROOT / "retrieval_artifact_health.json",
    "retrieval_model_health": _RETRIEVAL_OBSERVABILITY_ROOT / "retrieval_model_health.json",
    "retrieval_dependency_health": _RETRIEVAL_OBSERVABILITY_ROOT / "retrieval_dependency_health.json",
    "retrieval_last_build_status": _RETRIEVAL_OBSERVABILITY_ROOT / "retrieval_last_build_status.json",
}
_RETRIEVAL_QUERY_TRACE_PATH = _RETRIEVAL_OBSERVABILITY_ROOT / "retrieval_query_trace.jsonl"


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(_REPO_ROOT.resolve()).as_posix()
    except ValueError as exc:
        raise RuntimeError(f"Path escapes repository root: {path}") from exc


def _json_safe(value: Any) -> Any:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()
    if isinstance(value, Path):
        return _repo_relative(value)
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    return value


def _surface(artifact_type: str, *, status: str, data: dict[str, Any]) -> dict[str, Any]:
    return {
        "artifact_type": artifact_type,
        "schema_version": SCHEMA_VERSION,
        "generated_at_utc": _now_iso(),
        "status": status,
        "authority_note": AUTHORITY_NOTE,
        "read_only": True,
        "authority_override": False,
        "data": _json_safe(data),
    }


def _read_json(path: Path) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    try:
        _repo_relative(path)
    except RuntimeError as exc:
        return None, {
            "code": "path_escape",
            "source": str(path),
            "message": str(exc),
            "severity": "error",
        }
    if not path.exists():
        return None, {
            "code": "file_missing",
            "source": _repo_relative(path),
            "message": f"{_repo_relative(path)} is missing",
            "severity": "warning",
        }
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except json.JSONDecodeError:
        return None, {
            "code": "json_invalid",
            "source": _repo_relative(path),
            "message": f"{_repo_relative(path)} is not valid JSON",
            "severity": "error",
        }


def _read_query_traces(limit: int | None = None) -> list[dict[str, Any]]:
    if not _RETRIEVAL_QUERY_TRACE_PATH.exists():
        return []
    traces: list[dict[str, Any]] = []
    for raw_line in _RETRIEVAL_QUERY_TRACE_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict):
            traces.append(record)
    traces.sort(
        key=lambda item: str(item.get("generated_at_utc") or item.get("started_at_utc") or ""),
        reverse=True,
    )
    if limit is not None:
        return traces[:limit]
    return traces


def _status_to_operator_state(status: Any) -> str:
    normalized = str(status or "").strip().lower()
    if normalized in {"pass", "ok", "ready"}:
        return "READY"
    if normalized in {"blocked", "fail", "failed", "error"}:
        return "BLOCKED"
    return "DEGRADED"


def _combine_operator_states(states: list[str]) -> str:
    if any(state == "BLOCKED" for state in states):
        return "BLOCKED"
    if any(state == "DEGRADED" for state in states):
        return "DEGRADED"
    return "READY"


def _surface_status(surface: dict[str, Any] | None) -> str:
    if not isinstance(surface, dict):
        return "missing"
    return str(surface.get("status") or "unknown")


def _summarize_query_trace(trace: dict[str, Any] | None) -> dict[str, Any]:
    if not trace:
        return {"available": False}
    return {
        "available": True,
        "trace_id": trace.get("trace_id"),
        "request_id": trace.get("request_id"),
        "correlation_id": trace.get("correlation_id"),
        "status": trace.get("status"),
        "duration_ms": trace.get("duration_ms"),
        "candidate_counts": trace.get("candidate_counts") or {},
        "evidence_count": trace.get("evidence_count"),
        "models": trace.get("models") or {},
        "failure_code": trace.get("failure_code"),
        "started_at_utc": trace.get("started_at_utc"),
        "generated_at_utc": trace.get("generated_at_utc"),
    }


def _retrieval_surfaces() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    surfaces: dict[str, Any] = {}
    issues: list[dict[str, Any]] = []
    for name, path in _RETRIEVAL_HEALTH_FILES.items():
        payload, issue = _read_json(path)
        if issue:
            issues.append(issue)
        surfaces[name] = payload or {
            "artifact_type": name,
            "status": "missing",
            "path": _repo_relative(path),
        }
    semantic_status = "PASS" if all(_RETRIEVAL_HEALTH_FILES[name].exists() for name in _RETRIEVAL_HEALTH_FILES) else "BLOCKED"
    surfaces["semantic_mcp_health"] = {
        "artifact_type": "semantic_mcp_health",
        "status": semantic_status,
        "server_name": "aveli-semantic-search",
        "data_sources": ["retrieval_observability_files", ".vscode/mcp.json"],
        "read_only": True,
        "authority_override": False,
    }
    return surfaces, issues


async def _safe_call(label: str, awaitable: Awaitable[dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any] | None]:
    try:
        return await awaitable, None
    except Exception as exc:
        return {
            "artifact_type": label,
            "status": "blocked",
            "read_only": True,
            "authority_override": False,
            "error_class": exc.__class__.__name__,
        }, {
            "code": "surface_read_failed",
            "source": label,
            "message": f"{label} could not be read: {exc.__class__.__name__}",
            "severity": "error",
        }


def _worker_status(worker_health: dict[str, Any]) -> dict[str, Any]:
    workers = worker_health.get("worker_health") if isinstance(worker_health.get("worker_health"), dict) else {}
    worker_statuses = {
        name: data.get("status")
        for name, data in workers.items()
        if isinstance(data, dict)
    }
    operator_states = [_status_to_operator_state(status) for status in worker_statuses.values()]
    return {
        "status": _combine_operator_states(operator_states) if operator_states else "DEGRADED",
        "workers": worker_statuses,
    }


def _subsystem_statuses(
    *,
    retrieval: dict[str, Any],
    worker_health: dict[str, Any],
    supabase: dict[str, Any],
    stripe: dict[str, Any],
    netlify: dict[str, Any],
) -> dict[str, Any]:
    retrieval_children = {
        name: _surface_status(surface)
        for name, surface in retrieval.items()
    }
    retrieval_state = _combine_operator_states(
        [_status_to_operator_state(status) for status in retrieval_children.values()]
    )
    worker_summary = _worker_status(worker_health)
    backend_mcp_children = {
        "logs_mcp": "ok" if settings.logs_mcp_enabled else "disabled",
        "domain_observability_mcp": "ok" if settings.domain_observability_mcp_enabled else "disabled",
        "verification_mcp": "ok" if settings.verification_mcp_enabled else "disabled",
        "dev_operator_mcp": "ok" if settings.dev_operator_observability_mcp_enabled else "disabled",
    }
    external = {
        "supabase": {key: _surface_status(value) for key, value in supabase.items()},
        "stripe": {key: _surface_status(value) for key, value in stripe.items()},
        "netlify": {key: _surface_status(value) for key, value in netlify.items()},
    }
    return {
        "retrieval": {
            "status": retrieval_state,
            "children": retrieval_children,
        },
        "backend_workers": worker_summary,
        "backend_mcp": {
            "status": _combine_operator_states(
                [_status_to_operator_state(status) for status in backend_mcp_children.values()]
            ),
            "children": backend_mcp_children,
        },
        "supabase": {
            "status": _combine_operator_states(
                [_status_to_operator_state(status) for status in external["supabase"].values()]
            ),
            "children": external["supabase"],
        },
        "stripe": {
            "status": _combine_operator_states(
                [_status_to_operator_state(status) for status in external["stripe"].values()]
            ),
            "children": external["stripe"],
        },
        "netlify": {
            "status": _combine_operator_states(
                [_status_to_operator_state(status) for status in external["netlify"].values()]
            ),
            "children": external["netlify"],
        },
    }


def _active_build_summary(retrieval: dict[str, Any]) -> dict[str, Any]:
    manifest, manifest_issue = _read_json(_INDEX_MANIFEST_PATH)
    promotion, promotion_issue = _read_json(_PROMOTION_RESULT_PATH)
    runtime = retrieval.get("retrieval_runtime_health") if isinstance(retrieval.get("retrieval_runtime_health"), dict) else {}
    model = retrieval.get("retrieval_model_health") if isinstance(retrieval.get("retrieval_model_health"), dict) else {}
    manifest_data = manifest or {}
    corpus = manifest_data.get("corpus") if isinstance(manifest_data.get("corpus"), dict) else {}
    promotion_data = promotion or {}
    historical_attempts = []
    if _B01_RESULT_ROOT.exists():
        for path in sorted(_B01_RESULT_ROOT.glob("B01_*result*.json")):
            payload, issue = _read_json(path)
            if issue or not isinstance(payload, dict):
                continue
            historical_attempts.append(
                {
                    "path": _repo_relative(path),
                    "artifact_type": payload.get("artifact_type"),
                    "status": payload.get("status"),
                    "build_id": payload.get("build_id"),
                    "build_mode": payload.get("build_mode"),
                    "promotion_occurred": payload.get("promotion_occurred"),
                    "superseded_by_active_promotion": payload.get("build_id") == promotion_data.get("build_id")
                    and payload.get("status") != promotion_data.get("status"),
                }
            )
    return {
        "active_build_id": promotion_data.get("build_id"),
        "manifest_state": manifest_data.get("manifest_state") or promotion_data.get("active_manifest_state"),
        "corpus_file_count": len(corpus.get("files") or []) if isinstance(corpus.get("files"), list) else None,
        "chunk_count": runtime.get("chunk_count"),
        "model_ids": {
            "embedding": manifest_data.get("embedding_model"),
            "rerank": manifest_data.get("rerank_model"),
        },
        "model_revisions": {
            "embedding": ((model.get("models") or {}).get("embedding") or {}).get("model_revision")
            if isinstance(model.get("models"), dict)
            else None,
            "rerank": ((model.get("models") or {}).get("rerank") or {}).get("model_revision")
            if isinstance(model.get("models"), dict)
            else None,
        },
        "active_promotion_result_path": _repo_relative(_PROMOTION_RESULT_PATH),
        "promotion_status": promotion_data.get("status"),
        "promotion_completed_at_utc": promotion_data.get("promotion_completed_at_utc"),
        "historical_attempts": historical_attempts,
        "issues": [issue for issue in (manifest_issue, promotion_issue) if issue],
    }


def _failure_from_query_traces() -> dict[str, Any] | None:
    for trace in _read_query_traces(limit=None):
        if str(trace.get("status") or "").upper() != "PASS" or trace.get("failure_code"):
            return {
                "found": True,
                "subsystem": "retrieval",
                "source": "retrieval_query_trace",
                "status": trace.get("status"),
                "failure_code": trace.get("failure_code") or "retrieval_trace_failed",
                "occurred_at_utc": trace.get("generated_at_utc") or trace.get("started_at_utc"),
                "request_id": trace.get("request_id"),
                "correlation_id": trace.get("correlation_id"),
                "next_diagnostic_step": {
                    "tool": "dev_operator_trace",
                    "arguments": {"correlation_id": trace.get("correlation_id")},
                },
            }
    return None


def _failure_from_recent_errors(recent_errors: dict[str, Any]) -> dict[str, Any] | None:
    errors = recent_errors.get("recent_errors") if isinstance(recent_errors.get("recent_errors"), list) else []
    if not errors:
        return None
    item = errors[0]
    return {
        "found": True,
        "subsystem": "backend",
        "source": item.get("source") or "logs",
        "status": "error",
        "failure_code": item.get("event") or item.get("failure_type") or "backend_recent_error",
        "occurred_at_utc": item.get("timestamp"),
        "request_id": item.get("request_id"),
        "correlation_id": item.get("correlation_id"),
        "next_diagnostic_step": {
            "tool": "get_recent_errors",
            "arguments": {"limit": 20},
        },
    }


def _failure_from_subsystems(subsystems: dict[str, Any]) -> dict[str, Any]:
    for name, summary in subsystems.items():
        status = str(summary.get("status") if isinstance(summary, dict) else summary)
        if status in {"BLOCKED", "DEGRADED"}:
            return {
                "found": True,
                "subsystem": name,
                "source": "dev_operator_dashboard",
                "status": status,
                "failure_code": f"{name.lower()}_{status.lower()}",
                "occurred_at_utc": None,
                "request_id": None,
                "correlation_id": None,
                "next_diagnostic_step": {
                    "tool": "dev_operator_dashboard",
                    "arguments": {},
                },
            }
    return {
        "found": False,
        "subsystem": None,
        "source": None,
        "status": "READY",
        "failure_code": None,
        "occurred_at_utc": None,
        "request_id": None,
        "correlation_id": None,
        "next_diagnostic_step": None,
    }


async def _external_surfaces() -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
    calls = await asyncio.gather(
        _safe_call("supabase_connection_health", supabase_observability.get_connection_health()),
        _safe_call("supabase_domain_projection_health", supabase_observability.get_domain_projection_health()),
        _safe_call("supabase_storage_health", supabase_observability.get_storage_health()),
        _safe_call("stripe_checkout_health", stripe_observability.get_checkout_sessions()),
        _safe_call("stripe_subscription_health", stripe_observability.get_subscriptions()),
        _safe_call("stripe_payment_health", stripe_observability.get_payments()),
        _safe_call("stripe_webhook_health", stripe_observability.get_webhook_state()),
        _safe_call("stripe_app_reconciliation", stripe_observability.get_app_reconciliation()),
        _safe_call("netlify_deploy_health", netlify_observability.get_deploy_status()),
        _safe_call("netlify_build_health", netlify_observability.get_build_logs()),
        _safe_call("netlify_env_health", netlify_observability.get_env_completeness()),
        _safe_call("netlify_connectivity_health", netlify_observability.get_frontend_backend_connectivity()),
    )
    keys = [
        ("supabase", "supabase_connection_health"),
        ("supabase", "supabase_domain_projection_health"),
        ("supabase", "supabase_storage_health"),
        ("stripe", "stripe_checkout_health"),
        ("stripe", "stripe_subscription_health"),
        ("stripe", "stripe_payment_health"),
        ("stripe", "stripe_webhook_health"),
        ("stripe", "stripe_app_reconciliation"),
        ("netlify", "netlify_deploy_health"),
        ("netlify", "netlify_build_health"),
        ("netlify", "netlify_env_health"),
        ("netlify", "netlify_connectivity_health"),
    ]
    grouped: dict[str, dict[str, Any]] = {"supabase": {}, "stripe": {}, "netlify": {}}
    issues: list[dict[str, Any]] = []
    for (group, key), (payload, issue) in zip(keys, calls):
        grouped[group][key] = payload
        if issue:
            issues.append(issue)
    return grouped["supabase"], grouped["stripe"], grouped["netlify"], issues


async def _dashboard_data() -> dict[str, Any]:
    retrieval, retrieval_issues = _retrieval_surfaces()
    worker_health, worker_issue = await _safe_call("backend_worker_health", logs_observability.get_worker_health())
    recent_errors, recent_error_issue = await _safe_call("backend_recent_errors", logs_observability.get_recent_errors(limit=10))
    supabase, stripe, netlify, external_issues = await _external_surfaces()
    issues = [
        *retrieval_issues,
        *external_issues,
        *[issue for issue in (worker_issue, recent_error_issue) if issue],
    ]
    subsystems = _subsystem_statuses(
        retrieval=retrieval,
        worker_health=worker_health,
        supabase=supabase,
        stripe=stripe,
        netlify=netlify,
    )
    overall_status = _combine_operator_states(
        [str(summary.get("status")) for summary in subsystems.values() if isinstance(summary, dict)]
    )
    last_query = _summarize_query_trace(_read_query_traces(limit=1)[0] if _read_query_traces(limit=1) else None)
    last_failure = (
        _failure_from_recent_errors(recent_errors)
        or _failure_from_query_traces()
        or _failure_from_subsystems(subsystems)
    )
    active_build = _active_build_summary(retrieval)
    return {
        "overall_status": overall_status,
        "subsystem_statuses": subsystems,
        "last_failure": last_failure,
        "last_query_summary": last_query,
        "active_build_summary": active_build,
        "correlation_summary": {
            "last_query_correlation_id": last_query.get("correlation_id") if last_query.get("available") else None,
            "trace_tool": "dev_operator_trace",
            "traceable_sources": [
                "retrieval_query_trace.jsonl",
                "backend_current_worker_health",
                "supabase_current_observability",
                "stripe_current_observability",
                "netlify_current_observability",
            ],
        },
        "observability_inputs": {
            "retrieval": retrieval,
            "backend_worker_health": worker_health,
            "backend_recent_errors": recent_errors,
            "supabase": supabase,
            "stripe": stripe,
            "netlify": netlify,
        },
        "issues": issues,
    }


async def get_dev_operator_dashboard() -> dict[str, Any]:
    data = await _dashboard_data()
    return _surface("dev_operator_dashboard", status=data["overall_status"], data=data)


async def get_dev_operator_last_query() -> dict[str, Any]:
    traces = _read_query_traces(limit=1)
    summary = _summarize_query_trace(traces[0] if traces else None)
    status = "READY" if summary.get("available") else "DEGRADED"
    return _surface("dev_operator_last_query", status=status, data=summary)


async def get_dev_operator_last_failure() -> dict[str, Any]:
    worker_recent_errors, worker_issue = await _safe_call("backend_recent_errors", logs_observability.get_recent_errors(limit=10))
    dashboard = await _dashboard_data()
    failure = (
        _failure_from_recent_errors(worker_recent_errors)
        or _failure_from_query_traces()
        or _failure_from_subsystems(dashboard["subsystem_statuses"])
    )
    if worker_issue:
        failure = {
            "found": True,
            "subsystem": "backend",
            "source": worker_issue["source"],
            "status": "BLOCKED",
            "failure_code": worker_issue["code"],
            "occurred_at_utc": None,
            "request_id": None,
            "correlation_id": None,
            "next_diagnostic_step": {"tool": "get_recent_errors", "arguments": {"limit": 20}},
        }
    status = "DEGRADED" if failure.get("found") else "READY"
    return _surface("dev_operator_last_failure", status=status, data=failure)


async def get_dev_operator_trace(correlation_id: str) -> dict[str, Any]:
    normalized = str(correlation_id or "").strip()
    if not normalized:
        raise ValueError("correlation_id is required")
    traces = [
        _summarize_query_trace(trace)
        for trace in _read_query_traces(limit=None)
        if str(trace.get("correlation_id") or "") == normalized
    ]
    dashboard = await _dashboard_data()
    events: dict[str, Any] = {
        "retrieval": traces,
        "semantic_mcp": [
            {
                "link_type": "inferred_from_retrieval_trace",
                "correlation_id": normalized,
                "request_id": trace.get("request_id"),
                "status": trace.get("status"),
            }
            for trace in traces
        ],
        "backend_mcp": [
            {
                "link_type": "current_snapshot",
                "correlation_id": normalized,
                "status": dashboard["subsystem_statuses"]["backend_mcp"]["status"],
            }
        ],
        "supabase": [
            {
                "link_type": "current_snapshot",
                "correlation_id": normalized,
                "status": dashboard["subsystem_statuses"]["supabase"]["status"],
            }
        ],
        "stripe": [
            {
                "link_type": "current_snapshot",
                "correlation_id": normalized,
                "status": dashboard["subsystem_statuses"]["stripe"]["status"],
            }
        ],
        "netlify": [
            {
                "link_type": "current_snapshot",
                "correlation_id": normalized,
                "status": dashboard["subsystem_statuses"]["netlify"]["status"],
            }
        ],
    }
    live_segments_present = all(events[key] for key in ("backend_mcp", "supabase", "stripe", "netlify"))
    if traces and live_segments_present:
        trace_result = "full_result"
    elif traces or live_segments_present:
        trace_result = "partial_result"
    else:
        trace_result = "zero_result"
    return _surface(
        "dev_operator_trace",
        status="READY" if trace_result == "full_result" else "DEGRADED",
        data={
            "correlation_id": normalized,
            "trace_result": trace_result,
            "events": events,
            "known_event_count": sum(len(value) for value in events.values() if isinstance(value, list)),
            "limitations": [
                "External Supabase, Stripe, and Netlify surfaces are current read-only snapshots unless their systems persist matching correlation events."
            ],
        },
    )
