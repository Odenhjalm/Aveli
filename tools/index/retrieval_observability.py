from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
INDEX_ROOT = ROOT / ".repo_index"
OBSERVABILITY_ROOT_RELATIVE = ".repo_index/observability"
OBSERVABILITY_ROOT = INDEX_ROOT / "observability"

RETRIEVAL_RUNTIME_HEALTH_PATH = OBSERVABILITY_ROOT / "retrieval_runtime_health.json"
RETRIEVAL_ARTIFACT_HEALTH_PATH = OBSERVABILITY_ROOT / "retrieval_artifact_health.json"
RETRIEVAL_MODEL_HEALTH_PATH = OBSERVABILITY_ROOT / "retrieval_model_health.json"
RETRIEVAL_DEPENDENCY_HEALTH_PATH = OBSERVABILITY_ROOT / "retrieval_dependency_health.json"
RETRIEVAL_QUERY_TRACE_PATH = OBSERVABILITY_ROOT / "retrieval_query_trace.jsonl"
RETRIEVAL_LAST_BUILD_STATUS_PATH = OBSERVABILITY_ROOT / "retrieval_last_build_status.json"

INDEX_MANIFEST_PATH = INDEX_ROOT / "index_manifest.json"
PROMOTION_RESULT_PATH = INDEX_ROOT / "promotion_result.json"

SCHEMA_VERSION = "dev_observability_v1"
AUTHORITY_NOTE = "telemetry_not_authority"


class RetrievalObservabilityError(RuntimeError):
    pass


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_json_dumps(data: object) -> str:
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def is_relative_to_path(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def normalize_repo_relative_path(path_text: str, field_name: str = "path") -> str:
    if not isinstance(path_text, str) or not path_text.strip():
        raise RetrievalObservabilityError(f"FEL: {field_name} maste vara en icke-tom repo-relativ sokvag")
    if "\\" in path_text:
        raise RetrievalObservabilityError(f"FEL: {field_name} maste anvanda forward slash")
    path = Path(path_text)
    if path.is_absolute() or ".." in path.parts:
        raise RetrievalObservabilityError(f"FEL: {field_name} maste vara repo-relativ utan parent traversal")
    normalized = path.as_posix()
    if normalized.startswith("./"):
        normalized = normalized[2:]
    if normalized != path_text:
        raise RetrievalObservabilityError(f"FEL: {field_name} maste vara normaliserad")
    return normalized


def repo_relative_path(path: Path) -> str:
    resolved = path.resolve()
    resolved_root = ROOT.resolve()
    if resolved == resolved_root or not is_relative_to_path(resolved, resolved_root):
        raise RetrievalObservabilityError(f"FEL: sokvag ligger utanfor repo-root: {path}")
    return resolved.relative_to(resolved_root).as_posix()


def resolve_repo_relative_path(path_text: str, field_name: str = "path") -> Path:
    normalized = normalize_repo_relative_path(path_text, field_name)
    resolved = (ROOT / normalized).resolve()
    resolved_root = ROOT.resolve()
    if resolved == resolved_root or not is_relative_to_path(resolved, resolved_root):
        raise RetrievalObservabilityError(f"FEL: {field_name} ligger utanfor repo-root: {path_text}")
    return resolved


def require_observability_write_path(path: Path) -> Path:
    resolved = path.resolve()
    observability_root = OBSERVABILITY_ROOT.resolve()
    if resolved == observability_root or not is_relative_to_path(resolved, observability_root):
        raise RetrievalObservabilityError(
            f"FEL: observability-skrivning utanfor {OBSERVABILITY_ROOT_RELATIVE}: {display_path(path)}"
        )
    if resolved.parent != observability_root:
        raise RetrievalObservabilityError(
            f"FEL: observability-skrivning far endast ske direkt under {OBSERVABILITY_ROOT_RELATIVE}: "
            f"{display_path(path)}"
        )
    return resolved


def base_surface(artifact_type: str, status: str, *, generated_at_utc: str | None = None) -> dict[str, Any]:
    if not isinstance(artifact_type, str) or not artifact_type.strip():
        raise RetrievalObservabilityError("FEL: artifact_type maste vara en icke-tom strang")
    if not isinstance(status, str) or not status.strip():
        raise RetrievalObservabilityError("FEL: status maste vara en icke-tom strang")
    return {
        "artifact_type": artifact_type.strip(),
        "schema_version": SCHEMA_VERSION,
        "generated_at_utc": generated_at_utc or utc_now_iso(),
        "status": status.strip(),
        "authority_note": AUTHORITY_NOTE,
    }


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    target = require_observability_write_path(path)
    if not isinstance(payload, dict):
        raise RetrievalObservabilityError("FEL: atomic_write_json kraver JSON-objekt")
    target.parent.mkdir(parents=True, exist_ok=True)
    temp_path = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    try:
        temp_path.write_text(canonical_json_dumps(payload) + "\n", encoding="utf-8", newline="\n")
        temp_path.replace(target)
    finally:
        if temp_path.exists():
            temp_path.unlink()


def append_jsonl(path: Path, record: dict[str, Any]) -> None:
    target = require_observability_write_path(path)
    if target.suffix != ".jsonl":
        raise RetrievalObservabilityError(f"FEL: JSONL-append kraver .jsonl-fil: {display_path(path)}")
    if not isinstance(record, dict):
        raise RetrievalObservabilityError("FEL: append_jsonl kraver JSON-objekt")
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(canonical_json_dumps(record) + "\n")


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    if not path.exists() or not path.is_file():
        raise RetrievalObservabilityError(f"FEL: {label} saknas vid {display_path(path)}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RetrievalObservabilityError(f"FEL: ogiltig JSON i {display_path(path)}") from exc
    if not isinstance(data, dict):
        raise RetrievalObservabilityError(f"FEL: {label} maste vara ett JSON-objekt")
    return data


def read_build_lineage() -> dict[str, Any]:
    manifest = load_json_object(INDEX_MANIFEST_PATH, ".repo_index/index_manifest.json")
    promotion_result = load_json_object(PROMOTION_RESULT_PATH, ".repo_index/promotion_result.json")

    corpus = manifest.get("corpus")
    files = corpus.get("files") if isinstance(corpus, dict) else None
    if not isinstance(files, list):
        raise RetrievalObservabilityError("FEL: indexmanifest corpus.files maste vara en lista")

    build_id = promotion_result.get("build_id")
    if not isinstance(build_id, str) or not build_id.strip():
        raise RetrievalObservabilityError("FEL: promotion_result.build_id saknas")

    manifest_state = manifest.get("manifest_state")
    if not isinstance(manifest_state, str) or not manifest_state.strip():
        raise RetrievalObservabilityError("FEL: indexmanifest manifest_state saknas")

    return {
        "active_build_id": build_id.strip(),
        "manifest_state": manifest_state.strip(),
        "corpus_size": len(files),
    }


__all__ = [
    "AUTHORITY_NOTE",
    "OBSERVABILITY_ROOT",
    "OBSERVABILITY_ROOT_RELATIVE",
    "PROMOTION_RESULT_PATH",
    "RETRIEVAL_ARTIFACT_HEALTH_PATH",
    "RETRIEVAL_DEPENDENCY_HEALTH_PATH",
    "RETRIEVAL_LAST_BUILD_STATUS_PATH",
    "RETRIEVAL_MODEL_HEALTH_PATH",
    "RETRIEVAL_QUERY_TRACE_PATH",
    "RETRIEVAL_RUNTIME_HEALTH_PATH",
    "SCHEMA_VERSION",
    "RetrievalObservabilityError",
    "append_jsonl",
    "atomic_write_json",
    "base_surface",
    "canonical_json_dumps",
    "display_path",
    "normalize_repo_relative_path",
    "read_build_lineage",
    "repo_relative_path",
    "resolve_repo_relative_path",
    "require_observability_write_path",
]
