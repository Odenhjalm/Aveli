from copy import deepcopy
import hashlib
import json
import os
import sys
import unicodedata
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"

if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
        f"{CANONICAL_SEARCH_PYTHON}"
    )

from sentence_transformers import SentenceTransformer
import chromadb
import numpy as np
from tqdm import tqdm

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------

ACTIVE_INDEX_ROOT = ROOT / ".repo_index"
STAGING_PARENT = ACTIVE_INDEX_ROOT / "_staging"
INDEX_MANIFEST = ACTIVE_INDEX_ROOT / "index_manifest.json"

# ---------------------------------------------------------
# Config
# ---------------------------------------------------------

COLLECTION_NAME = "aveli_repo"
APPROVAL_PHRASE = "APPROVE AVELI INDEX REBUILD"
CONTROLLER_MODE_ENV = "AVELI_RETRIEVAL_CONTROLLER_MODE"
APPROVAL_ENV = "AVELI_INDEX_REBUILD_APPROVAL"
BUILD_ID_ENV = "AVELI_INDEX_BUILD_ID"
PROMOTION_STOP_MESSAGE = "PROMOTION REQUIRES VERIFIED CONTROLLER PHASE"
MISSING_CONTROLLER_CONTEXT_MESSAGE = "BUILD REQUIRES CONTROLLER MODE + T14 APPROVAL"

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


def load_controller_build_context() -> dict:
    mode = os.environ.get(CONTROLLER_MODE_ENV, "").strip().lower()
    approval = os.environ.get(APPROVAL_ENV, "")
    build_id = validate_build_id(os.environ.get(BUILD_ID_ENV, ""))

    if mode != "build" or approval != APPROVAL_PHRASE:
        raise RuntimeError(MISSING_CONTROLLER_CONTEXT_MESSAGE)

    staging_root = STAGING_PARENT / build_id
    staging_parent = STAGING_PARENT.resolve()
    resolved_staging_root = staging_root.resolve()
    if not is_relative_to_path(resolved_staging_root, staging_parent):
        raise RuntimeError(MISSING_CONTROLLER_CONTEXT_MESSAGE)
    if staging_root.exists():
        raise RuntimeError("FEL: staging path finns redan och kraver explicit controller-cleanup")

    return {
        "build_id": build_id,
        "staging_root": staging_root,
        "index_manifest": staging_root / "index_manifest.json",
        "chunk_manifest": staging_root / "chunk_manifest.jsonl",
        "lexical_index_dir": staging_root / "lexical_index",
        "lexical_index_manifest": staging_root / "lexical_index" / "manifest.json",
        "lexical_index_documents": staging_root / "lexical_index" / "documents.jsonl",
        "vector_db_dir": staging_root / "chroma_db",
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


def save_json_object(path: Path, data: dict) -> None:
    assert_staging_write_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


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


def get_embedding_model_config(manifest: dict) -> dict:
    model_id = require_manifest_root_str(manifest, "embedding_model")
    rerank_model = require_manifest_root_str(manifest, "rerank_model")
    return {
        "local_files_only": True,
        "model_id": model_id,
        "model_revision": None,
        "model_snapshot_hash": "",
        "rerank_model": rerank_model,
        "tokenizer_files_hash": "",
        "trust_remote_code": False,
    }


def get_embedding_policy(manifest: dict) -> dict:
    get_embedding_model_config(manifest)
    return {
        "dtype": "float32",
        "embedding_dimension": 1024,
        "normalize_embeddings": True,
        "passage_prefix": "",
        "query_prefix": "query: ",
        "tolerance_absolute": 0.00001,
        "tolerance_relative": 0.00001,
    }


def resolve_manifest_build_device(manifest: dict) -> str:
    get_embedding_model_config(manifest)
    return "cpu"


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


def validate_index_manifest(
    manifest: dict,
    corpus_manifest_hash: str,
    *,
    require_chunk_manifest_hash: bool,
) -> None:
    missing = sorted(INDEX_MANIFEST_REQUIRED_FIELDS - set(manifest))
    if missing:
        raise RuntimeError(
            "FEL: index_manifest.json saknar fält: " + ", ".join(missing)
        )

    reject_deprecated_manifest_config(manifest)
    load_manifest_corpus_files(manifest)

    if str(manifest["contract_version"]) != CANONICAL_CONTRACT_VERSION:
        raise RuntimeError("FEL: contract_version matchar inte kanoniskt värde")
    if str(manifest["corpus_manifest_hash"]) != corpus_manifest_hash:
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
        model_config["model_id"],
        device=device,
        revision=model_config["model_revision"],
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
    artifact_hashes = deepcopy(finalized_manifest.get("artifact_hashes", {}))
    artifact_hashes["chroma_db"] = validate_sha256_hex(vector_export_hash, "vector_export_hash")
    finalized_manifest["artifact_hashes"] = artifact_hashes
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

def main():
    build_context = load_controller_build_context()
    staging_root = build_context["staging_root"]
    staging_index_manifest = build_context["index_manifest"]
    staging_chunk_manifest = build_context["chunk_manifest"]
    staging_lexical_index_dir = build_context["lexical_index_dir"]
    staging_lexical_index_manifest = build_context["lexical_index_manifest"]
    staging_lexical_index_documents = build_context["lexical_index_documents"]
    staging_vector_db_dir = build_context["vector_db_dir"]

    if not INDEX_MANIFEST.exists():
        raise RuntimeError(
            f"{INDEX_MANIFEST} saknas. Bygg repoindex först."
        )

    print("\n[STEG] Läser indexmanifest...")

    manifest = load_json_object(INDEX_MANIFEST)
    files = load_manifest_corpus_files(manifest)

    excluded_paths = [file for file in files if is_excluded_path(file)]
    if excluded_paths:
        raise RuntimeError(
            "index_manifest.json corpus.files innehaller exkluderade paths: "
            + ", ".join(excluded_paths[:5])
        )

    print(f"[INFO] {len(files)} filer hittades")

    corpus_manifest_hash = compute_corpus_manifest_hash(files)

    staging_root.mkdir(parents=True, exist_ok=False)

    validate_index_manifest(
        manifest,
        corpus_manifest_hash,
        require_chunk_manifest_hash=False,
    )

    staging_manifest = deepcopy(manifest)
    staging_manifest["manifest_state"] = "STAGING_INCOMPLETE"
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

    model_config = get_embedding_model_config(staging_manifest)
    embedding_policy = get_embedding_policy(staging_manifest)
    build_device = resolve_manifest_build_device(staging_manifest)
    batch_size = get_embedding_batch_size(staging_manifest)
    embedding_inputs = build_embedding_inputs(documents, embedding_policy)

    try:
        print("[STEG] Laddar CPU-baslinje for embedding-modell...")
        cpu_model = load_embedding_model(model_config, "cpu")
        cpu_embeddings = validate_embedding_matrix(
            encode_embeddings(cpu_model, embedding_inputs, embedding_policy, batch_size),
            expected_rows=len(documents),
            embedding_policy=embedding_policy,
        )
    except RuntimeError as e:
        raise RuntimeError("FEL: CPU-baslinje for embedding-modellen misslyckades") from e

    print(f"[INFO] Manifeststyrd build-enhet: {build_device}")
    print(f"[INFO] Manifestlast batchstorlek: {batch_size}")
    embeddings = cpu_embeddings

    if build_device != "cpu":
        try:
            print("[STEG] Verifierar accelererad embedding mot CPU-baslinje...")
            accelerated_model = load_embedding_model(model_config, build_device)
            accelerated_embeddings = validate_embedding_matrix(
                encode_embeddings(accelerated_model, embedding_inputs, embedding_policy, batch_size),
                expected_rows=len(documents),
                embedding_policy=embedding_policy,
            )
            assert_embedding_equivalence(cpu_embeddings, accelerated_embeddings, embedding_policy)
        except RuntimeError as e:
            raise RuntimeError(
                f"DEVICE_DRIFT: accelererad embedding pa {build_device} matchar inte CPU-baslinje"
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

    print("\n[KLAR] Staging-vektorindex byggt.")
    print(f"[INFO] Plats: {staging_vector_db_dir}")
    print(f"[INFO] Indexerade textblock: {len(documents)}")
    print(f"[INFO] vector_export_hash: {vector_export_hash}")
    raise RuntimeError(PROMOTION_STOP_MESSAGE)

# ---------------------------------------------------------

if __name__ == "__main__":
    main()
