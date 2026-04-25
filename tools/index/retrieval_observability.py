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


def json_safe_value(value: Any) -> Any:
    if isinstance(value, Path):
        return display_path(value)
    if isinstance(value, dict):
        return {str(key): json_safe_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe_value(item) for item in value]
    return value


def canonical_json_dumps(data: object) -> str:
    return json.dumps(json_safe_value(data), ensure_ascii=False, separators=(",", ":"), sort_keys=True)


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


def load_optional_json_object(path: Path) -> dict[str, Any] | None:
    if not path.exists() or not path.is_file():
        return None
    return load_json_object(path, display_path(path))


def read_jsonl_records(path: Path, *, limit: int | None = None) -> list[dict[str, Any]]:
    if not path.exists() or not path.is_file():
        return []
    records: list[dict[str, Any]] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    if limit is not None:
        if limit <= 0:
            raise RetrievalObservabilityError("FEL: limit maste vara positivt")
        lines = lines[-limit:]
    for line_number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise RetrievalObservabilityError(
                f"FEL: ogiltig JSONL-rad i {display_path(path)} pa rad {line_number}"
            ) from exc
        if not isinstance(value, dict):
            raise RetrievalObservabilityError(
                f"FEL: JSONL-rad i {display_path(path)} pa rad {line_number} ar inte objekt"
            )
        records.append(value)
    return records


def read_last_query_trace() -> dict[str, Any] | None:
    records = read_jsonl_records(RETRIEVAL_QUERY_TRACE_PATH, limit=1)
    return records[-1] if records else None


def read_recent_query_traces(*, limit: int = 10) -> list[dict[str, Any]]:
    return read_jsonl_records(RETRIEVAL_QUERY_TRACE_PATH, limit=limit)


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


def _manifest_summary(manifest: dict[str, Any]) -> dict[str, Any]:
    corpus = manifest.get("corpus") if isinstance(manifest.get("corpus"), dict) else {}
    files = corpus.get("files") if isinstance(corpus.get("files"), list) else []
    return {
        "manifest_state": manifest.get("manifest_state"),
        "contract_version": manifest.get("contract_version"),
        "corpus_file_count": len(files),
        "corpus_manifest_hash": manifest.get("corpus_manifest_hash"),
        "chunk_manifest_hash": manifest.get("chunk_manifest_hash"),
        "embedding_model": manifest.get("embedding_model"),
        "rerank_model": manifest.get("rerank_model"),
        "top_k": manifest.get("top_k"),
        "vector_candidate_k": manifest.get("vector_candidate_k"),
        "lexical_candidate_k": manifest.get("lexical_candidate_k"),
    }


def _model_binding_summary(binding: dict[str, Any]) -> dict[str, Any]:
    tokenizer_files = binding.get("tokenizer_files")
    return {
        "model_id": binding.get("model_id"),
        "model_revision": binding.get("model_revision"),
        "local_path": binding.get("local_path"),
        "snapshot_hash": binding.get("snapshot_hash"),
        "tokenizer_id": binding.get("tokenizer_id"),
        "tokenizer_revision": binding.get("tokenizer_revision"),
        "tokenizer_files_hash": binding.get("tokenizer_files_hash"),
        "tokenizer_file_count": len(tokenizer_files) if isinstance(tokenizer_files, dict) else 0,
        "local_files_only": binding.get("local_files_only"),
        "trust_remote_code": binding.get("trust_remote_code"),
    }


def write_retrieval_runtime_health(runtime_state: dict[str, Any]) -> dict[str, Any]:
    manifest = runtime_state.get("index_manifest")
    payload = base_surface("retrieval_runtime_health", "PASS")
    payload.update(
        {
            "warm_runtime_ready": True,
            "embedding_model_loaded": bool(runtime_state.get("warm_models", {}).get("embedding")),
            "rerank_model_loaded": bool(runtime_state.get("warm_models", {}).get("rerank")),
            "manifest": _manifest_summary(manifest if isinstance(manifest, dict) else {}),
            "lexical_doc_count": runtime_state.get("lexical_runtime_index", {}).get("doc_count"),
            "chunk_count": len(runtime_state.get("chunk_records", [])),
        }
    )
    atomic_write_json(RETRIEVAL_RUNTIME_HEALTH_PATH, payload)
    return payload


def write_retrieval_artifact_health(runtime_state: dict[str, Any]) -> dict[str, Any]:
    artifact_integrity = runtime_state.get("artifact_integrity")
    if not isinstance(artifact_integrity, dict):
        artifact_integrity = {}
    payload = base_surface("retrieval_artifact_health", "PASS")
    payload.update(
        {
            "artifact_integrity_status": artifact_integrity.get("status"),
            "artifact_set": artifact_integrity.get("artifact_set"),
            "chunk_manifest": artifact_integrity.get("chunk_manifest"),
            "lexical_index": artifact_integrity.get("lexical_index"),
            "vector_index": artifact_integrity.get("vector_index"),
        }
    )
    atomic_write_json(RETRIEVAL_ARTIFACT_HEALTH_PATH, payload)
    return payload


def write_retrieval_model_health(runtime_state: dict[str, Any]) -> dict[str, Any]:
    model_authority = runtime_state.get("model_authority")
    if not isinstance(model_authority, dict):
        model_authority = {}
    models = model_authority.get("models") if isinstance(model_authority.get("models"), dict) else {}
    embedding = models.get("embedding") if isinstance(models.get("embedding"), dict) else {}
    rerank = models.get("rerank") if isinstance(models.get("rerank"), dict) else {}
    payload = base_surface("retrieval_model_health", "PASS")
    payload.update(
        {
            "authority_path": model_authority.get("authority_path_text"),
            "authority_root": model_authority.get("authority_root"),
            "local_files_only": model_authority.get("local_files_only"),
            "network_allowed": model_authority.get("network_allowed"),
            "cache_resolution_allowed": model_authority.get("cache_resolution_allowed"),
            "models": {
                "embedding": _model_binding_summary(embedding),
                "rerank": _model_binding_summary(rerank),
            },
        }
    )
    atomic_write_json(RETRIEVAL_MODEL_HEALTH_PATH, payload)
    return payload


def write_retrieval_dependency_health(runtime_state: dict[str, Any]) -> dict[str, Any]:
    dependency_authority = runtime_state.get("dependency_authority")
    if not isinstance(dependency_authority, dict):
        dependency_authority = {}
    package_list = dependency_authority.get("package_list")
    payload = base_surface("retrieval_dependency_health", "PASS")
    payload.update(
        {
            "d01_status": dependency_authority.get("status"),
            "d01_execution_status": dependency_authority.get("execution_status"),
            "build_id": dependency_authority.get("build_id"),
            "target_interpreter_path": dependency_authority.get("target_interpreter_path"),
            "approval_artifact": dependency_authority.get("approval_artifact"),
            "package_count": len(package_list) if isinstance(package_list, list) else None,
            "installed_package_verification": dependency_authority.get("installed_package_verification", {}).get("status")
            if isinstance(dependency_authority.get("installed_package_verification"), dict)
            else None,
            "import_readiness_verification": dependency_authority.get("import_readiness_verification", {}).get("status")
            if isinstance(dependency_authority.get("import_readiness_verification"), dict)
            else None,
            "package_hash_verification": dependency_authority.get("package_hash_verification", {}).get("status")
            if isinstance(dependency_authority.get("package_hash_verification"), dict)
            else None,
            "network_verification": dependency_authority.get("network_verification", {}).get("status")
            if isinstance(dependency_authority.get("network_verification"), dict)
            else None,
            "fallback_verification": dependency_authority.get("fallback_verification", {}).get("status")
            if isinstance(dependency_authority.get("fallback_verification"), dict)
            else None,
        }
    )
    atomic_write_json(RETRIEVAL_DEPENDENCY_HEALTH_PATH, payload)
    return payload


def write_retrieval_last_build_status() -> dict[str, Any]:
    lineage = read_build_lineage()
    promotion_result = load_json_object(PROMOTION_RESULT_PATH, ".repo_index/promotion_result.json")
    payload = base_surface("retrieval_last_build_status", "PASS")
    payload.update(
        {
            "active_build_id": lineage["active_build_id"],
            "manifest_state": lineage["manifest_state"],
            "corpus_size": lineage["corpus_size"],
            "promotion_status": promotion_result.get("status"),
            "promotion_occurred": promotion_result.get("promotion_occurred"),
            "build_mode": promotion_result.get("build_mode"),
            "completed_at_utc": promotion_result.get("completed_at_utc"),
        }
    )
    atomic_write_json(RETRIEVAL_LAST_BUILD_STATUS_PATH, payload)
    return payload


def write_retrieval_health_surfaces(runtime_state: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        "runtime": write_retrieval_runtime_health(runtime_state),
        "artifact": write_retrieval_artifact_health(runtime_state),
        "model": write_retrieval_model_health(runtime_state),
        "dependency": write_retrieval_dependency_health(runtime_state),
        "last_build": write_retrieval_last_build_status(),
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
    "load_json_object",
    "load_optional_json_object",
    "normalize_repo_relative_path",
    "read_build_lineage",
    "read_last_query_trace",
    "read_recent_query_traces",
    "repo_relative_path",
    "resolve_repo_relative_path",
    "require_observability_write_path",
    "utc_now_iso",
    "write_retrieval_artifact_health",
    "write_retrieval_dependency_health",
    "write_retrieval_health_surfaces",
    "write_retrieval_last_build_status",
    "write_retrieval_model_health",
    "write_retrieval_runtime_health",
]
