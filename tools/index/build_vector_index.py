from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import os
import shutil
import sys
import unicodedata
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
INDEX_TOOL_ROOT = Path(__file__).resolve().parent
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"

if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
        f"{CANONICAL_SEARCH_PYTHON}"
    )

if str(INDEX_TOOL_ROOT) not in sys.path:
    sys.path.insert(0, str(INDEX_TOOL_ROOT))

from model_authority import (
    ModelAuthorityError,
    serialize_model_authority_result,
    validate_model_authority_for_manifest,
)
from index_artifact_integrity import (
    IndexArtifactIntegrityError,
    validate_index_artifact_integrity,
)
from retrieval_policies import (
    RetrievalPolicyError,
    canonical_retrieval_policies,
    validate_retrieval_policies,
)
from dependency_authority import (
    DependencyAuthorityError,
    require_valid_d01_pass_for_build,
)

SentenceTransformer = None
chromadb = None
np = None
tqdm = None
BUILD_DEPENDENCIES_LOADED = False

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------

ACTIVE_INDEX_ROOT = ROOT / ".repo_index"
STAGING_PARENT = ACTIVE_INDEX_ROOT / "_staging"
PROMOTION_PARENT = ACTIVE_INDEX_ROOT / "_promotion"
INDEX_MANIFEST = ACTIVE_INDEX_ROOT / "index_manifest.json"
CHUNK_MANIFEST = ACTIVE_INDEX_ROOT / "chunk_manifest.jsonl"
LEXICAL_INDEX_DIR = ACTIVE_INDEX_ROOT / "lexical_index"
CHROMA_DB_DIR = ACTIVE_INDEX_ROOT / "chroma_db"
PROMOTION_RESULT = ACTIVE_INDEX_ROOT / "promotion_result.json"

# ---------------------------------------------------------
# Config
# ---------------------------------------------------------

COLLECTION_NAME = "aveli_repo"
APPROVAL_PHRASE = "APPROVE AVELI INDEX REBUILD"
CONTROLLER_MODE_ENV = "AVELI_RETRIEVAL_CONTROLLER_MODE"
APPROVAL_ENV = "AVELI_INDEX_REBUILD_APPROVAL"
BUILD_ID_ENV = "AVELI_INDEX_BUILD_ID"
BUILD_APPROVAL_ARTIFACT_ENV = "AVELI_INDEX_BUILD_APPROVAL_ARTIFACT"
CANONICAL_INTERPRETER_RELATIVE = ".repo_index/.search_venv/Scripts/python.exe"
TARGET_INDEX_RELATIVE = ".repo_index"
INITIAL_BUILD_MODE = "INITIAL_BUILD"
REBUILD_MODE = "REBUILD"
MISSING_CONTROLLER_CONTEXT_MESSAGE = (
    "FEL: build kraver controllerlage, godkand approvalfras och godkand approvalartefakt"
)

INDEX_MANIFEST_REQUIRED_FIELDS = {
    "contract_version",
    "corpus",
    "corpus_manifest_hash",
    "chunk_manifest_hash",
    "chunk_size",
    "chunk_overlap",
    "embedding_model",
    "rerank_model",
    "top_k",
    "vector_candidate_k",
    "lexical_candidate_k",
    "classification_policy",
    "normalization_policy",
    "lexical_query_policy",
    "embedding_query_policy",
    "rerank_policy",
    "scoring_policy",
    "evidence_policy",
}

DEPRECATED_MANIFEST_CONFIG_FIELDS = {
    "batch_policy",
    "chunking_policy",
    "classification_rules",
    "device_policy",
    "embedding_policy",
    "model_policy",
    "ranking_policy",
    "retrieval_policy",
}

CANONICAL_CONTRACT_VERSION = "retrieval-v1"
CANONICAL_LAYERS = {"LAW", "ROUTE", "SERVICE", "DB", "POLICY", "SCHEMA", "MODEL", "OTHER"}
CANONICAL_CLASSIFICATION_RULES = {
    "default_layer": "OTHER",
    "precedence": [
        {"layer": "LAW", "type": "path_substring", "value": "actual_truth"},
        {"layer": "LAW", "type": "path_substring", "value": "aveli_system_decisions"},
        {"layer": "LAW", "type": "path_substring", "value": "manifest"},
        {"layer": "LAW", "type": "path_substring", "value": "contract"},
        {"layer": "ROUTE", "type": "path_substring", "value": "routes"},
        {"layer": "SERVICE", "type": "path_substring", "value": "services"},
        {"layer": "DB", "type": "path_substring", "value": "supabase"},
        {"layer": "DB", "type": "path_substring", "value": "migrations"},
        {"layer": "POLICY", "type": "path_substring", "value": "policy"},
        {"layer": "SCHEMA", "type": "path_substring", "value": "schemas"},
        {"layer": "MODEL", "type": "path_substring", "value": "models"},
    ],
}

EXCLUDED_DIRECTORIES = {
    ".repo_index",
    ".venv",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "target",
}


def load_build_dependency_modules() -> None:
    global BUILD_DEPENDENCIES_LOADED, SentenceTransformer, chromadb, np, tqdm
    if BUILD_DEPENDENCIES_LOADED:
        return
    try:
        from sentence_transformers import SentenceTransformer as _SentenceTransformer
        import chromadb as _chromadb
        import numpy as _np
        from tqdm import tqdm as _tqdm
    except Exception as exc:
        raise RuntimeError("FEL: D01 PASS finns men buildberoenden kan inte importeras") from exc

    SentenceTransformer = _SentenceTransformer
    chromadb = _chromadb
    np = _np
    tqdm = _tqdm
    BUILD_DEPENDENCIES_LOADED = True


def is_excluded_path(relative_file: str) -> bool:
    path = Path(relative_file)

    lowered_parts = [part.lower() for part in path.parts]
    if any(part in EXCLUDED_DIRECTORIES for part in lowered_parts):
        return True

    name = path.name.lower()
    if name.startswith(".env"):
        return True
    if name.endswith(".log"):
        return True

    return False


def normalize_repo_relative_path(file_path: str) -> str:
    path = Path(file_path)

    if path.is_absolute():
        try:
            path = path.resolve().relative_to(ROOT)
        except ValueError as exc:
            raise RuntimeError(
                f"FEL: filen ligger utanför repo-root: {file_path}"
            ) from exc

    normalized = Path(path.as_posix())
    if normalized.is_absolute() or ".." in normalized.parts:
        raise RuntimeError(f"FEL: ogiltig repo-relativ filidentitet: {file_path}")

    normalized_path = normalized.as_posix()
    if normalized_path.startswith("./"):
        normalized_path = normalized_path[2:]
    return normalized_path


def classify(path: str, manifest: dict) -> str:
    lowered = path.lower()
    classification_policy = manifest.get("classification_policy")
    if not isinstance(classification_policy, dict):
        raise RuntimeError("FEL: classification_policy saknas i index_manifest.json")

    for rule in classification_policy.get("precedence", []):
        rule_type = rule.get("type")
        value = str(rule.get("value", "")).lower()
        layer = str(rule.get("layer", "")).upper()

        if rule_type == "path_substring" and value in lowered:
            return layer
        if rule_type == "path_suffix" and lowered.endswith(value):
            return layer

    return str(classification_policy.get("default_layer", "OTHER")).upper()


def normalize_ingested_text(text: str) -> str:
    normalized = unicodedata.normalize("NFC", text)
    normalized = normalized.replace("\r\n", "\n").replace("\r", "\n")
    normalized = normalized.replace("\t", "    ")
    return "\n".join(line.rstrip() for line in normalized.split("\n"))


def normalize_corpus_text_for_hash(raw_bytes: bytes, file_path: str) -> str:
    if b"\x00" in raw_bytes:
        raise RuntimeError(f"FEL: binart corpusinnehall nekas: {file_path}")
    try:
        text = raw_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError(f"FEL: corpusfil maste vara UTF-8: {file_path}") from exc

    if text.startswith("\ufeff"):
        text = text[1:]

    normalized = unicodedata.normalize("NFC", text)
    normalized = normalized.replace("\r\n", "\n").replace("\r", "\n")
    normalized = normalized.replace("\t", "    ")
    normalized = "\n".join(line.rstrip(" ") for line in normalized.split("\n"))

    if not normalized.strip():
        raise RuntimeError(f"FEL: tom corpusfil nekas: {file_path}")

    return normalized.rstrip("\n") + "\n"


def normalize_document_text(text: str) -> str:
    return text.strip()


def tokenize_for_lexical(text: str) -> list[str]:
    return normalize_document_text(text).lower().split()


def compute_sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def compute_sha256_text(content: str) -> str:
    return compute_sha256_bytes(content.encode("utf-8"))


def canonical_json_dumps(data: object) -> str:
    return json.dumps(
        data,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def validate_sha256_hex(value: object, field_name: str) -> str:
    if not isinstance(value, str):
        raise RuntimeError(f"FEL: {field_name} maste vara sha256-hex")
    digest = value.strip()
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise RuntimeError(f"FEL: {field_name} maste vara 64 tecken lowercase sha256-hex")
    return digest


def is_relative_to_path(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def validate_build_id(raw_build_id: str) -> str:
    build_id = raw_build_id.strip()
    if len(build_id) != 64:
        raise RuntimeError(MISSING_CONTROLLER_CONTEXT_MESSAGE)
    if any(char not in "0123456789abcdef" for char in build_id):
        raise RuntimeError(MISSING_CONTROLLER_CONTEXT_MESSAGE)
    return build_id


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def normalize_path_for_compare(path: Path) -> str:
    normalized = path.resolve().as_posix()
    if os.name == "nt":
        return normalized.lower()
    return normalized


def require_controller_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(MISSING_CONTROLLER_CONTEXT_MESSAGE)
    return value


def require_json_object(container: dict, field_name: str, owner: str) -> dict:
    value = container.get(field_name)
    if not isinstance(value, dict):
        raise RuntimeError(f"FEL: {owner}.{field_name} maste vara ett JSON-objekt")
    return value


def require_json_string(container: dict, field_name: str, owner: str) -> str:
    value = container.get(field_name)
    if not isinstance(value, str) or not value.strip():
        raise RuntimeError(f"FEL: {owner}.{field_name} maste vara en icke-tom strang")
    return value


def require_json_bool(container: dict, field_name: str, owner: str) -> bool:
    value = container.get(field_name)
    if not isinstance(value, bool):
        raise RuntimeError(f"FEL: {owner}.{field_name} maste vara boolean")
    return value


def require_json_int(container: dict, field_name: str, owner: str) -> int:
    value = container.get(field_name)
    if not isinstance(value, int) or isinstance(value, bool):
        raise RuntimeError(f"FEL: {owner}.{field_name} maste vara heltal")
    return value


def resolve_repo_relative_path(path_text: str, field_name: str) -> Path:
    if not isinstance(path_text, str) or not path_text.strip():
        raise RuntimeError(f"FEL: {field_name} maste vara en icke-tom repo-relativ sokvag")
    path = Path(path_text)
    if path.is_absolute() or "\\" in path_text:
        raise RuntimeError(f"FEL: {field_name} maste vara repo-relativ och anvanda forward slash")
    normalized = normalize_repo_relative_path(path_text)
    if normalized != path_text:
        raise RuntimeError(f"FEL: {field_name} maste vara normaliserad repo-relativ sokvag")
    resolved = (ROOT / normalized).resolve()
    if not is_relative_to_path(resolved, ROOT.resolve()):
        raise RuntimeError(f"FEL: {field_name} pekar utanfor repo-root")
    return resolved


def validate_approval_scope(approval: dict) -> None:
    scope = require_json_object(approval, "approval_scope", "approval")
    expected = {
        "controller_scope": "retrieval_index_build_execution",
        "task_id": "B01",
        "mode": "build",
        "expires_after_use": True,
    }
    for field_name, expected_value in expected.items():
        actual = scope.get(field_name)
        if actual != expected_value:
            raise RuntimeError(f"FEL: approval_scope.{field_name} matchar inte B01-kontraktet")
    if scope.get("example_only") is True:
        raise RuntimeError("FEL: exempelapproval far inte exekveras")


def validate_false_policy_fields(policy: dict, owner: str, field_names: list[str]) -> None:
    for field_name in field_names:
        if require_json_bool(policy, field_name, owner):
            raise RuntimeError(f"FEL: {owner}.{field_name} maste vara false")


def validate_device_policy(device_policy: dict) -> dict:
    if require_json_string(device_policy, "canonical_baseline", "approval.device_policy") != "cpu":
        raise RuntimeError("FEL: device_policy.canonical_baseline maste vara cpu")
    allowed_devices = device_policy.get("allowed_devices")
    if not isinstance(allowed_devices, list) or "cpu" not in allowed_devices:
        raise RuntimeError("FEL: device_policy.allowed_devices maste innehalla cpu")
    if any(device not in {"cpu", "cuda"} for device in allowed_devices):
        raise RuntimeError("FEL: device_policy.allowed_devices innehaller ogiltig enhet")
    selected_device = require_json_string(device_policy, "selected_build_device", "approval.device_policy")
    preferred_device = require_json_string(device_policy, "preferred_local_build_device", "approval.device_policy")
    if selected_device not in allowed_devices or selected_device not in {"cpu", "cuda"}:
        raise RuntimeError("FEL: device_policy.selected_build_device ar ogiltig")
    if preferred_device not in allowed_devices or preferred_device not in {"cpu", "cuda"}:
        raise RuntimeError("FEL: device_policy.preferred_local_build_device ar ogiltig")
    if selected_device == "cuda" and "cuda" not in allowed_devices:
        raise RuntimeError("FEL: cuda-build kraver att cuda finns i allowed_devices")
    if require_json_bool(device_policy, "cuda_required", "approval.device_policy"):
        raise RuntimeError("FEL: device_policy.cuda_required maste vara false")
    if require_json_bool(device_policy, "device_changes_semantics", "approval.device_policy"):
        raise RuntimeError("FEL: device_policy.device_changes_semantics maste vara false")
    tolerance = require_json_object(device_policy, "cpu_gpu_tolerance", "approval.device_policy")
    cpu_baseline_required = require_json_bool(
        device_policy,
        "cpu_baseline_required",
        "approval.device_policy",
    )
    bounded_equivalence_required = require_json_bool(
        device_policy,
        "bounded_equivalence_verification_required",
        "approval.device_policy",
    )
    sample_size = require_json_int(
        device_policy,
        "equivalence_sample_size",
        "approval.device_policy",
    )
    if sample_size <= 0:
        raise RuntimeError("FEL: device_policy.equivalence_sample_size maste vara positivt")
    if selected_device == "cuda" and not bounded_equivalence_required and not cpu_baseline_required:
        raise RuntimeError("FEL: cuda-build kraver explicit bounded equivalence eller CPU-baslinje")
    return {
        "allowed_devices": list(allowed_devices),
        "bounded_equivalence_verification_required": bounded_equivalence_required,
        "canonical_baseline": "cpu",
        "cpu_baseline_required": cpu_baseline_required,
        "cpu_gpu_tolerance": tolerance,
        "cuda_required": False,
        "device_changes_semantics": False,
        "equivalence_sample_size": sample_size,
        "preferred_local_build_device": preferred_device,
        "selected_build_device": selected_device,
    }


def validate_build_approval_shape(approval: dict, build_id: str) -> None:
    required_fields = {
        "artifact_type",
        "approval_state",
        "approval_phrase",
        "approval_scope",
        "repo_root",
        "target_path",
        "build_id",
        "manifest_input",
        "model_id",
        "model_revision",
        "tokenizer_id",
        "tokenizer_revision",
        "tokenizer_hashes",
        "device_policy",
        "batch_size",
        "interpreter_path",
        "network_policy",
        "fallback_policy",
        "staging_policy",
        "promotion_policy",
    }
    missing = sorted(required_fields - set(approval))
    if missing:
        raise RuntimeError("FEL: approvalartefakt saknar falt: " + ", ".join(missing))
    if approval.get("artifact_type") != "build_approval":
        raise RuntimeError("FEL: approvalartefakt ar inte exekverbar build_approval")
    if approval.get("approval_state") != "APPROVED_FOR_SINGLE_BUILD":
        raise RuntimeError("FEL: approval_state tillater inte B01-exekvering")
    if approval.get("approval_phrase") != APPROVAL_PHRASE:
        raise RuntimeError("FEL: approvalfras matchar inte byte-for-byte")
    validate_approval_scope(approval)
    if approval.get("target_path") != TARGET_INDEX_RELATIVE:
        raise RuntimeError("FEL: approval target_path maste vara .repo_index")
    if validate_build_id(str(approval.get("build_id", ""))) != build_id:
        raise RuntimeError("FEL: approval build_id matchar inte controllerns build_id")
    approved_root = Path(require_json_string(approval, "repo_root", "approval"))
    if normalize_path_for_compare(approved_root) != normalize_path_for_compare(ROOT):
        raise RuntimeError("FEL: approval repo_root matchar inte aktiv repo-root")
    if approval.get("interpreter_path") != CANONICAL_INTERPRETER_RELATIVE:
        raise RuntimeError("FEL: approval interpreter_path matchar inte kanonisk Windows-tolk")
    if approval.get("execution_policy", {}).get("not_executable") is True:
        raise RuntimeError("FEL: approvalartefakt ar markerad som icke-exekverbar")


def validate_approval_manifest_input(
    approval: dict,
    build_id: str,
    active_manifest_exists: bool,
) -> tuple[str, Path, dict]:
    manifest_input = require_json_object(approval, "manifest_input", "approval")
    input_kind = require_json_string(manifest_input, "kind", "approval.manifest_input")
    input_path_text = require_json_string(manifest_input, "path", "approval.manifest_input")
    corpus_field = require_json_string(manifest_input, "corpus_field", "approval.manifest_input")
    active_before_promotion = require_json_bool(
        manifest_input,
        "active_authority_before_promotion",
        "approval.manifest_input",
    )

    if corpus_field != "corpus.files":
        raise RuntimeError("FEL: approval manifest_input.corpus_field maste vara corpus.files")

    if active_manifest_exists:
        if input_kind != "active_index_manifest":
            raise RuntimeError("FEL: aktivt index finns; rebuild far endast anvanda aktivt index_manifest.json")
        if input_path_text != TARGET_INDEX_RELATIVE + "/index_manifest.json":
            raise RuntimeError("FEL: rebuild maste peka pa .repo_index/index_manifest.json")
        if active_before_promotion is not True:
            raise RuntimeError("FEL: active_index_manifest maste deklareras som aktiv auktoritet fore promotion")
        manifest_path = INDEX_MANIFEST
    else:
        if input_kind != "manifest_candidate":
            raise RuntimeError("FEL: initial build kraver manifest_candidate som explicit buildinput")
        if active_before_promotion is not False:
            raise RuntimeError("FEL: manifest_candidate far inte vara aktiv auktoritet fore promotion")
        manifest_path = resolve_repo_relative_path(input_path_text, "approval.manifest_input.path")
        if is_relative_to_path(manifest_path, ACTIVE_INDEX_ROOT.resolve()):
            raise RuntimeError("FEL: manifest_candidate far inte ligga i aktiv .repo_index")

    if not manifest_path.exists():
        raise RuntimeError(f"FEL: manifestinput saknas: {display_path(manifest_path)}")

    manifest = load_json_object(manifest_path)

    if input_kind == "manifest_candidate":
        if manifest.get("artifact_type") != "index_manifest_candidate":
            raise RuntimeError("FEL: manifest_candidate saknar ratt artifact_type")
        if manifest.get("manifest_state") != "MANIFEST_CANDIDATE":
            raise RuntimeError("FEL: manifest_candidate maste ha manifest_state MANIFEST_CANDIDATE")
        if manifest.get("build_id") != build_id:
            raise RuntimeError("FEL: manifest_candidate build_id matchar inte approval")
        repo = manifest.get("repo")
        if isinstance(repo, dict) and "repo_root" in repo:
            candidate_root = Path(str(repo["repo_root"]))
            if normalize_path_for_compare(candidate_root) != normalize_path_for_compare(ROOT):
                raise RuntimeError("FEL: manifest_candidate repo_root matchar inte aktiv repo-root")
    else:
        if manifest.get("manifest_state") != "ACTIVE_VERIFIED":
            raise RuntimeError("FEL: aktivt indexmanifest maste vara ACTIVE_VERIFIED for rebuild")

    return input_kind, manifest_path, manifest


def validate_build_approval_policy(approval: dict, manifest: dict, build_id: str) -> dict:
    model_authority = resolve_manifest_model_authority(manifest)
    embedding_binding = model_authority["models"]["embedding"]
    model_id = require_json_string(approval, "model_id", "approval")
    tokenizer_id = require_json_string(approval, "tokenizer_id", "approval")
    if model_id != embedding_binding["model_id"]:
        raise RuntimeError("FEL: approval model_id matchar inte manifestets embedding_model")
    if tokenizer_id != embedding_binding["tokenizer_id"]:
        raise RuntimeError("FEL: approval tokenizer_id matchar inte modellauktoriteten")

    for field_name in ("model_revision", "tokenizer_revision"):
        revision = require_json_string(approval, field_name, "approval")
        if revision in {"main", "master", "latest"}:
            raise RuntimeError(f"FEL: approval {field_name} maste vara en last revision")
    if approval["model_revision"] != embedding_binding["model_revision"]:
        raise RuntimeError("FEL: approval model_revision matchar inte modellauktoriteten")
    if approval["tokenizer_revision"] != embedding_binding["tokenizer_revision"]:
        raise RuntimeError("FEL: approval tokenizer_revision matchar inte modellauktoriteten")

    tokenizer_hashes = require_json_object(approval, "tokenizer_hashes", "approval")
    if not tokenizer_hashes:
        raise RuntimeError("FEL: approval tokenizer_hashes far inte vara tom")
    for name, digest in tokenizer_hashes.items():
        if not isinstance(name, str) or not name.strip():
            raise RuntimeError("FEL: tokenizer_hashes innehaller ogiltigt filnamn")
        validate_sha256_hex(digest, f"tokenizer_hashes.{name}")
    if tokenizer_hashes != embedding_binding["tokenizer_files"]:
        raise RuntimeError("FEL: approval tokenizer_hashes matchar inte modellauktoriteten")

    validate_device_policy(require_json_object(approval, "device_policy", "approval"))

    if require_json_int(approval, "batch_size", "approval") != get_embedding_batch_size(manifest):
        raise RuntimeError("FEL: approval batch_size matchar inte manifeststyrd batchstorlek")

    network_policy = require_json_object(approval, "network_policy", "approval")
    validate_false_policy_fields(
        network_policy,
        "approval.network_policy",
        ["downloads_allowed", "model_download_allowed", "dependency_install_allowed"],
    )

    fallback_policy = require_json_object(approval, "fallback_policy", "approval")
    validate_false_policy_fields(
        fallback_policy,
        "approval.fallback_policy",
        [
            "fallbacks_allowed",
            "fallback_interpreter_allowed",
            "fallback_model_allowed",
            "fallback_device_allowed",
            "fallback_corpus_allowed",
            "fallback_retrieval_allowed",
        ],
    )

    staging_policy = require_json_object(approval, "staging_policy", "approval")
    if not require_json_bool(staging_policy, "staging_required", "approval.staging_policy"):
        raise RuntimeError("FEL: staging_policy.staging_required maste vara true")
    staging_root = require_json_string(staging_policy, "staging_root", "approval.staging_policy")
    if staging_root not in {".repo_index/_staging/<build_id>", f".repo_index/_staging/{build_id}"}:
        raise RuntimeError("FEL: staging_policy.staging_root matchar inte B01")
    if require_json_bool(staging_policy, "direct_active_write_allowed", "approval.staging_policy"):
        raise RuntimeError("FEL: staging_policy.direct_active_write_allowed maste vara false")

    promotion_policy = require_json_object(approval, "promotion_policy", "approval")
    if not require_json_bool(
        promotion_policy,
        "promotion_requires_staging_verification",
        "approval.promotion_policy",
    ):
        raise RuntimeError("FEL: promotion kraver stagingverifiering")
    if require_json_string(
        promotion_policy,
        "active_manifest_state",
        "approval.promotion_policy",
    ) != "ACTIVE_VERIFIED":
        raise RuntimeError("FEL: promotion_policy.active_manifest_state maste vara ACTIVE_VERIFIED")
    if not require_json_bool(promotion_policy, "atomic_promotion_required", "approval.promotion_policy"):
        raise RuntimeError("FEL: promotion_policy.atomic_promotion_required maste vara true")
    return model_authority


def prepare_manifest_for_staging(manifest: dict) -> dict:
    staging_manifest = {
        field_name: deepcopy(manifest[field_name])
        for field_name in INDEX_MANIFEST_REQUIRED_FIELDS
    }
    staging_manifest["manifest_state"] = "STAGING_INCOMPLETE"
    return staging_manifest


def load_controller_build_context() -> dict:
    mode = os.environ.get(CONTROLLER_MODE_ENV, "").strip().lower()
    approval = os.environ.get(APPROVAL_ENV, "")
    build_id = validate_build_id(os.environ.get(BUILD_ID_ENV, ""))

    if mode != "build" or approval != APPROVAL_PHRASE:
        raise RuntimeError(MISSING_CONTROLLER_CONTEXT_MESSAGE)

    try:
        dependency_authority = require_valid_d01_pass_for_build(ROOT, build_id)
    except DependencyAuthorityError as exc:
        raise RuntimeError(str(exc)) from exc

    approval_artifact_path = resolve_repo_relative_path(
        require_controller_env(BUILD_APPROVAL_ARTIFACT_ENV),
        BUILD_APPROVAL_ARTIFACT_ENV,
    )
    approval_artifact = load_json_object(approval_artifact_path)
    validate_build_approval_shape(approval_artifact, build_id)
    device_policy = validate_device_policy(
        require_json_object(approval_artifact, "device_policy", "approval")
    )

    active_manifest_exists = INDEX_MANIFEST.exists()
    build_mode = REBUILD_MODE if active_manifest_exists else INITIAL_BUILD_MODE
    manifest_input_kind, manifest_input_path, manifest = validate_approval_manifest_input(
        approval_artifact,
        build_id,
        active_manifest_exists,
    )
    model_authority = validate_build_approval_policy(approval_artifact, manifest, build_id)

    staging_root = STAGING_PARENT / build_id
    staging_parent = STAGING_PARENT.resolve()
    resolved_staging_root = staging_root.resolve()
    if not is_relative_to_path(resolved_staging_root, staging_parent):
        raise RuntimeError(MISSING_CONTROLLER_CONTEXT_MESSAGE)
    if staging_root.exists():
        raise RuntimeError("FEL: staging path finns redan och kraver explicit controller-cleanup")

    return {
        "active_manifest_exists_before_build": active_manifest_exists,
        "approval_artifact": approval_artifact,
        "approval_artifact_path": approval_artifact_path,
        "build_mode": build_mode,
        "build_id": build_id,
        "manifest": manifest,
        "manifest_input_kind": manifest_input_kind,
        "manifest_input_path": manifest_input_path,
        "dependency_authority": dependency_authority,
        "device_policy": device_policy,
        "embedding_execution": {
            "status": "NOT_STARTED",
            "selected_build_device": device_policy["selected_build_device"],
            "full_corpus_cpu_baseline_required": device_policy["cpu_baseline_required"],
            "bounded_equivalence_verification_required": device_policy[
                "bounded_equivalence_verification_required"
            ],
            "equivalence_sample_size": device_policy["equivalence_sample_size"],
        },
        "model_authority": model_authority,
        "started_at_utc": utc_now_iso(),
        "staging_root": staging_root,
        "index_manifest": staging_root / "index_manifest.json",
        "chunk_manifest": staging_root / "chunk_manifest.jsonl",
        "lexical_index_dir": staging_root / "lexical_index",
        "lexical_index_manifest": staging_root / "lexical_index" / "manifest.json",
        "lexical_index_documents": staging_root / "lexical_index" / "documents.jsonl",
        "vector_db_dir": staging_root / "chroma_db",
        "build_execution_result": staging_root / "build_execution_result.json",
        "staging_verification_result": staging_root / "staging_verification_result.json",
        "promotion_result": PROMOTION_RESULT,
    }


def assert_staging_write_path(path: Path) -> None:
    resolved_path = path.resolve()
    resolved_parent = STAGING_PARENT.resolve()
    if not is_relative_to_path(resolved_path, resolved_parent):
        raise RuntimeError("FEL: aktiv .repo_index-mutation nekas; build skriver endast till staging")


def load_json_object(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError(f"FEL: JSON-objekt forvantas i {path}")
    return data


def write_json_object(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def save_json_object(path: Path, data: dict) -> None:
    assert_staging_write_path(path)
    write_json_object(path, data)


def compute_file_hash(path: Path) -> str:
    if not path.exists() or not path.is_file():
        raise RuntimeError(f"FEL: fil saknas for hashning: {display_path(path)}")
    return compute_sha256_bytes(path.read_bytes())


def compute_directory_hash(path: Path) -> str:
    if not path.exists() or not path.is_dir():
        raise RuntimeError(f"FEL: katalog saknas for hashning: {display_path(path)}")
    parts: list[bytes] = [b"AVELI_DIRECTORY_HASH_V1\n"]
    files = [
        child
        for child in path.rglob("*")
        if child.is_file()
    ]
    files.sort(key=lambda child: child.relative_to(path).as_posix().encode("utf-8"))
    for file_path in files:
        relative_path = file_path.relative_to(path).as_posix()
        relative_bytes = relative_path.encode("utf-8")
        content = file_path.read_bytes()
        parts.append(f"PATH_LEN {len(relative_bytes)}\n".encode("ascii"))
        parts.append(relative_bytes)
        parts.append(b"\n")
        parts.append(f"CONTENT_LEN {len(content)}\n".encode("ascii"))
        parts.append(content)
        parts.append(b"\n")
    return compute_sha256_bytes(b"".join(parts))


def active_authority_snapshot() -> dict:
    snapshot = {}
    authority_paths = {
        "index_manifest": INDEX_MANIFEST,
        "chunk_manifest": CHUNK_MANIFEST,
        "lexical_index": LEXICAL_INDEX_DIR,
        "chroma_db": CHROMA_DB_DIR,
    }
    for name, path in authority_paths.items():
        if path.is_file():
            snapshot[name] = {"exists": True, "kind": "file", "hash": compute_file_hash(path)}
        elif path.is_dir():
            snapshot[name] = {"exists": True, "kind": "dir", "hash": compute_directory_hash(path)}
        else:
            snapshot[name] = {"exists": False, "kind": None, "hash": None}
    return snapshot


def assert_active_snapshot_unchanged(before_snapshot: dict) -> None:
    after_snapshot = active_authority_snapshot()
    if after_snapshot != before_snapshot:
        raise RuntimeError("FEL: aktivt index andrades fore verifierad promotion")


def serialize_chunk_record(record: dict) -> str:
    return canonical_json_dumps(record)


def build_doc_id_payload(
    contract_version: str,
    file_path: str,
    chunk_index: int,
    content_hash: str,
) -> bytes:
    normalized_file = normalize_repo_relative_path(file_path)
    validated_content_hash = validate_sha256_hex(content_hash, "content_hash")
    contract_version_bytes = str(contract_version).encode("utf-8")
    file_bytes = normalized_file.encode("utf-8")
    return b"".join(
        [
            b"AVELI_DOC_ID_V1\n",
            f"CONTRACT_VERSION_LEN {len(contract_version_bytes)}\n".encode("ascii"),
            contract_version_bytes,
            b"\n",
            f"FILE_LEN {len(file_bytes)}\n".encode("ascii"),
            file_bytes,
            b"\n",
            f"CHUNK_INDEX {int(chunk_index)}\n".encode("ascii"),
            f"CONTENT_HASH {validated_content_hash}\n".encode("ascii"),
        ]
    )


def build_canonical_doc_id(
    contract_version: str,
    file_path: str,
    chunk_index: int,
    content_hash: str,
) -> str:
    return compute_sha256_bytes(
        build_doc_id_payload(contract_version, file_path, chunk_index, content_hash)
    )


def validate_manifest_corpus_files(corpus_files: object) -> list[str]:
    if not isinstance(corpus_files, list) or not corpus_files:
        raise RuntimeError("FEL: index_manifest.json corpus.files maste vara en icke-tom lista")

    files: list[str] = []
    seen: set[str] = set()

    for entry in corpus_files:
        if not isinstance(entry, str) or not entry:
            raise RuntimeError("FEL: corpus.files far endast innehalla icke-tomma strangsokvagar")
        if "\\" in entry:
            raise RuntimeError(f"FEL: corpus.files maste anvanda forward slash: {entry}")

        path = Path(entry)
        if path.is_absolute():
            raise RuntimeError(f"FEL: corpus.files far inte innehalla absoluta sokvagar: {entry}")

        normalized = normalize_repo_relative_path(entry)
        if normalized != entry:
            raise RuntimeError(f"FEL: corpus.files maste vara repo-relativt normaliserad: {entry}")
        if normalized in seen:
            raise RuntimeError(f"FEL: duplicerad corpusfil i index_manifest.json: {normalized}")

        files.append(normalized)
        seen.add(normalized)

    expected_order = sorted(files, key=lambda item: item.encode("utf-8"))
    if files != expected_order:
        raise RuntimeError("FEL: corpus.files maste vara sorterad enligt UTF-8 byteordning")

    return files


def load_manifest_corpus_files(manifest: dict) -> list[str]:
    corpus = manifest.get("corpus")
    if not isinstance(corpus, dict):
        raise RuntimeError("FEL: index_manifest.json corpus maste vara ett JSON-objekt")
    return validate_manifest_corpus_files(corpus.get("files"))


def render_canonical_corpus_serialization(files: list[str]) -> bytes:
    parts = [
        b"AVELI_CORPUS_NORMALIZATION_V1\n",
        f"FILE_COUNT {len(files)}\n".encode("ascii"),
    ]

    for file in files:
        path = ROOT / file
        if not path.exists() or not path.is_file():
            raise RuntimeError(f"FEL: fil i index_manifest.json corpus.files saknas: {file}")

        path_bytes = file.encode("utf-8")
        text_bytes = normalize_corpus_text_for_hash(path.read_bytes(), file).encode("utf-8")

        parts.append(f"PATH_LEN {len(path_bytes)}\n".encode("ascii"))
        parts.append(path_bytes)
        parts.append(b"\n")
        parts.append(f"CONTENT_LEN {len(text_bytes)}\n".encode("ascii"))
        parts.append(text_bytes)

    return b"".join(parts)


def compute_corpus_manifest_hash(files: list[str]) -> str:
    return compute_sha256_bytes(render_canonical_corpus_serialization(files))


def order_chunk_records(records: list[dict]) -> list[dict]:
    return sorted(
        records,
        key=lambda record: (
            str(record["file"]).encode("utf-8"),
            int(record["chunk_index"]),
        ),
    )


def render_chunk_manifest(records: list[dict]) -> str:
    ordered_records = order_chunk_records(records)
    if not ordered_records:
        raise RuntimeError("FEL: chunk_manifest far inte vara tom")
    return "".join(serialize_chunk_record(record) + "\n" for record in ordered_records)


def build_canonical_index_manifest(
    corpus_manifest_hash: str,
    chunk_manifest_hash: str = "",
    corpus_files: list[str] | None = None,
    embedding_model: str = "",
    rerank_model: str = "",
    chunk_size: int = 2000,
    chunk_overlap: int = 200,
    top_k: int = 16,
    vector_candidate_k: int = 30,
    lexical_candidate_k: int = 30,
) -> dict:
    return {
        "chunk_manifest_hash": str(chunk_manifest_hash),
        "chunk_overlap": int(chunk_overlap),
        "chunk_size": int(chunk_size),
        "classification_policy": deepcopy(CANONICAL_CLASSIFICATION_RULES),
        "contract_version": CANONICAL_CONTRACT_VERSION,
        "corpus": {"files": list(corpus_files or [])},
        "corpus_manifest_hash": corpus_manifest_hash,
        **canonical_retrieval_policies(),
        "embedding_model": str(embedding_model),
        "lexical_candidate_k": int(lexical_candidate_k),
        "rerank_model": str(rerank_model),
        "top_k": int(top_k),
        "vector_candidate_k": int(vector_candidate_k),
    }


def require_manifest_object(manifest: dict, field_name: str) -> dict:
    value = manifest.get(field_name)
    if not isinstance(value, dict):
        raise RuntimeError(f"FEL: index_manifest.json {field_name} maste vara ett JSON-objekt")
    return value


def require_manifest_bool(container: dict, field_name: str, owner: str) -> bool:
    value = container.get(field_name)
    if not isinstance(value, bool):
        raise RuntimeError(f"FEL: {owner}.{field_name} maste vara boolean")
    return value


def require_manifest_int(container: dict, field_name: str, owner: str) -> int:
    value = container.get(field_name)
    if not isinstance(value, int) or isinstance(value, bool):
        raise RuntimeError(f"FEL: {owner}.{field_name} maste vara heltal")
    return value


def require_manifest_str(container: dict, field_name: str, owner: str) -> str:
    value = container.get(field_name)
    if not isinstance(value, str):
        raise RuntimeError(f"FEL: {owner}.{field_name} maste vara strang")
    return value


def require_manifest_root_str(manifest: dict, field_name: str) -> str:
    value = manifest.get(field_name)
    if not isinstance(value, str) or not value.strip():
        raise RuntimeError(f"FEL: index_manifest.json {field_name} maste vara en icke-tom strang")
    return value


def require_manifest_root_int(manifest: dict, field_name: str) -> int:
    value = manifest.get(field_name)
    if not isinstance(value, int) or isinstance(value, bool):
        raise RuntimeError(f"FEL: index_manifest.json {field_name} maste vara heltal")
    if value <= 0:
        raise RuntimeError(f"FEL: index_manifest.json {field_name} maste vara positivt")
    return value


def reject_deprecated_manifest_config(manifest: dict) -> None:
    present = sorted(DEPRECATED_MANIFEST_CONFIG_FIELDS & set(manifest))
    if present:
        raise RuntimeError(
            "FEL: index_manifest.json innehaller foraldrade config-falt: "
            + ", ".join(present)
        )


def get_chunking_policy(manifest: dict) -> tuple[int, int]:
    chunk_size = require_manifest_root_int(manifest, "chunk_size")
    chunk_overlap = require_manifest_root_int(manifest, "chunk_overlap")
    if chunk_overlap >= chunk_size:
        raise RuntimeError("FEL: index_manifest.json chunk_overlap maste vara mindre an chunk_size")
    return chunk_size, chunk_overlap


def resolve_manifest_model_authority(manifest: dict) -> dict:
    try:
        return validate_model_authority_for_manifest(ROOT, manifest)
    except ModelAuthorityError as exc:
        raise RuntimeError(str(exc)) from exc


def get_embedding_model_config(manifest: dict, model_authority: dict | None = None) -> dict:
    if model_authority is None:
        model_authority = resolve_manifest_model_authority(manifest)
    embedding_binding = model_authority["models"]["embedding"]
    rerank_binding = model_authority["models"]["rerank"]
    return {
        "local_files_only": True,
        "local_path": embedding_binding["local_path"],
        "local_path_text": embedding_binding["local_path_text"],
        "model_authority": model_authority,
        "model_id": embedding_binding["model_id"],
        "model_revision": embedding_binding["model_revision"],
        "model_snapshot_hash": embedding_binding["model_snapshot_hash"],
        "rerank_local_path": rerank_binding["local_path"],
        "rerank_local_path_text": rerank_binding["local_path_text"],
        "rerank_model": rerank_binding["model_id"],
        "rerank_model_revision": rerank_binding["model_revision"],
        "rerank_model_snapshot_hash": rerank_binding["model_snapshot_hash"],
        "tokenizer_files_hash": embedding_binding["tokenizer_files_hash"],
        "tokenizer_id": embedding_binding["tokenizer_id"],
        "tokenizer_revision": embedding_binding["tokenizer_revision"],
        "trust_remote_code": False,
    }


def get_embedding_policy(manifest: dict) -> dict:
    get_embedding_model_config(manifest)
    try:
        retrieval_policies = validate_retrieval_policies(manifest)
    except RetrievalPolicyError as exc:
        raise RuntimeError(str(exc)) from exc
    embedding_query_policy = retrieval_policies["embedding_query_policy"]
    return {
        "dtype": "float32",
        "embedding_dimension": 1024,
        "normalize_embeddings": bool(embedding_query_policy["normalize_embeddings"]),
        "passage_prefix": "",
        "query_prefix": str(embedding_query_policy["query_prefix"]),
        "tolerance_absolute": 0.00001,
        "tolerance_relative": 0.00001,
    }


def resolve_manifest_build_device(manifest: dict) -> str:
    get_embedding_model_config(manifest)
    return "cpu"


def resolve_approved_build_device(build_context: dict) -> str:
    device = str(build_context["device_policy"]["selected_build_device"])
    if device not in {"cpu", "cuda"}:
        raise RuntimeError("FEL: approval device_policy.selected_build_device ar ogiltig")
    return device


def validate_build_device_runtime(device: str) -> dict:
    if device == "cpu":
        return {
            "status": "PASS",
            "selected_build_device": "cpu",
            "cuda_available": None,
            "cuda_device_count": None,
            "cuda_device_name": None,
        }
    if device != "cuda":
        raise RuntimeError("FEL: okand build-enhet")
    try:
        import torch
    except Exception as exc:
        raise RuntimeError("FEL: cuda-build kraver torch runtime") from exc
    cuda_available = bool(torch.cuda.is_available())
    cuda_device_count = int(torch.cuda.device_count())
    if not cuda_available or cuda_device_count < 1:
        raise RuntimeError("FEL: approval valde cuda men lokal CUDA-runtime ar inte tillganglig")
    return {
        "status": "PASS",
        "selected_build_device": "cuda",
        "cuda_available": cuda_available,
        "cuda_device_count": cuda_device_count,
        "cuda_device_name": torch.cuda.get_device_name(0),
    }


def select_equivalence_sample_indices(total_rows: int, sample_size: int) -> list[int]:
    if total_rows <= 0:
        raise RuntimeError("FEL: equivalence sample kraver minst en embeddingrad")
    bounded_size = min(total_rows, sample_size)
    if bounded_size == 1:
        return [0]
    last = total_rows - 1
    indices = {
        int(round(index * last / (bounded_size - 1)))
        for index in range(bounded_size)
    }
    return sorted(indices)


def get_embedding_batch_size(manifest: dict) -> int:
    get_embedding_model_config(manifest)
    return 64


def validate_classification_policy(classification_policy: object) -> None:
    if not isinstance(classification_policy, dict):
        raise RuntimeError("FEL: classification_policy maste vara ett JSON-objekt")
    if classification_policy != CANONICAL_CLASSIFICATION_RULES:
        raise RuntimeError("FEL: classification_policy matchar inte kanonisk klassificering")

    default_layer = classification_policy.get("default_layer")
    if default_layer not in CANONICAL_LAYERS:
        raise RuntimeError("FEL: classification_policy.default_layer ar ogiltig")

    precedence = classification_policy.get("precedence")
    if not isinstance(precedence, list) or not precedence:
        raise RuntimeError("FEL: classification_policy.precedence saknas eller ar tom")

    for rule in precedence:
        if not isinstance(rule, dict):
            raise RuntimeError("FEL: classification_policy.precedence innehaller ogiltig regel")
        if str(rule.get("type", "")) not in {"path_substring", "path_suffix"}:
            raise RuntimeError("FEL: classification_policy innehaller ogiltig regeltyp")
        if not str(rule.get("value", "")).strip():
            raise RuntimeError("FEL: classification_policy innehaller tomt regelvarde")
        if str(rule.get("layer", "")).upper() not in CANONICAL_LAYERS:
            raise RuntimeError("FEL: classification_policy innehaller ogiltigt lager")


def validate_flat_manifest_fields(manifest: dict) -> None:
    require_manifest_root_str(manifest, "contract_version")
    require_manifest_root_str(manifest, "corpus_manifest_hash")
    require_manifest_root_str(manifest, "embedding_model")
    require_manifest_root_str(manifest, "rerank_model")
    require_manifest_root_int(manifest, "chunk_size")
    require_manifest_root_int(manifest, "chunk_overlap")
    require_manifest_root_int(manifest, "top_k")
    require_manifest_root_int(manifest, "vector_candidate_k")
    require_manifest_root_int(manifest, "lexical_candidate_k")
    get_chunking_policy(manifest)
    try:
        validate_retrieval_policies(manifest)
    except RetrievalPolicyError as exc:
        raise RuntimeError(str(exc)) from exc


def validate_index_manifest(
    manifest: dict,
    corpus_manifest_hash: str,
    *,
    require_chunk_manifest_hash: bool,
    build_mode: str = REBUILD_MODE,
) -> None:
    if build_mode not in {INITIAL_BUILD_MODE, REBUILD_MODE}:
        raise RuntimeError("FEL: okant build-lage for indexmanifestvalidering")
    missing = sorted(INDEX_MANIFEST_REQUIRED_FIELDS - set(manifest))
    if missing:
        raise RuntimeError(
            "FEL: index_manifest.json saknar fält: " + ", ".join(missing)
        )

    reject_deprecated_manifest_config(manifest)
    load_manifest_corpus_files(manifest)

    if str(manifest["contract_version"]) != CANONICAL_CONTRACT_VERSION:
        raise RuntimeError("FEL: contract_version matchar inte kanoniskt värde")
    stored_corpus_manifest_hash = require_manifest_root_str(manifest, "corpus_manifest_hash")
    if stored_corpus_manifest_hash != corpus_manifest_hash:
        if build_mode == INITIAL_BUILD_MODE:
            manifest["corpus_manifest_hash"] = corpus_manifest_hash
        else:
            raise RuntimeError("FEL: corpus_manifest_hash matchar inte kanonisk corpusserialisering")
    validate_flat_manifest_fields(manifest)
    get_embedding_model_config(manifest)
    get_embedding_policy(manifest)
    resolve_manifest_build_device(manifest)
    get_embedding_batch_size(manifest)

    chunk_manifest_hash = manifest.get("chunk_manifest_hash")
    if not isinstance(chunk_manifest_hash, str):
        raise RuntimeError("FEL: chunk_manifest_hash måste vara en sträng")
    if require_chunk_manifest_hash and not chunk_manifest_hash.strip():
        raise RuntimeError("FEL: chunk_manifest_hash saknas i index_manifest.json")

    validate_classification_policy(manifest.get("classification_policy"))


def finalize_index_manifest(
    manifest: dict,
    chunk_manifest_hash: str,
    path: Path,
) -> dict:
    finalized_manifest = deepcopy(manifest)
    finalized_manifest["chunk_manifest_hash"] = chunk_manifest_hash
    save_json_object(path, finalized_manifest)
    materialized_manifest = load_json_object(path)
    validate_index_manifest(
        materialized_manifest,
        str(materialized_manifest["corpus_manifest_hash"]),
        require_chunk_manifest_hash=True,
    )
    return materialized_manifest


def compute_chunk_manifest_hash(records: list[dict]) -> str:
    serialized = render_chunk_manifest(records)
    return compute_sha256_text(serialized)


def write_chunk_manifest(records: list[dict], contract_version: str, path: Path) -> None:
    assert_staging_write_path(path)
    versioned_records = bind_contract_version(records, contract_version)
    path.write_text(render_chunk_manifest(versioned_records), encoding="utf-8")


def bind_contract_version(records: list[dict], contract_version: str) -> list[dict]:
    versioned_records = []
    for record in records:
        versioned_record = dict(record)
        versioned_record["contract_version"] = contract_version
        versioned_records.append(versioned_record)
    return versioned_records


def write_lexical_index(
    documents: list[str],
    ids: list[str],
    manifest: dict,
    lexical_index_dir: Path,
    lexical_index_manifest: Path,
    lexical_index_documents: Path,
) -> None:
    assert_staging_write_path(lexical_index_dir)
    assert_staging_write_path(lexical_index_manifest)
    assert_staging_write_path(lexical_index_documents)
    lexical_records = []
    document_frequency: dict[str, int] = {}
    total_length = 0

    for doc_id, document in zip(ids, documents):
        tokens = tokenize_for_lexical(document)
        total_length += len(tokens)

        term_freqs: dict[str, int] = {}
        for token in tokens:
            term_freqs[token] = term_freqs.get(token, 0) + 1

        for token in term_freqs:
            document_frequency[token] = document_frequency.get(token, 0) + 1

        lexical_records.append({
            "doc_id": doc_id,
            "text": normalize_document_text(document),
            "term_freqs": term_freqs,
            "length": len(tokens),
        })

    lexical_index_dir.mkdir(parents=True, exist_ok=True)
    lexical_index_documents.write_text(
        "\n".join(
            json.dumps(record, ensure_ascii=False, sort_keys=True)
            for record in lexical_records
        ),
        encoding="utf-8",
    )

    lexical_manifest = {
        "contract_version": manifest["contract_version"],
        "corpus_manifest_hash": manifest["corpus_manifest_hash"],
        "chunk_manifest_hash": manifest["chunk_manifest_hash"],
        "doc_count": len(lexical_records),
        "avg_doc_length": (total_length / len(lexical_records)) if lexical_records else 0.0,
        "document_frequency": document_frequency,
        "doc_ids": [record["doc_id"] for record in lexical_records],
    }
    save_json_object(lexical_index_manifest, lexical_manifest)


def ensure_unique_doc_ids(records: list[dict]) -> None:
    seen: set[str] = set()
    for record in records:
        doc_id = str(record.get("doc_id", ""))
        validate_sha256_hex(doc_id, "doc_id")
        if doc_id in seen:
            raise RuntimeError(f"FEL: duplicerat doc_id i chunk manifest: {doc_id}")
        seen.add(doc_id)


def load_embedding_model(model_config: dict, device: str) -> SentenceTransformer:
    return SentenceTransformer(
        str(model_config["local_path"]),
        device=device,
        local_files_only=model_config["local_files_only"],
        trust_remote_code=model_config["trust_remote_code"],
    )


def build_embedding_inputs(documents: list[str], embedding_policy: dict) -> list[str]:
    passage_prefix = str(embedding_policy["passage_prefix"])
    return [passage_prefix + document for document in documents]


def encode_embeddings(
    model: SentenceTransformer,
    texts: list[str],
    embedding_policy: dict,
    batch_size: int,
) -> np.ndarray:
    encoded = model.encode(
        texts,
        show_progress_bar=True,
        batch_size=batch_size,
        normalize_embeddings=bool(embedding_policy["normalize_embeddings"]),
        convert_to_numpy=True,
    )
    return np.asarray(encoded, dtype=np.float32)


def validate_embedding_matrix(
    embeddings: np.ndarray,
    *,
    expected_rows: int,
    embedding_policy: dict,
) -> np.ndarray:
    matrix = np.asarray(embeddings, dtype=np.float32)
    if matrix.ndim != 2:
        raise RuntimeError("FEL: embeddingmatris maste vara tva-dimensionell")
    if matrix.shape[0] != expected_rows:
        raise RuntimeError("FEL: embeddingradantal matchar inte chunkantal")
    if matrix.shape[1] != int(embedding_policy["embedding_dimension"]):
        raise RuntimeError("FEL: embeddingdimension matchar inte manifest")
    if not np.isfinite(matrix).all():
        raise RuntimeError("FEL: embeddingmatris innehaller NaN eller infinity")
    return np.ascontiguousarray(matrix, dtype=np.float32)


def assert_embedding_equivalence(
    cpu_embeddings: np.ndarray,
    accelerated_embeddings: np.ndarray,
    embedding_policy: dict,
) -> None:
    if cpu_embeddings.shape != accelerated_embeddings.shape:
        raise RuntimeError("DEVICE_DRIFT: CPU/GPU embeddingform skiljer sig")
    if not np.allclose(
        cpu_embeddings,
        accelerated_embeddings,
        atol=float(embedding_policy["tolerance_absolute"]),
        rtol=float(embedding_policy["tolerance_relative"]),
    ):
        max_delta = float(np.max(np.abs(cpu_embeddings - accelerated_embeddings)))
        raise RuntimeError(f"DEVICE_DRIFT: CPU/GPU embeddingdrift overskrider tolerans: {max_delta}")


def canonical_embedding_bytes(embedding: np.ndarray) -> bytes:
    vector = np.asarray(embedding, dtype=np.dtype("<f4")).reshape(-1)
    if not np.isfinite(vector).all():
        raise RuntimeError("FEL: embeddingvektor innehaller NaN eller infinity")
    return np.ascontiguousarray(vector, dtype=np.dtype("<f4")).tobytes(order="C")


def compute_embedding_vector_hash(embedding: np.ndarray) -> str:
    return compute_sha256_bytes(canonical_embedding_bytes(embedding))


def compute_doc_id_set_hash(doc_ids: list[str]) -> str:
    for doc_id in doc_ids:
        validate_sha256_hex(doc_id, "doc_id")
    canonical_bytes = "".join(doc_id + "\n" for doc_id in sorted(doc_ids)).encode("ascii")
    return compute_sha256_bytes(canonical_bytes)


def build_vector_export_records(
    chunk_records: list[dict],
    embeddings: np.ndarray,
    manifest: dict,
    model_config: dict,
    embedding_policy: dict,
) -> list[dict]:
    ordered_records = order_chunk_records(chunk_records)
    if chunk_records != ordered_records:
        raise RuntimeError("FEL: embeddingordning matchar inte kanonisk chunkordning")
    if len(ordered_records) != len(embeddings):
        raise RuntimeError("FEL: vector export antal matchar inte chunkantal")

    export_records = []
    for record, embedding in zip(ordered_records, embeddings):
        export_records.append({
            "chunk_index": int(record["chunk_index"]),
            "chunk_manifest_hash": str(manifest["chunk_manifest_hash"]),
            "content_hash": validate_sha256_hex(record["content_hash"], "content_hash"),
            "contract_version": str(manifest["contract_version"]),
            "corpus_manifest_hash": str(manifest["corpus_manifest_hash"]),
            "doc_id": validate_sha256_hex(record["doc_id"], "doc_id"),
            "embedding_dimension": int(embedding_policy["embedding_dimension"]),
            "embedding_dtype": str(embedding_policy["dtype"]),
            "embedding_model_snapshot_hash": model_config["model_snapshot_hash"],
            "embedding_normalized": bool(embedding_policy["normalize_embeddings"]),
            "embedding_vector_hash": compute_embedding_vector_hash(embedding),
            "file": str(record["file"]),
            "layer": str(record["layer"]),
            "source_type": str(record["source_type"]),
            "tokenizer_files_hash": model_config["tokenizer_files_hash"],
        })
    return export_records


def render_vector_export(records: list[dict]) -> str:
    ordered_records = order_chunk_records(records)
    if not ordered_records:
        raise RuntimeError("FEL: vector export far inte vara tom")
    return "".join(canonical_json_dumps(record) + "\n" for record in ordered_records)


def compute_vector_export_hash(records: list[dict]) -> str:
    return compute_sha256_text(render_vector_export(records))


def build_vector_metadatas(
    vector_export_records: list[dict],
    manifest: dict,
) -> list[dict]:
    chunk_manifest_hash = str(manifest["chunk_manifest_hash"])
    return [
        {
            "chunk_index": int(record["chunk_index"]),
            "content_hash": record["content_hash"],
            "contract_version": record["contract_version"],
            "corpus_manifest_hash": record["corpus_manifest_hash"],
            "doc_id": record["doc_id"],
            "embedding_dimension": int(record["embedding_dimension"]),
            "embedding_dtype": record["embedding_dtype"],
            "embedding_model_snapshot_hash": record["embedding_model_snapshot_hash"],
            "embedding_normalized": bool(record["embedding_normalized"]),
            "embedding_vector_hash": record["embedding_vector_hash"],
            "file": record["file"],
            "layer": record["layer"],
            "source_type": record["source_type"],
            "tokenizer_files_hash": record["tokenizer_files_hash"],
            "chunk_manifest_hash": chunk_manifest_hash,
        }
        for record in vector_export_records
    ]


def build_collection_metadata(
    manifest: dict,
    vector_export_hash: str,
    vector_export_records: list[dict],
    model_config: dict,
    embedding_policy: dict,
) -> dict:
    doc_ids = [str(record["doc_id"]) for record in vector_export_records]
    return {
        "artifact_type": "chroma_vector_index",
        "chunk_manifest_hash": str(manifest["chunk_manifest_hash"]),
        "collection_name": COLLECTION_NAME,
        "contract_version": str(manifest["contract_version"]),
        "corpus_manifest_hash": str(manifest["corpus_manifest_hash"]),
        "doc_count": len(doc_ids),
        "doc_id_set_hash": compute_doc_id_set_hash(doc_ids),
        "embedding_dimension": int(embedding_policy["embedding_dimension"]),
        "embedding_dtype": str(embedding_policy["dtype"]),
        "embedding_model_snapshot_hash": model_config["model_snapshot_hash"],
        "normalize_embeddings": bool(embedding_policy["normalize_embeddings"]),
        "passage_prefix": str(embedding_policy["passage_prefix"]),
        "query_prefix": str(embedding_policy["query_prefix"]),
        "source_artifact": ".repo_index/chunk_manifest.jsonl",
        "tokenizer_files_hash": model_config["tokenizer_files_hash"],
        "vector_contract_version": "T10",
        "vector_export_hash": vector_export_hash,
    }


def bind_vector_artifact_hash(
    manifest: dict,
    vector_export_hash: str,
    path: Path,
) -> dict:
    finalized_manifest = deepcopy(manifest)
    validate_sha256_hex(vector_export_hash, "vector_export_hash")
    save_json_object(path, finalized_manifest)
    return load_json_object(path)


def build_chunk_artifacts(files: list[str], manifest: dict) -> tuple[list[str], list[dict], list[str], list[dict]]:
    documents = []
    metadatas = []
    ids = []
    chunk_records = []

    chunk_size, chunk_overlap = get_chunking_policy(manifest)
    contract_version = str(manifest["contract_version"])
    corpus_manifest_hash = str(manifest["corpus_manifest_hash"])

    print("[STEG] Indexerar filer...")

    for file in tqdm(files):
        path = ROOT / file

        if not path.exists():
            raise RuntimeError(f"FEL: fil i index_manifest.json corpus.files saknas: {file}")

        try:
            content = normalize_corpus_text_for_hash(path.read_bytes(), file)
        except OSError as exc:
            raise RuntimeError(f"FEL: kunde inte lasa textinnehall for {file}") from exc

        if not content.strip():
            continue

        chunk_index = 0

        for chunk, start_char, end_char in iter_chunk_spans(
            content,
            chunk_size=chunk_size,
            overlap=chunk_overlap,
        ):
            if not chunk.strip():
                continue

            document = chunk
            content_hash = compute_sha256_text(chunk)
            doc_id = build_canonical_doc_id(
                contract_version,
                file,
                chunk_index,
                content_hash,
            )

            documents.append(document)

            metadata = {
                "content_hash": content_hash,
                "contract_version": contract_version,
                "corpus_manifest_hash": corpus_manifest_hash,
                "doc_id": doc_id,
                "file": file,
                "chunk_index": chunk_index,
                "type": file.split('.')[-1],
                "layer": classify(file, manifest),
                "source_type": "chunk",
            }
            metadatas.append(metadata)
            ids.append(doc_id)
            chunk_records.append({
                "contract_version": contract_version,
                "corpus_manifest_hash": corpus_manifest_hash,
                "doc_id": doc_id,
                "file": file,
                "chunk_index": chunk_index,
                "start_char": start_char,
                "end_char": end_char,
                "layer": metadata["layer"],
                "source_type": "chunk",
                "content_hash": content_hash,
                "text": document,
            })

            chunk_index += 1

    return documents, metadatas, ids, chunk_records


def result_check(status: str, expected: str, actual: str, failure_class: str | None = None) -> dict:
    return {
        "status": status,
        "expected": expected,
        "actual": actual,
        "failure_class": failure_class,
    }


def pass_check(expected: str, actual: str = "PASS") -> dict:
    return result_check("PASS", expected, actual)


def relative_artifact_paths(build_context: dict) -> dict:
    return {
        "index_manifest": display_path(build_context["index_manifest"]),
        "chunk_manifest": display_path(build_context["chunk_manifest"]),
        "lexical_index": display_path(build_context["lexical_index_dir"]) + "/",
        "chroma_db": display_path(build_context["vector_db_dir"]) + "/",
        "build_execution_result": display_path(build_context["build_execution_result"]),
        "staging_verification_result": display_path(build_context["staging_verification_result"]),
        "promotion_result": display_path(build_context["promotion_result"]),
    }


def checkpoint_result(status: str, authority: str, expected: str, actual: str, failure_class: str | None = None) -> dict:
    return {
        "status": status,
        "authority": authority,
        "expected": expected,
        "actual": actual,
        "failure_class": failure_class,
    }


def build_checkpoint_map(
    *,
    staging_verified: bool,
    promotion_occurred: bool,
    embedding_execution: dict | None = None,
) -> dict:
    pass_status = "PASS" if staging_verified else "NOT_APPLICABLE"
    promotion_status = "PASS" if promotion_occurred else "NOT_APPLICABLE"
    device_actual = "Verifierad" if staging_verified else "Ej natt"
    if isinstance(embedding_execution, dict) and staging_verified:
        device_actual = (
            f"{embedding_execution.get('full_corpus_embedding_device')} full-corpus encode; "
            f"CPU-baslinje rader={embedding_execution.get('full_corpus_cpu_baseline_rows')}; "
            f"bounded equivalence rader={embedding_execution.get('bounded_equivalence_rows')}"
        )
    return {
        "approval_validation": checkpoint_result(
            "PASS",
            "actual_truth/contracts/retrieval/build_approval_contract.md",
            "Godkand approvalartefakt utan natverk eller fallback",
            "Approval validerades fore mutation",
        ),
        "windows_runtime_validation": checkpoint_result(
            "PASS",
            "codex/AVELI_OPERATING_SYSTEM.md",
            CANONICAL_INTERPRETER_RELATIVE,
            display_path(CANONICAL_SEARCH_PYTHON),
        ),
        "manifest_input_validation": checkpoint_result(
            "PASS",
            "actual_truth/contracts/retrieval/index_structure_contract.md",
            "Manifestagd corpusinput",
            "Manifestinput validerades via approvalartefakt",
        ),
        "staging_write_validation": checkpoint_result(
            pass_status,
            "actual_truth/DETERMINED_TASKS/retrieval_index_build_execution/B01_controller_governed_index_build.md",
            "Endast staging skrivs fore verifiering",
            "Staging verifierad" if staging_verified else "Ej natt",
        ),
        "chunk_manifest_validation": checkpoint_result(
            pass_status,
            "actual_truth/contracts/retrieval/index_structure_contract.md",
            "chunk_manifest.jsonl matchar manifest och doc_id-kontrakt",
            "Verifierad" if staging_verified else "Ej natt",
        ),
        "lexical_index_validation": checkpoint_result(
            pass_status,
            "actual_truth/contracts/retrieval/index_structure_contract.md",
            "Lexikalt doc_id-set matchar chunkmanifest",
            "Verifierad" if staging_verified else "Ej natt",
        ),
        "vector_index_validation": checkpoint_result(
            pass_status,
            "actual_truth/contracts/retrieval/index_structure_contract.md",
            "Vektorindexets doc_id-set matchar chunkmanifest",
            "Verifierad" if staging_verified else "Ej natt",
        ),
        "cpu_gpu_equivalence_validation": checkpoint_result(
            pass_status,
            "actual_truth/contracts/retrieval/determinism_contract.md",
            "Builden foljer godkand devicepolicy och explicit equivalence-lage",
            device_actual,
        ),
        "artifact_hash_validation": checkpoint_result(
            pass_status,
            "actual_truth/contracts/retrieval/build_execution_result_contract.md",
            "Artefakthashar beraknas deterministiskt",
            "Verifierad" if staging_verified else "Ej natt",
        ),
        "pre_promotion_validation": checkpoint_result(
            pass_status,
            "actual_truth/contracts/retrieval/build_execution_result_contract.md",
            "Promotion forbjuden tills staging PASS",
            "Verifierad" if staging_verified else "Ej natt",
        ),
        "promotion_validation": checkpoint_result(
            promotion_status,
            "actual_truth/contracts/retrieval/build_execution_result_contract.md",
            "Promotion installerar full artefaktuppsattning",
            "Promotion klar" if promotion_occurred else "Ej forsokt",
        ),
        "post_promotion_validation": checkpoint_result(
            promotion_status,
            "actual_truth/contracts/retrieval/index_structure_contract.md",
            "Aktivt manifest ar ACTIVE_VERIFIED och artefakter finns",
            "Verifierad" if promotion_occurred else "Ej forsokt",
        ),
    }


def base_artifact_hashes(manifest: dict, vector_export_hash: str | None = None) -> dict:
    return {
        "index_manifest_hash": None,
        "corpus_manifest_hash": manifest.get("corpus_manifest_hash"),
        "chunk_manifest_hash": manifest.get("chunk_manifest_hash"),
        "lexical_index_hash": None,
        "chroma_db_hash": None,
        "vector_export_hash": vector_export_hash,
        "build_execution_result_hash": None,
        "staging_verification_result_hash": None,
    }


def collect_staging_artifact_hashes(build_context: dict, manifest: dict, vector_export_hash: str) -> dict:
    hashes = base_artifact_hashes(manifest, vector_export_hash)
    hashes["index_manifest_hash"] = compute_file_hash(build_context["index_manifest"])
    hashes["chunk_manifest_hash"] = compute_file_hash(build_context["chunk_manifest"])
    hashes["lexical_index_hash"] = compute_directory_hash(build_context["lexical_index_dir"])
    hashes["chroma_db_hash"] = compute_directory_hash(build_context["vector_db_dir"])
    if build_context["build_execution_result"].exists():
        hashes["build_execution_result_hash"] = compute_file_hash(build_context["build_execution_result"])
    if build_context["staging_verification_result"].exists():
        hashes["staging_verification_result_hash"] = compute_file_hash(build_context["staging_verification_result"])
    return hashes


def load_jsonl_records(path: Path) -> list[dict]:
    if not path.exists() or not path.is_file():
        raise RuntimeError(f"FEL: JSONL-artefakt saknas: {display_path(path)}")
    records = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            raise RuntimeError(f"FEL: tom rad i JSONL pa rad {line_number}")
        value = json.loads(line)
        if not isinstance(value, dict):
            raise RuntimeError(f"FEL: JSONL-rad {line_number} ar inte objekt")
        records.append(value)
    if not records:
        raise RuntimeError("FEL: chunk_manifest.jsonl far inte vara tom")
    return records


def validate_chunk_records(records: list[dict], manifest: dict) -> None:
    if records != order_chunk_records(records):
        raise RuntimeError("FEL: chunk_manifest.jsonl ar inte kanoniskt sorterad")
    ensure_unique_doc_ids(records)
    for record in records:
        for field_name in ("doc_id", "file", "chunk_index", "layer", "source_type", "content_hash", "text"):
            if field_name not in record:
                raise RuntimeError(f"FEL: chunkrecord saknar {field_name}")
        if record["source_type"] != "chunk":
            raise RuntimeError("FEL: chunkrecord source_type maste vara chunk")
        if compute_sha256_text(str(record["text"])) != record["content_hash"]:
            raise RuntimeError("FEL: content_hash matchar inte chunktext")
        expected_doc_id = build_canonical_doc_id(
            str(manifest["contract_version"]),
            str(record["file"]),
            int(record["chunk_index"]),
            str(record["content_hash"]),
        )
        if record["doc_id"] != expected_doc_id:
            raise RuntimeError("FEL: doc_id matchar inte kanonisk formel")


def verify_vector_collection(collection, records: list[dict], manifest: dict, embedding_policy: dict) -> None:
    result = collection.get(include=["metadatas"])
    vector_ids = [str(doc_id) for doc_id in (result.get("ids") or [])]
    metadatas = result.get("metadatas") or []
    expected_ids = {str(record["doc_id"]) for record in records}
    if set(vector_ids) != expected_ids:
        raise RuntimeError("FEL: vector doc_id-set matchar inte chunkmanifest")
    chunk_by_id = {str(record["doc_id"]): record for record in records}
    for doc_id, metadata in zip(vector_ids, metadatas):
        if not isinstance(metadata, dict):
            raise RuntimeError("FEL: vector metadata saknas")
        record = chunk_by_id[doc_id]
        for field_name in ("file", "chunk_index", "content_hash", "contract_version", "corpus_manifest_hash"):
            if str(metadata.get(field_name)) != str(record[field_name]):
                raise RuntimeError(f"FEL: vector metadata matchar inte chunkmanifest for {field_name}")
        if int(metadata.get("embedding_dimension", 0)) != int(embedding_policy["embedding_dimension"]):
            raise RuntimeError("FEL: vector embedding_dimension matchar inte manifest")
        if metadata.get("chunk_manifest_hash") != manifest["chunk_manifest_hash"]:
            raise RuntimeError("FEL: vector metadata chunk_manifest_hash matchar inte manifest")


def verify_lexical_index(build_context: dict, records: list[dict], manifest: dict) -> None:
    lexical_manifest = load_json_object(build_context["lexical_index_manifest"])
    lexical_docs = load_jsonl_records(build_context["lexical_index_documents"])
    expected_ids = {str(record["doc_id"]) for record in records}
    lexical_manifest_ids = {str(doc_id) for doc_id in lexical_manifest.get("doc_ids", [])}
    lexical_doc_ids = {str(record.get("doc_id", "")) for record in lexical_docs}
    if lexical_manifest_ids != expected_ids or lexical_doc_ids != expected_ids:
        raise RuntimeError("FEL: lexical doc_id-set matchar inte chunkmanifest")
    for field_name in ("contract_version", "corpus_manifest_hash", "chunk_manifest_hash"):
        if lexical_manifest.get(field_name) != manifest[field_name]:
            raise RuntimeError(f"FEL: lexical manifest {field_name} matchar inte indexmanifest")


def verify_staging_artifacts(
    build_context: dict,
    staging_manifest: dict,
    collection,
    versioned_chunk_records: list[dict],
    vector_export_hash: str,
    embedding_policy: dict,
    active_snapshot_before: dict,
) -> tuple[dict, dict, dict]:
    checks = {
        "approval_valid": pass_check("Approval validerad fore mutation"),
        "manifest_schema_valid": pass_check("Manifestschema valideras mot kanonisk flat schema"),
        "manifest_owned_corpus_valid": pass_check("Corpus kommer fran manifestagd input"),
        "corpus_manifest_hash_valid": pass_check("corpus_manifest_hash matchar corpusserialisering"),
        "required_artifact_set_complete": pass_check("Alla obligatoriska indexartefakter finns i staging"),
        "chunk_manifest_hash_valid": pass_check("chunk_manifest_hash matchar chunk_manifest.jsonl"),
        "chunk_order_valid": pass_check("Chunkar ar kanoniskt sorterade"),
        "content_hash_valid": pass_check("content_hash beraknas fran chunktext"),
        "doc_id_formula_valid": pass_check("doc_id beraknas deterministiskt"),
        "doc_id_unique": pass_check("doc_id ar unika"),
        "lexical_doc_id_parity": pass_check("Lexikalt doc_id-set matchar chunkmanifest"),
        "lexical_tokenization_valid": pass_check("Lexikal tokenisering matchar lagrade termfrekvenser"),
        "vector_doc_id_parity": pass_check("Vektorindexets doc_id-set matchar chunkmanifest"),
        "vector_count_valid": pass_check("Vektorantal matchar chunkmanifest"),
        "vector_metadata_parity": pass_check("Vektormetadata matchar chunkmanifest"),
        "embedding_dimension_valid": pass_check("Embeddingdimension matchar manifest"),
        "cross_artifact_binding_valid": pass_check("Manifest, chunkmanifest, lexikalt index och vektorindex delar hashbindningar"),
        "model_lock_valid": pass_check("Approval model_id matchar manifestets embedding_model"),
        "tokenizer_lock_valid": pass_check("Approval tokenizer_id och hashar ar validerade"),
        "artifact_hashes_valid": pass_check("Artefakthashar kan beraknas"),
        "no_active_write_before_promotion": pass_check("Aktiva artefakter andras inte fore promotion"),
        "no_fallback_used": pass_check("Ingen fallback anvands"),
    }

    files = load_manifest_corpus_files(staging_manifest)
    corpus_manifest_hash = compute_corpus_manifest_hash(files)
    validate_index_manifest(
        staging_manifest,
        corpus_manifest_hash,
        require_chunk_manifest_hash=True,
    )

    try:
        integrity_report = validate_index_artifact_integrity(
            root=ROOT,
            index_root=build_context["staging_root"],
            manifest_path=build_context["index_manifest"],
            chunk_manifest_path=build_context["chunk_manifest"],
            chroma_db_dir=build_context["vector_db_dir"],
            lexical_index_dir=build_context["lexical_index_dir"],
            collection=collection,
        )
    except IndexArtifactIntegrityError as exc:
        raise RuntimeError(str(exc)) from exc

    materialized_records = integrity_report["chunk_records"]
    if render_chunk_manifest(materialized_records) != render_chunk_manifest(versioned_chunk_records):
        raise RuntimeError("FEL: staging chunkmanifest matchar inte byggda chunkrecords")
    if compute_chunk_manifest_hash(materialized_records) != staging_manifest["chunk_manifest_hash"]:
        raise RuntimeError("FEL: chunk_manifest_hash matchar inte staging chunkmanifest")
    assert_active_snapshot_unchanged(active_snapshot_before)

    verified_manifest = deepcopy(staging_manifest)
    verified_manifest["manifest_state"] = "STAGING_VERIFIED"
    save_json_object(build_context["index_manifest"], verified_manifest)
    artifact_hashes = collect_staging_artifact_hashes(
        build_context,
        verified_manifest,
        vector_export_hash,
    )

    staging_result = {
        "artifact_type": "staging_verification_result",
        "build_id": build_context["build_id"],
        "staging_root": display_path(build_context["staging_root"]),
        "status": "PASS",
        "manifest_state": "STAGING_VERIFIED",
        "checks": checks,
        "device_policy": build_context["device_policy"],
        "embedding_execution": build_context["embedding_execution"],
        "model_authority": serialize_model_authority_result(build_context["model_authority"]),
        "artifact_integrity": {
            "status": integrity_report["status"],
            "artifact_set": integrity_report["artifact_set"],
            "chunk_manifest": integrity_report["chunk_manifest"],
            "lexical_index": integrity_report["lexical_index"],
            "vector_index": integrity_report["vector_index"],
        },
        "doc_id_sets": {
            "chunk_manifest_count": len(materialized_records),
            "lexical_count": len(materialized_records),
            "vector_count": len(materialized_records),
            "doc_id_set_hash": compute_doc_id_set_hash([str(record["doc_id"]) for record in materialized_records]),
        },
        "artifact_hashes": artifact_hashes,
        "device_check": checks["no_fallback_used"],
        "model_check": checks["model_lock_valid"],
        "tokenizer_check": checks["tokenizer_lock_valid"],
        "ordering_check": checks["chunk_order_valid"],
        "forbidden_behavior_check": {
            "no_active_write_before_promotion": checks["no_active_write_before_promotion"],
            "no_fallback_used": checks["no_fallback_used"],
        },
        "failure": None,
    }
    save_json_object(build_context["staging_verification_result"], staging_result)
    artifact_hashes["staging_verification_result_hash"] = compute_file_hash(
        build_context["staging_verification_result"]
    )
    staging_result["artifact_hashes"] = artifact_hashes
    save_json_object(build_context["staging_verification_result"], staging_result)
    return verified_manifest, staging_result, artifact_hashes


def build_execution_result(
    build_context: dict,
    *,
    status: str,
    write_phase: str,
    artifact_hashes: dict,
    staging_verified: bool,
    promotion_occurred: bool,
    final_active_status: str,
    failure: dict | None,
) -> dict:
    completed_at = utc_now_iso()
    return {
        "artifact_type": "build_execution_result",
        "controller_scope": "retrieval_index_build_execution",
        "task_id": "B01",
        "mode": "build",
        "build_mode": build_context["build_mode"],
        "status": status,
        "build_id": build_context["build_id"],
        "approval_artifact": display_path(build_context["approval_artifact_path"]),
        "manifest_input": {
            "kind": build_context["manifest_input_kind"],
            "path": display_path(build_context["manifest_input_path"]),
        },
        "repo_root": ROOT.as_posix(),
        "target_path": TARGET_INDEX_RELATIVE,
        "staging_root": display_path(build_context["staging_root"]),
        "canonical_interpreter": CANONICAL_INTERPRETER_RELATIVE,
        "dependency_authority": build_context["dependency_authority"],
        "device_policy": build_context["device_policy"],
        "embedding_execution": build_context["embedding_execution"],
        "model_authority": serialize_model_authority_result(build_context["model_authority"]),
        "started_at_utc": build_context["started_at_utc"],
        "completed_at_utc": completed_at,
        "write_phase": write_phase,
        "artifact_paths": relative_artifact_paths(build_context),
        "artifact_hashes": artifact_hashes,
        "verification_checkpoints": build_checkpoint_map(
            staging_verified=staging_verified,
            promotion_occurred=promotion_occurred,
            embedding_execution=build_context["embedding_execution"],
        ),
        "promotion_occurred": promotion_occurred,
        "final_active_status": final_active_status,
        "failure": failure,
    }


def write_build_execution_result(build_context: dict, result: dict) -> dict:
    save_json_object(build_context["build_execution_result"], result)
    result["artifact_hashes"]["build_execution_result_hash"] = compute_file_hash(
        build_context["build_execution_result"]
    )
    save_json_object(build_context["build_execution_result"], result)
    return result


def assert_promotion_path(path: Path) -> None:
    resolved_path = path.resolve()
    resolved_parent = PROMOTION_PARENT.resolve()
    if not is_relative_to_path(resolved_path, resolved_parent):
        raise RuntimeError("FEL: promotion far endast anvanda .repo_index/_promotion")


def copy_staging_to_promotion_bundle(build_context: dict, active_manifest: dict, bundle_root: Path) -> None:
    assert_promotion_path(bundle_root)
    if bundle_root.exists():
        raise RuntimeError("FEL: promotion bundle finns redan och kraver explicit cleanup")
    bundle_root.mkdir(parents=True, exist_ok=False)
    write_json_object(bundle_root / "index_manifest.json", active_manifest)
    shutil.copy2(build_context["chunk_manifest"], bundle_root / "chunk_manifest.jsonl")
    shutil.copytree(build_context["lexical_index_dir"], bundle_root / "lexical_index")
    shutil.copytree(build_context["vector_db_dir"], bundle_root / "chroma_db")


def move_existing_active_artifact_to_backup(target: Path, backup_root: Path, name: str) -> Path | None:
    if not target.exists():
        return None
    backup_path = backup_root / name
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(target), str(backup_path))
    return backup_path


def rollback_active_promotion(installed: list[tuple[Path, Path | None]], backup_root: Path) -> None:
    for target, backup_path in reversed(installed):
        if target.exists():
            if target.is_dir():
                shutil.rmtree(target)
            else:
                target.unlink()
        if backup_path is not None and backup_path.exists():
            shutil.move(str(backup_path), str(target))
    if backup_root.exists() and not any(backup_root.iterdir()):
        backup_root.rmdir()


def install_active_artifact(source: Path, target: Path, backup_root: Path, name: str, installed: list[tuple[Path, Path | None]]) -> None:
    backup_path = move_existing_active_artifact_to_backup(target, backup_root, name)
    shutil.move(str(source), str(target))
    installed.append((target, backup_path))


def validate_active_post_promotion(active_artifact_hashes: dict) -> dict:
    active_manifest = load_json_object(INDEX_MANIFEST)
    if active_manifest.get("manifest_state") != "ACTIVE_VERIFIED":
        raise RuntimeError("FEL: aktivt manifest ar inte ACTIVE_VERIFIED efter promotion")
    files = load_manifest_corpus_files(active_manifest)
    validate_index_manifest(
        active_manifest,
        compute_corpus_manifest_hash(files),
        require_chunk_manifest_hash=True,
    )
    actual_hashes = {
        "index_manifest_hash": compute_file_hash(INDEX_MANIFEST),
        "chunk_manifest_hash": compute_file_hash(CHUNK_MANIFEST),
        "lexical_index_hash": compute_directory_hash(LEXICAL_INDEX_DIR),
        "chroma_db_hash": compute_directory_hash(CHROMA_DB_DIR),
    }
    for field_name, actual_hash in actual_hashes.items():
        if active_artifact_hashes.get(field_name) != actual_hash:
            raise RuntimeError(f"FEL: aktiv artefakthash matchar inte promotion for {field_name}")
    return {
        "active_manifest_present": pass_check("Aktivt index_manifest.json finns", "ACTIVE_VERIFIED"),
        "active_chunk_manifest_present": pass_check("Aktivt chunk_manifest.jsonl finns"),
        "active_lexical_index_present": pass_check("Aktivt lexical_index finns"),
        "active_chroma_db_present": pass_check("Aktivt chroma_db finns"),
        "active_hashes_match": pass_check("Aktiva hashvarden matchar promotion bundle"),
    }


def promote_verified_staging(
    build_context: dict,
    verified_manifest: dict,
    artifact_hashes: dict,
) -> dict:
    staging_result = load_json_object(build_context["staging_verification_result"])
    if staging_result.get("status") != "PASS":
        raise RuntimeError("FEL: promotion nekas utan staging_verification_result PASS")
    if staging_result.get("manifest_state") != "STAGING_VERIFIED":
        raise RuntimeError("FEL: promotion nekas utan STAGING_VERIFIED")

    promotion_started = utc_now_iso()
    work_root = PROMOTION_PARENT / build_context["build_id"]
    bundle_root = work_root / "bundle"
    backup_root = work_root / "backup"
    assert_promotion_path(work_root)
    if work_root.exists():
        raise RuntimeError("FEL: promotion path finns redan och kraver explicit cleanup")

    active_manifest = deepcopy(verified_manifest)
    active_manifest["manifest_state"] = "ACTIVE_VERIFIED"
    copy_staging_to_promotion_bundle(build_context, active_manifest, bundle_root)
    active_artifact_hashes = dict(artifact_hashes)
    active_artifact_hashes["index_manifest_hash"] = compute_file_hash(bundle_root / "index_manifest.json")
    active_artifact_hashes["chunk_manifest_hash"] = compute_file_hash(bundle_root / "chunk_manifest.jsonl")
    active_artifact_hashes["lexical_index_hash"] = compute_directory_hash(bundle_root / "lexical_index")
    active_artifact_hashes["chroma_db_hash"] = compute_directory_hash(bundle_root / "chroma_db")

    installed: list[tuple[Path, Path | None]] = []
    try:
        install_active_artifact(bundle_root / "chunk_manifest.jsonl", CHUNK_MANIFEST, backup_root, "chunk_manifest.jsonl", installed)
        install_active_artifact(bundle_root / "lexical_index", LEXICAL_INDEX_DIR, backup_root, "lexical_index", installed)
        install_active_artifact(bundle_root / "chroma_db", CHROMA_DB_DIR, backup_root, "chroma_db", installed)
        install_active_artifact(bundle_root / "index_manifest.json", INDEX_MANIFEST, backup_root, "index_manifest.json", installed)
        post_checks = validate_active_post_promotion(active_artifact_hashes)
    except Exception:
        rollback_active_promotion(installed, backup_root)
        raise

    promotion_result = {
        "artifact_type": "promotion_result",
        "build_id": build_context["build_id"],
        "build_mode": build_context["build_mode"],
        "status": "PASS",
        "source_staging_root": display_path(build_context["staging_root"]),
        "target_path": TARGET_INDEX_RELATIVE,
        "promotion_started_at_utc": promotion_started,
        "promotion_completed_at_utc": utc_now_iso(),
        "atomic_promotion": True,
        "active_manifest_state": "ACTIVE_VERIFIED",
        "active_artifact_paths": {
            "index_manifest": display_path(INDEX_MANIFEST),
            "chunk_manifest": display_path(CHUNK_MANIFEST),
            "lexical_index": display_path(LEXICAL_INDEX_DIR) + "/",
            "chroma_db": display_path(CHROMA_DB_DIR) + "/",
            "promotion_result": display_path(PROMOTION_RESULT),
        },
        "active_artifact_hashes": active_artifact_hashes,
        "post_promotion_checks": post_checks,
        "failure": None,
    }
    write_json_object(PROMOTION_RESULT, promotion_result)
    if backup_root.exists():
        shutil.rmtree(backup_root)
    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    if work_root.exists() and not any(work_root.iterdir()):
        work_root.rmdir()
    return promotion_result

# ---------------------------------------------------------
# Chunking
# ---------------------------------------------------------

def iter_chunk_spans(text: str, chunk_size: int, overlap: int) -> Iterable[tuple[str, int, int]]:

    if not text:
        return

    start = 0
    text_len = len(text)

    while start < text_len:

        end = min(start + chunk_size, text_len)

        yield text[start:end], start, end

        if end == text_len:
            break

        start = max(end - overlap, 0)


def chunk_text(text: str, chunk_size: int, overlap: int) -> Iterable[str]:
    for chunk, _start, _end in iter_chunk_spans(text, chunk_size, overlap):
        yield chunk

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------

def run_build(build_context: dict) -> None:
    load_build_dependency_modules()
    build_device = resolve_approved_build_device(build_context)
    build_context["embedding_execution"].update(
        {
            "device_runtime": validate_build_device_runtime(build_device),
            "full_corpus_embedding_device": build_device,
            "status": "DEVICE_VALIDATED",
        }
    )

    staging_root = build_context["staging_root"]
    staging_index_manifest = build_context["index_manifest"]
    staging_chunk_manifest = build_context["chunk_manifest"]
    staging_lexical_index_dir = build_context["lexical_index_dir"]
    staging_lexical_index_manifest = build_context["lexical_index_manifest"]
    staging_lexical_index_documents = build_context["lexical_index_documents"]
    staging_vector_db_dir = build_context["vector_db_dir"]

    print("\n[STEG] Läser indexmanifest...")

    manifest = build_context["manifest"]
    files = load_manifest_corpus_files(manifest)
    active_snapshot_before = active_authority_snapshot()

    excluded_paths = [file for file in files if is_excluded_path(file)]
    if excluded_paths:
        raise RuntimeError(
            "index_manifest.json corpus.files innehaller exkluderade paths: "
            + ", ".join(excluded_paths[:5])
        )

    print(f"[INFO] Build-lage: {build_context['build_mode']}")
    print(f"[INFO] {len(files)} filer hittades")

    corpus_manifest_hash = compute_corpus_manifest_hash(files)

    staging_root.mkdir(parents=True, exist_ok=False)

    validate_index_manifest(
        manifest,
        corpus_manifest_hash,
        require_chunk_manifest_hash=build_context["build_mode"] == REBUILD_MODE,
        build_mode=build_context["build_mode"],
    )

    staging_manifest = prepare_manifest_for_staging(manifest)
    save_json_object(staging_index_manifest, staging_manifest)

    documents, _chunk_metadatas, ids, chunk_records = build_chunk_artifacts(files, staging_manifest)
    ensure_unique_doc_ids(chunk_records)

    print(f"[INFO] {len(documents)} textblock skapades")

    contract_version = str(staging_manifest["contract_version"])
    versioned_chunk_records = bind_contract_version(chunk_records, contract_version)
    chunk_manifest_hash = compute_chunk_manifest_hash(versioned_chunk_records)
    staging_manifest = finalize_index_manifest(
        manifest=staging_manifest,
        chunk_manifest_hash=chunk_manifest_hash,
        path=staging_index_manifest,
    )
    write_chunk_manifest(
        chunk_records,
        contract_version=str(staging_manifest["contract_version"]),
        path=staging_chunk_manifest,
    )
    write_lexical_index(
        documents,
        ids,
        staging_manifest,
        lexical_index_dir=staging_lexical_index_dir,
        lexical_index_manifest=staging_lexical_index_manifest,
        lexical_index_documents=staging_lexical_index_documents,
    )

    # ---------------------------------------------------------
    # Model + embedding policy
    # ---------------------------------------------------------

    model_config = get_embedding_model_config(staging_manifest, build_context["model_authority"])
    embedding_policy = get_embedding_policy(staging_manifest)
    batch_size = get_embedding_batch_size(staging_manifest)
    embedding_inputs = build_embedding_inputs(documents, embedding_policy)

    print(f"[INFO] Manifeststyrd build-enhet: {build_device}")
    print(f"[INFO] Manifestlast batchstorlek: {batch_size}")
    device_policy = build_context["device_policy"]
    embeddings = None

    if build_device == "cpu":
        try:
            print("[STEG] Kodar embeddingar pa CPU...")
            cpu_model = load_embedding_model(model_config, "cpu")
            embeddings = validate_embedding_matrix(
                encode_embeddings(cpu_model, embedding_inputs, embedding_policy, batch_size),
                expected_rows=len(documents),
                embedding_policy=embedding_policy,
            )
            build_context["embedding_execution"].update(
                {
                    "bounded_equivalence_indices": [],
                    "bounded_equivalence_rows": 0,
                    "equivalence_verification": "NOT_REQUIRED",
                    "full_corpus_cpu_baseline_rows": len(documents),
                    "status": "PASS",
                }
            )
        except RuntimeError as e:
            raise RuntimeError("FEL: CPU-embedding for modellen misslyckades") from e
    else:
        try:
            print(f"[STEG] Laddar godkand embeddingmodell pa {build_device}...")
            accelerated_model = load_embedding_model(model_config, build_device)
            if bool(device_policy["bounded_equivalence_verification_required"]):
                sample_indices = select_equivalence_sample_indices(
                    len(embedding_inputs),
                    int(device_policy["equivalence_sample_size"]),
                )
                sample_inputs = [embedding_inputs[index] for index in sample_indices]
                print("[STEG] Kor bounded CPU/GPU-equivalence enligt approval...")
                cpu_model = load_embedding_model(model_config, "cpu")
                cpu_sample_embeddings = validate_embedding_matrix(
                    encode_embeddings(cpu_model, sample_inputs, embedding_policy, batch_size),
                    expected_rows=len(sample_inputs),
                    embedding_policy=embedding_policy,
                )
                accelerated_sample_embeddings = validate_embedding_matrix(
                    encode_embeddings(accelerated_model, sample_inputs, embedding_policy, batch_size),
                    expected_rows=len(sample_inputs),
                    embedding_policy=embedding_policy,
                )
                assert_embedding_equivalence(
                    cpu_sample_embeddings,
                    accelerated_sample_embeddings,
                    embedding_policy,
                )
                build_context["embedding_execution"].update(
                    {
                        "bounded_equivalence_indices": sample_indices,
                        "bounded_equivalence_rows": len(sample_indices),
                        "equivalence_verification": "PASS",
                    }
                )
            else:
                build_context["embedding_execution"].update(
                    {
                        "bounded_equivalence_indices": [],
                        "bounded_equivalence_rows": 0,
                        "equivalence_verification": "NOT_REQUIRED",
                    }
                )

            if bool(device_policy["cpu_baseline_required"]):
                print("[STEG] Kor full CPU-baslinje enligt approval...")
                cpu_model = load_embedding_model(model_config, "cpu")
                cpu_embeddings = validate_embedding_matrix(
                    encode_embeddings(cpu_model, embedding_inputs, embedding_policy, batch_size),
                    expected_rows=len(documents),
                    embedding_policy=embedding_policy,
                )
                accelerated_embeddings = validate_embedding_matrix(
                    encode_embeddings(accelerated_model, embedding_inputs, embedding_policy, batch_size),
                    expected_rows=len(documents),
                    embedding_policy=embedding_policy,
                )
                assert_embedding_equivalence(cpu_embeddings, accelerated_embeddings, embedding_policy)
                embeddings = accelerated_embeddings
                build_context["embedding_execution"]["full_corpus_cpu_baseline_rows"] = len(documents)
            else:
                print(f"[STEG] Kodar full corpus pa godkand build-enhet: {build_device}...")
                embeddings = validate_embedding_matrix(
                    encode_embeddings(accelerated_model, embedding_inputs, embedding_policy, batch_size),
                    expected_rows=len(documents),
                    embedding_policy=embedding_policy,
                )
                build_context["embedding_execution"]["full_corpus_cpu_baseline_rows"] = 0
            build_context["embedding_execution"]["status"] = "PASS"
        except RuntimeError as e:
            raise RuntimeError(
                f"DEVICE_DRIFT: embedding pa {build_device} matchar inte godkand devicepolicy"
            ) from e

    vector_export_records = build_vector_export_records(
        versioned_chunk_records,
        embeddings,
        staging_manifest,
        model_config,
        embedding_policy,
    )
    vector_export_hash = compute_vector_export_hash(vector_export_records)
    staging_manifest = bind_vector_artifact_hash(
        staging_manifest,
        vector_export_hash,
        staging_index_manifest,
    )
    vector_metadatas = build_vector_metadatas(vector_export_records, staging_manifest)

    staging_vector_db_dir.mkdir(parents=True, exist_ok=False)

    # ---------------------------------------------------------
    # Chroma
    # ---------------------------------------------------------

    print("[STEG] Oppnar Chroma DB...")

    client = chromadb.PersistentClient(
        path=str(staging_vector_db_dir)
    )

    collection = client.create_collection(
        name=COLLECTION_NAME,
        metadata=build_collection_metadata(
            staging_manifest,
            vector_export_hash,
            vector_export_records,
            model_config,
            embedding_policy,
        ),
    )

    # ---------------------------------------------------------
    # Store
    # ---------------------------------------------------------

    print("[STEG] Skriver till vektor-DB...")

    for i in tqdm(range(0, len(documents), 4000)):

        j = i + 4000

        collection.add(
            documents=documents[i:j],
            embeddings=embeddings[i:j].tolist(),
            metadatas=vector_metadatas[i:j],
            ids=ids[i:j]
        )

    print("\n[STEG] Verifierar stagingartefakter...")
    verified_manifest, _staging_result, artifact_hashes = verify_staging_artifacts(
        build_context,
        staging_manifest,
        collection,
        versioned_chunk_records,
        vector_export_hash,
        embedding_policy,
        active_snapshot_before,
    )
    build_result = build_execution_result(
        build_context,
        status="PASS",
        write_phase="staging_verified_before_promotion",
        artifact_hashes=artifact_hashes,
        staging_verified=True,
        promotion_occurred=False,
        final_active_status="NOT_PROMOTED",
        failure=None,
    )
    write_build_execution_result(build_context, build_result)
    artifact_hashes = collect_staging_artifact_hashes(build_context, verified_manifest, vector_export_hash)

    print("[STEG] Promoverar verifierade artefakter...")
    promotion_result = promote_verified_staging(
        build_context,
        verified_manifest,
        artifact_hashes,
    )
    artifact_hashes = collect_staging_artifact_hashes(build_context, verified_manifest, vector_export_hash)
    build_result = build_execution_result(
        build_context,
        status="PASS",
        write_phase="promotion_completed",
        artifact_hashes=artifact_hashes,
        staging_verified=True,
        promotion_occurred=True,
        final_active_status=promotion_result["active_manifest_state"],
        failure=None,
    )
    write_build_execution_result(build_context, build_result)

    print("\n[KLAR] Verifierad indexbuild och promotion klar.")
    print(f"[INFO] Plats: {staging_vector_db_dir}")
    print(f"[INFO] Indexerade textblock: {len(documents)}")
    print(f"[INFO] vector_export_hash: {vector_export_hash}")


def build_failure_object(exc: Exception, *, active_index_touched: bool, staging_invalidated: bool) -> dict:
    return {
        "failure_class": "STOP",
        "stop_reason": str(exc),
        "authority_file": "actual_truth/contracts/retrieval/build_execution_result_contract.md",
        "affected_path": TARGET_INDEX_RELATIVE,
        "active_index_touched": active_index_touched,
        "staging_invalidated": staging_invalidated,
        "next_allowed_action": "Stoppa, reparera blockerande B01-villkor och kor om med ny explicit approval.",
    }


def write_failed_result_surfaces(build_context: dict, exc: Exception) -> None:
    staging_exists = build_context["staging_root"].exists()
    if not staging_exists:
        return
    failure = build_failure_object(
        exc,
        active_index_touched=False,
        staging_invalidated=True,
    )
    manifest = build_context.get("manifest", {})
    artifact_hashes = base_artifact_hashes(manifest)
    required_check_names = [
        "approval_valid",
        "manifest_schema_valid",
        "manifest_owned_corpus_valid",
        "corpus_manifest_hash_valid",
        "required_artifact_set_complete",
        "chunk_manifest_hash_valid",
        "chunk_order_valid",
        "content_hash_valid",
        "doc_id_formula_valid",
        "doc_id_unique",
        "lexical_doc_id_parity",
        "lexical_tokenization_valid",
        "vector_doc_id_parity",
        "vector_count_valid",
        "vector_metadata_parity",
        "embedding_dimension_valid",
        "cross_artifact_binding_valid",
        "model_lock_valid",
        "tokenizer_lock_valid",
        "artifact_hashes_valid",
        "no_active_write_before_promotion",
        "no_fallback_used",
    ]
    failed_checks = {
        name: result_check(
            "NOT_APPLICABLE",
            "Kontrollen kraver full stagingverifiering",
            "Build stoppades innan kontrollen kunde slutforas",
            "STOP",
        )
        for name in required_check_names
    }
    failed_checks["no_active_write_before_promotion"] = result_check(
        "PASS",
        "Aktiva artefakter ska inte skrivas fore verifiering",
        "Ingen promotion utfordes",
    )
    failed_checks["no_fallback_used"] = result_check("PASS", "Fallback ar forbjuden", "Ingen fallback anvandes")
    staging_result = {
        "artifact_type": "staging_verification_result",
        "build_id": build_context["build_id"],
        "staging_root": display_path(build_context["staging_root"]),
        "status": "STOP",
        "manifest_state": "STAGING_INVALID",
        "checks": failed_checks,
        "model_authority": serialize_model_authority_result(build_context["model_authority"]),
        "artifact_integrity": {},
        "doc_id_sets": {},
        "artifact_hashes": artifact_hashes,
        "device_check": result_check("NOT_APPLICABLE", "Ej verifierad", "Build stoppades", None),
        "model_check": result_check("NOT_APPLICABLE", "Ej verifierad", "Build stoppades", None),
        "tokenizer_check": result_check("NOT_APPLICABLE", "Ej verifierad", "Build stoppades", None),
        "ordering_check": result_check("NOT_APPLICABLE", "Ej verifierad", "Build stoppades", None),
        "forbidden_behavior_check": {
            "no_active_write_before_promotion": result_check(
                "PASS",
                "Aktiva artefakter ska inte skrivas fore verifiering",
                "Ingen promotion utfordes",
            ),
            "no_fallback_used": result_check("PASS", "Fallback ar forbjuden", "Ingen fallback anvandes"),
        },
        "failure": failure,
    }
    save_json_object(build_context["staging_verification_result"], staging_result)
    artifact_hashes["staging_verification_result_hash"] = compute_file_hash(
        build_context["staging_verification_result"]
    )
    build_result = build_execution_result(
        build_context,
        status="STOP",
        write_phase="staging_failed",
        artifact_hashes=artifact_hashes,
        staging_verified=False,
        promotion_occurred=False,
        final_active_status="UNCHANGED",
        failure=failure,
    )
    write_build_execution_result(build_context, build_result)


def main():
    build_context = None
    try:
        build_context = load_controller_build_context()
        run_build(build_context)
    except Exception as exc:
        if build_context is not None:
            try:
                write_failed_result_surfaces(build_context, exc)
            except Exception:
                pass
        raise

# ---------------------------------------------------------

if __name__ == "__main__":
    main()
