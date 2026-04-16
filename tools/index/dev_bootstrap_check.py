from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import sys
from typing import Callable


ROOT = Path(__file__).resolve().parents[2]
INDEX_TOOL_ROOT = Path(__file__).resolve().parent
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"
CANONICAL_INTERPRETER_RELATIVE = ".repo_index/.search_venv/Scripts/python.exe"
MODEL_AUTHORITY_RELATIVE = ".repo_index/models/model_authority.json"
ACTIVE_MANIFEST_RELATIVE = ".repo_index/index_manifest.json"
CHUNK_MANIFEST_RELATIVE = ".repo_index/chunk_manifest.jsonl"
CHROMA_DB_RELATIVE = ".repo_index/chroma_db"
LEXICAL_INDEX_RELATIVE = ".repo_index/lexical_index"
D01_BUILD_ID_ENV = "AVELI_ENVIRONMENT_DEPENDENCY_BUILD_ID"
D01_RESULT_ARTIFACT_ENV = "AVELI_ENVIRONMENT_DEPENDENCY_RESULT_ARTIFACT"


class BootstrapBlocked(RuntimeError):
    def __init__(self, layer: str, missing_or_invalid: str, required_path: str, next_action: str) -> None:
        super().__init__(missing_or_invalid)
        self.layer = layer
        self.missing_or_invalid = missing_or_invalid
        self.required_path = required_path
        self.next_action = next_action


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")


def blocked(layer: str, missing_or_invalid: str, required_path: str, next_action: str) -> dict:
    return {
        "status": "BLOCKED",
        "layer": layer,
        "missing_or_invalid": missing_or_invalid,
        "required_path": required_path,
        "next_action": next_action,
    }


def ready() -> dict:
    return {"status": "READY"}


def ensure_canonical_interpreter() -> None:
    if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
        raise BootstrapBlocked(
            "canonical_interpreter",
            f"non-canonical interpreter: {Path(sys.executable).resolve()}",
            CANONICAL_INTERPRETER_RELATIVE,
            f"Run this check with {CANONICAL_INTERPRETER_RELATIVE}.",
        )


def quiet_call(callable_: Callable[[], object]) -> object:
    stdout_buffer = io.StringIO()
    stderr_buffer = io.StringIO()
    with contextlib.redirect_stdout(stdout_buffer), contextlib.redirect_stderr(stderr_buffer):
        return callable_()


def d01_required_path() -> str:
    result_artifact = os.environ.get(D01_RESULT_ARTIFACT_ENV, "").strip()
    build_id = os.environ.get(D01_BUILD_ID_ENV, "").strip()
    if result_artifact:
        return result_artifact
    if build_id:
        return (
            "actual_truth/DETERMINED_TASKS/retrieval_index_environment_dependencies/"
            f"D01_environment_dependency_result_{build_id}.json"
        )
    return f"{D01_BUILD_ID_ENV} or {D01_RESULT_ARTIFACT_ENV}"


def step_1_d01_dependency_authority() -> None:
    from dependency_authority import DependencyAuthorityError, require_valid_d01_pass_from_environment

    try:
        quiet_call(lambda: require_valid_d01_pass_from_environment(ROOT))
    except DependencyAuthorityError as exc:
        raise BootstrapBlocked(
            "D01 dependency authority",
            str(exc),
            d01_required_path(),
            "Produce a valid D01 PASS result and select it explicitly.",
        ) from exc


def step_2_model_authority() -> None:
    from model_authority import (
        ModelAuthorityError,
        ROLE_TO_MANIFEST_FIELD,
        assert_no_implicit_cache_environment,
        load_model_authority,
        require_string,
        resolve_model_binding,
        validate_model_authority_header,
    )

    try:
        def validate_local_model_authority() -> None:
            assert_no_implicit_cache_environment()
            authority_path, authority = load_model_authority(ROOT)
            models = validate_model_authority_header(ROOT, authority)
            manifest_stub = {}
            for role, manifest_field in ROLE_TO_MANIFEST_FIELD.items():
                binding = models[role]
                if not isinstance(binding, dict):
                    raise ModelAuthorityError(f"FEL: model_authority.models.{role} maste vara ett JSON-objekt")
                manifest_stub[manifest_field] = require_string(
                    binding,
                    "model_id",
                    f"model_authority.models.{role}",
                )
            for role in ROLE_TO_MANIFEST_FIELD:
                resolve_model_binding(ROOT, manifest_stub, role, authority_path, models[role])

        quiet_call(validate_local_model_authority)
    except ModelAuthorityError as exc:
        raise BootstrapBlocked(
            "model authority",
            str(exc),
            MODEL_AUTHORITY_RELATIVE,
            f"Materialize valid canonical model authority at {MODEL_AUTHORITY_RELATIVE}.",
        ) from exc


def step_3_active_manifest():
    import search_code

    try:
        manifest = quiet_call(search_code.load_index_manifest)
    except SystemExit as exc:
        raise BootstrapBlocked(
            "active manifest",
            str(exc),
            ACTIVE_MANIFEST_RELATIVE,
            f"Promote a verified active manifest to {ACTIVE_MANIFEST_RELATIVE}.",
        ) from exc
    if manifest.get("manifest_state") != "ACTIVE_VERIFIED":
        raise BootstrapBlocked(
            "active manifest",
            "manifest_state is not ACTIVE_VERIFIED",
            ACTIVE_MANIFEST_RELATIVE,
            f"Promote a verified active manifest to {ACTIVE_MANIFEST_RELATIVE}.",
        )
    return manifest


def step_4_index_artifact_integrity() -> None:
    import search_code

    try:
        def validate_artifacts() -> None:
            collection = search_code.open_vector_collection()
            search_code.validate_runtime_artifact_integrity(collection)

        quiet_call(validate_artifacts)
    except SystemExit as exc:
        raise BootstrapBlocked(
            "index artifact integrity",
            str(exc),
            f"{ACTIVE_MANIFEST_RELATIVE}; {CHUNK_MANIFEST_RELATIVE}; {CHROMA_DB_RELATIVE}; {LEXICAL_INDEX_RELATIVE}",
            "Promote a complete verified active index artifact set.",
        ) from exc


def step_5_retrieval_runtime_readiness() -> None:
    import search_code

    try:
        state = quiet_call(search_code.load_runtime_state)
    except SystemExit as exc:
        raise BootstrapBlocked(
            "retrieval runtime readiness",
            str(exc),
            ".repo_index/",
            "Restore all validated dependency, model, manifest, and index authorities.",
        ) from exc
    warm_models = state.get("warm_models") if isinstance(state, dict) else None
    if not isinstance(warm_models, dict) or not warm_models.get("embedding") or not warm_models.get("rerank"):
        raise BootstrapBlocked(
            "retrieval runtime readiness",
            "warm retrieval runtime did not expose embedding and rerank models",
            MODEL_AUTHORITY_RELATIVE,
            "Restore canonical local model authority and rerun the bootstrap check.",
        )


def run_check() -> dict:
    ensure_canonical_interpreter()
    if str(INDEX_TOOL_ROOT) not in sys.path:
        sys.path.insert(0, str(INDEX_TOOL_ROOT))
    step_1_d01_dependency_authority()
    step_2_model_authority()
    step_3_active_manifest()
    step_4_index_artifact_integrity()
    step_5_retrieval_runtime_readiness()
    return ready()


def main() -> int:
    try:
        emit(run_check())
        return 0
    except BootstrapBlocked as exc:
        emit(blocked(exc.layer, exc.missing_or_invalid, exc.required_path, exc.next_action))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
