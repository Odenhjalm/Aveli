import hashlib
import json
import math
import struct
from pathlib import Path


REQUIRED_INDEX_ARTIFACTS = {
    "index_manifest": "index_manifest.json",
    "chunk_manifest": "chunk_manifest.jsonl",
    "chroma_db": "chroma_db",
    "lexical_index": "lexical_index",
}
LEXICAL_INDEX_MANIFEST = "manifest.json"
LEXICAL_INDEX_DOCUMENTS = "documents.jsonl"
CANONICAL_LAYERS = {"LAW", "ROUTE", "SERVICE", "DB", "POLICY", "SCHEMA", "MODEL", "OTHER"}
REQUIRED_CHUNK_FIELDS = {
    "doc_id",
    "file",
    "chunk_index",
    "layer",
    "source_type",
    "content_hash",
}


class IndexArtifactIntegrityError(RuntimeError):
    pass


def canonical_json_dumps(data: object) -> str:
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def compute_sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def compute_sha256_text(content: str) -> str:
    return compute_sha256_bytes(content.encode("utf-8"))


def validate_sha256_hex(value: object, field_name: str) -> str:
    if not isinstance(value, str):
        raise IndexArtifactIntegrityError(f"FEL: {field_name} maste vara sha256-hex")
    digest = value.strip()
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise IndexArtifactIntegrityError(
            f"FEL: {field_name} maste vara 64 tecken lowercase sha256-hex"
        )
    return digest


def display_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def is_relative_to_path(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def require_string(container: dict, field_name: str, owner: str) -> str:
    value = container.get(field_name)
    if not isinstance(value, str) or not value.strip():
        raise IndexArtifactIntegrityError(
            f"FEL: {owner}.{field_name} maste vara en icke-tom strang"
        )
    return value.strip()


def require_int(container: dict, field_name: str, owner: str, *, minimum: int = 0) -> int:
    value = container.get(field_name)
    if not isinstance(value, int) or isinstance(value, bool):
        raise IndexArtifactIntegrityError(f"FEL: {owner}.{field_name} maste vara heltal")
    if value < minimum:
        raise IndexArtifactIntegrityError(
            f"FEL: {owner}.{field_name} maste vara minst {minimum}"
        )
    return value


def require_object(container: dict, field_name: str, owner: str) -> dict:
    value = container.get(field_name)
    if not isinstance(value, dict):
        raise IndexArtifactIntegrityError(
            f"FEL: {owner}.{field_name} maste vara ett JSON-objekt"
        )
    return value


def normalize_repo_relative_path(path_text: str, field_name: str = "file") -> str:
    if not isinstance(path_text, str) or not path_text.strip():
        raise IndexArtifactIntegrityError(
            f"FEL: {field_name} maste vara en icke-tom repo-relativ sokvag"
        )
    if "\\" in path_text:
        raise IndexArtifactIntegrityError(f"FEL: {field_name} maste anvanda forward slash")
    path = Path(path_text)
    if path.is_absolute() or ".." in path.parts:
        raise IndexArtifactIntegrityError(
            f"FEL: {field_name} maste vara repo-relativ utan parent traversal"
        )
    normalized = path.as_posix()
    if normalized.startswith("./"):
        normalized = normalized[2:]
    if normalized != path_text:
        raise IndexArtifactIntegrityError(f"FEL: {field_name} maste vara normaliserad")
    return normalized


def ensure_artifact_under_index_root(root: Path, index_root: Path, path: Path, expected_relative: str) -> None:
    resolved_index_root = index_root.resolve()
    resolved_path = path.resolve()
    if not is_relative_to_path(resolved_path, resolved_index_root):
        raise IndexArtifactIntegrityError(
            f"FEL: indexartefakt ligger utanfor indexroot: {display_path(root, path)}"
        )
    if resolved_path.relative_to(resolved_index_root).as_posix() != expected_relative:
        raise IndexArtifactIntegrityError(
            f"FEL: indexartefakt har fel kanonisk plats: {display_path(root, path)}"
        )


def require_file(root: Path, path: Path, label: str) -> None:
    if not path.exists() or not path.is_file():
        raise IndexArtifactIntegrityError(
            f"FEL: obligatorisk indexartefakt saknas: {label} vid {display_path(root, path)}"
        )


def require_dir(root: Path, path: Path, label: str) -> None:
    if not path.exists() or not path.is_dir():
        raise IndexArtifactIntegrityError(
            f"FEL: obligatorisk indexartefakt saknas: {label} vid {display_path(root, path)}"
        )


def validate_required_artifact_set(
    *,
    root: Path,
    index_root: Path,
    manifest_path: Path,
    chunk_manifest_path: Path,
    chroma_db_dir: Path,
    lexical_index_dir: Path,
) -> dict:
    if not index_root.exists() or not index_root.is_dir():
        raise IndexArtifactIntegrityError(
            f"FEL: kanonisk indexroot saknas vid {display_path(root, index_root)}"
        )
    ensure_artifact_under_index_root(root, index_root, manifest_path, "index_manifest.json")
    ensure_artifact_under_index_root(root, index_root, chunk_manifest_path, "chunk_manifest.jsonl")
    ensure_artifact_under_index_root(root, index_root, chroma_db_dir, "chroma_db")
    ensure_artifact_under_index_root(root, index_root, lexical_index_dir, "lexical_index")
    require_file(root, manifest_path, ".repo_index/index_manifest.json")
    require_file(root, chunk_manifest_path, ".repo_index/chunk_manifest.jsonl")
    require_dir(root, chroma_db_dir, ".repo_index/chroma_db/")
    require_dir(root, lexical_index_dir, ".repo_index/lexical_index/")
    require_file(root, lexical_index_dir / LEXICAL_INDEX_MANIFEST, "lexical_index/manifest.json")
    require_file(root, lexical_index_dir / LEXICAL_INDEX_DOCUMENTS, "lexical_index/documents.jsonl")
    return {
        name: {"path": display_path(root, index_root / relative_path), "status": "PASS"}
        for name, relative_path in REQUIRED_INDEX_ARTIFACTS.items()
    }


def load_json_object(path: Path, root: Path, label: str) -> dict:
    require_file(root, path, label)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise IndexArtifactIntegrityError(f"FEL: ogiltig JSON i {display_path(root, path)}") from exc
    if not isinstance(value, dict):
        raise IndexArtifactIntegrityError(
            f"FEL: JSON-objekt forvantas i {display_path(root, path)}"
        )
    return value


def load_jsonl_records(path: Path, root: Path, label: str) -> list[dict]:
    require_file(root, path, label)
    records = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            raise IndexArtifactIntegrityError(
                f"FEL: tom rad i JSONL-artefakt {display_path(root, path)} pa rad {line_number}"
            )
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise IndexArtifactIntegrityError(
                f"FEL: ogiltig JSONL-rad i {display_path(root, path)} pa rad {line_number}"
            ) from exc
        if not isinstance(value, dict):
            raise IndexArtifactIntegrityError(
                f"FEL: JSONL-rad i {display_path(root, path)} pa rad {line_number} ar inte objekt"
            )
        records.append(value)
    if not records:
        raise IndexArtifactIntegrityError(f"FEL: {label} far inte vara tom")
    return records


def validate_manifest_bindings(manifest: dict) -> dict:
    contract_version = require_string(manifest, "contract_version", "index_manifest")
    corpus_manifest_hash = validate_sha256_hex(
        require_string(manifest, "corpus_manifest_hash", "index_manifest"),
        "index_manifest.corpus_manifest_hash",
    )
    chunk_manifest_hash = validate_sha256_hex(
        require_string(manifest, "chunk_manifest_hash", "index_manifest"),
        "index_manifest.chunk_manifest_hash",
    )
    corpus = require_object(manifest, "corpus", "index_manifest")
    corpus_files = corpus.get("files")
    if not isinstance(corpus_files, list) or not corpus_files:
        raise IndexArtifactIntegrityError(
            "FEL: index_manifest.corpus.files maste vara en icke-tom lista"
        )
    normalized_files = []
    seen = set()
    for file_entry in corpus_files:
        normalized_file = normalize_repo_relative_path(file_entry, "index_manifest.corpus.files")
        if normalized_file in seen:
            raise IndexArtifactIntegrityError(
                f"FEL: duplicerad corpusfil i index_manifest.corpus.files: {normalized_file}"
            )
        normalized_files.append(normalized_file)
        seen.add(normalized_file)
    if normalized_files != sorted(normalized_files, key=lambda item: item.encode("utf-8")):
        raise IndexArtifactIntegrityError(
            "FEL: index_manifest.corpus.files maste vara sorterad enligt UTF-8 byteordning"
        )
    return {
        "contract_version": contract_version,
        "corpus_manifest_hash": corpus_manifest_hash,
        "chunk_manifest_hash": chunk_manifest_hash,
        "corpus_files": normalized_files,
    }


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
        raise IndexArtifactIntegrityError("FEL: chunk_manifest.jsonl far inte vara tom")
    return "".join(canonical_json_dumps(record) + "\n" for record in ordered_records)


def compute_chunk_manifest_hash(records: list[dict]) -> str:
    return compute_sha256_text(render_chunk_manifest(records))


def build_doc_id_payload(contract_version: str, file_path: str, chunk_index: int, content_hash: str) -> bytes:
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


def build_canonical_doc_id(contract_version: str, file_path: str, chunk_index: int, content_hash: str) -> str:
    return compute_sha256_bytes(
        build_doc_id_payload(contract_version, file_path, chunk_index, content_hash)
    )


def compute_doc_id_set_hash(doc_ids: list[str]) -> str:
    for doc_id in doc_ids:
        validate_sha256_hex(doc_id, "doc_id")
    canonical_bytes = "".join(doc_id + "\n" for doc_id in sorted(doc_ids)).encode("ascii")
    return compute_sha256_bytes(canonical_bytes)


def validate_chunk_manifest_records(manifest_bindings: dict, records: list[dict]) -> dict:
    if records != order_chunk_records(records):
        raise IndexArtifactIntegrityError("FEL: chunk_manifest.jsonl ar inte kanoniskt sorterad")
    contract_version = manifest_bindings["contract_version"]
    corpus_manifest_hash = manifest_bindings["corpus_manifest_hash"]
    expected_chunk_manifest_hash = manifest_bindings["chunk_manifest_hash"]
    corpus_files = set(manifest_bindings["corpus_files"])
    seen_doc_ids: set[str] = set()
    chunk_indices_by_file: dict[str, list[int]] = {}

    for record in records:
        missing = sorted(REQUIRED_CHUNK_FIELDS - set(record))
        if missing:
            raise IndexArtifactIntegrityError(
                "FEL: chunk_manifest.jsonl saknar obligatoriska falt: " + ", ".join(missing)
            )
        doc_id = validate_sha256_hex(record["doc_id"], "chunk_manifest.doc_id")
        if doc_id in seen_doc_ids:
            raise IndexArtifactIntegrityError(f"FEL: duplicerat doc_id i chunk_manifest.jsonl: {doc_id}")
        seen_doc_ids.add(doc_id)
        file_path = normalize_repo_relative_path(str(record["file"]), "chunk_manifest.file")
        if file_path != record["file"]:
            raise IndexArtifactIntegrityError("FEL: chunk_manifest.file maste vara normaliserad")
        if file_path not in corpus_files:
            raise IndexArtifactIntegrityError(
                f"FEL: chunk_manifest.file saknas i index_manifest.corpus.files: {file_path}"
            )
        chunk_index = require_int(record, "chunk_index", "chunk_manifest", minimum=0)
        layer = require_string(record, "layer", "chunk_manifest").upper()
        if layer not in CANONICAL_LAYERS:
            raise IndexArtifactIntegrityError("FEL: chunk_manifest.layer ar inte ett kanoniskt lager")
        if require_string(record, "source_type", "chunk_manifest") != "chunk":
            raise IndexArtifactIntegrityError("FEL: chunk_manifest.source_type maste vara chunk")
        content_hash = validate_sha256_hex(record["content_hash"], "chunk_manifest.content_hash")
        if "text" in record:
            if not isinstance(record["text"], str):
                raise IndexArtifactIntegrityError("FEL: chunk_manifest.text maste vara strang")
            if compute_sha256_text(record["text"]) != content_hash:
                raise IndexArtifactIntegrityError("FEL: chunk_manifest.content_hash matchar inte chunktext")
        if require_string(record, "contract_version", "chunk_manifest") != contract_version:
            raise IndexArtifactIntegrityError("FEL: chunk_manifest.contract_version matchar inte index_manifest")
        record_corpus_hash = validate_sha256_hex(
            require_string(record, "corpus_manifest_hash", "chunk_manifest"),
            "chunk_manifest.corpus_manifest_hash",
        )
        if record_corpus_hash != corpus_manifest_hash:
            raise IndexArtifactIntegrityError(
                "FEL: chunk_manifest.corpus_manifest_hash matchar inte index_manifest"
            )
        expected_doc_id = build_canonical_doc_id(contract_version, file_path, chunk_index, content_hash)
        if doc_id != expected_doc_id:
            raise IndexArtifactIntegrityError("FEL: chunk_manifest.doc_id matchar inte kanonisk formel")
        chunk_indices_by_file.setdefault(file_path, []).append(chunk_index)

    for file_path, indices in chunk_indices_by_file.items():
        if indices != list(range(len(indices))):
            raise IndexArtifactIntegrityError(f"FEL: chunk_index har luckor eller fel start for {file_path}")
    actual_chunk_manifest_hash = compute_chunk_manifest_hash(records)
    if actual_chunk_manifest_hash != expected_chunk_manifest_hash:
        raise IndexArtifactIntegrityError(
            "FEL: index_manifest.chunk_manifest_hash matchar inte chunk_manifest.jsonl"
        )
    ordered_doc_ids = [str(record["doc_id"]) for record in records]
    return {
        "record_count": len(records),
        "chunk_manifest_hash": actual_chunk_manifest_hash,
        "doc_id_set_hash": compute_doc_id_set_hash(ordered_doc_ids),
        "ordered_doc_ids": ordered_doc_ids,
        "records_by_doc_id": {str(record["doc_id"]): record for record in records},
    }


def normalize_document_text(text: str) -> str:
    return text.strip()


def tokenize_for_lexical(text: str) -> list[str]:
    return normalize_document_text(text).lower().split()


def compute_term_freqs(tokens: list[str]) -> dict[str, int]:
    term_freqs: dict[str, int] = {}
    for token in tokens:
        term_freqs[token] = term_freqs.get(token, 0) + 1
    return term_freqs


def validate_lexical_index(
    *,
    manifest_bindings: dict,
    lexical_manifest: dict,
    lexical_records: list[dict],
    ordered_doc_ids: list[str],
) -> dict:
    contract_version = manifest_bindings["contract_version"]
    corpus_manifest_hash = manifest_bindings["corpus_manifest_hash"]
    chunk_manifest_hash = manifest_bindings["chunk_manifest_hash"]
    expected_doc_ids = set(ordered_doc_ids)

    if require_string(lexical_manifest, "contract_version", "lexical_index") != contract_version:
        raise IndexArtifactIntegrityError("FEL: lexical_index.contract_version matchar inte index_manifest")
    lexical_corpus_hash = validate_sha256_hex(
        require_string(lexical_manifest, "corpus_manifest_hash", "lexical_index"),
        "lexical_index.corpus_manifest_hash",
    )
    if lexical_corpus_hash != corpus_manifest_hash:
        raise IndexArtifactIntegrityError("FEL: lexical_index.corpus_manifest_hash matchar inte index_manifest")
    lexical_chunk_hash = validate_sha256_hex(
        require_string(lexical_manifest, "chunk_manifest_hash", "lexical_index"),
        "lexical_index.chunk_manifest_hash",
    )
    if lexical_chunk_hash != chunk_manifest_hash:
        raise IndexArtifactIntegrityError("FEL: lexical_index.chunk_manifest_hash matchar inte index_manifest")
    doc_count = require_int(lexical_manifest, "doc_count", "lexical_index", minimum=1)
    if doc_count != len(ordered_doc_ids):
        raise IndexArtifactIntegrityError("FEL: lexical_index.doc_count matchar inte chunkmanifest")

    lexical_doc_ids = lexical_manifest.get("doc_ids")
    if not isinstance(lexical_doc_ids, list):
        raise IndexArtifactIntegrityError("FEL: lexical_index.doc_ids maste vara en lista")
    normalized_lexical_doc_ids = [
        validate_sha256_hex(doc_id, "lexical_index.doc_ids")
        for doc_id in lexical_doc_ids
    ]
    if normalized_lexical_doc_ids != ordered_doc_ids:
        raise IndexArtifactIntegrityError("FEL: lexical_index.doc_ids matchar inte kanonisk chunkordning")
    if len(lexical_records) != len(ordered_doc_ids):
        raise IndexArtifactIntegrityError("FEL: lexical_index/documents.jsonl antal matchar inte chunkmanifest")

    document_frequency = lexical_manifest.get("document_frequency")
    if not isinstance(document_frequency, dict):
        raise IndexArtifactIntegrityError("FEL: lexical_index.document_frequency maste vara ett JSON-objekt")

    recomputed_document_frequency: dict[str, int] = {}
    recomputed_lengths = []
    records_doc_ids = []
    seen_doc_ids = set()
    for expected_doc_id, record in zip(ordered_doc_ids, lexical_records):
        doc_id = validate_sha256_hex(record.get("doc_id"), "lexical_index.documents.doc_id")
        if doc_id != expected_doc_id:
            raise IndexArtifactIntegrityError("FEL: lexical_index/documents.jsonl foljer inte kanonisk chunkordning")
        if doc_id in seen_doc_ids:
            raise IndexArtifactIntegrityError(f"FEL: duplicerat doc_id i lexical_index/documents.jsonl: {doc_id}")
        seen_doc_ids.add(doc_id)
        if doc_id not in expected_doc_ids:
            raise IndexArtifactIntegrityError("FEL: lexical_index/documents.jsonl innehaller okant doc_id")
        text = record.get("text")
        if not isinstance(text, str):
            raise IndexArtifactIntegrityError("FEL: lexical_index/documents.jsonl text maste vara strang")
        tokens = tokenize_for_lexical(text)
        expected_term_freqs = compute_term_freqs(tokens)
        if record.get("term_freqs") != expected_term_freqs:
            raise IndexArtifactIntegrityError(
                "FEL: lexical_index term_freqs matchar inte deterministisk tokenisering"
            )
        length = require_int(record, "length", "lexical_index.documents", minimum=0)
        if length != len(tokens):
            raise IndexArtifactIntegrityError(
                "FEL: lexical_index length matchar inte deterministisk tokenisering"
            )
        for token in expected_term_freqs:
            recomputed_document_frequency[token] = recomputed_document_frequency.get(token, 0) + 1
        recomputed_lengths.append(length)
        records_doc_ids.append(doc_id)

    if records_doc_ids != ordered_doc_ids:
        raise IndexArtifactIntegrityError("FEL: lexical_index/documents.jsonl doc_id-set matchar inte chunkmanifest")
    if document_frequency != recomputed_document_frequency:
        raise IndexArtifactIntegrityError(
            "FEL: lexical_index.document_frequency matchar inte deterministisk tokenisering"
        )
    avg_doc_length = lexical_manifest.get("avg_doc_length")
    if not isinstance(avg_doc_length, (int, float)) or isinstance(avg_doc_length, bool):
        raise IndexArtifactIntegrityError("FEL: lexical_index.avg_doc_length maste vara tal")
    expected_avg_doc_length = sum(recomputed_lengths) / len(recomputed_lengths)
    if float(avg_doc_length) != float(expected_avg_doc_length):
        raise IndexArtifactIntegrityError(
            "FEL: lexical_index.avg_doc_length matchar inte deterministisk tokenisering"
        )
    return {
        "doc_count": len(ordered_doc_ids),
        "doc_id_set_hash": compute_doc_id_set_hash(ordered_doc_ids),
        "tokenization_authority": "lexical_index/documents.jsonl",
    }


def coerce_sequence(value: object, field_name: str) -> list:
    if value is None or isinstance(value, (str, bytes)):
        raise IndexArtifactIntegrityError(f"FEL: vektorindex saknar {field_name}")
    try:
        return list(value)
    except TypeError as exc:
        raise IndexArtifactIntegrityError(f"FEL: vektorindex {field_name} ar inte en lista") from exc


def vector_as_float_list(embedding: object) -> list[float]:
    values = coerce_sequence(embedding, "embeddings")
    vector = []
    for value in values:
        try:
            number = float(value)
        except (TypeError, ValueError) as exc:
            raise IndexArtifactIntegrityError("FEL: embeddingvektor innehaller ogiltigt tal") from exc
        if not math.isfinite(number):
            raise IndexArtifactIntegrityError("FEL: embeddingvektor innehaller NaN eller infinity")
        vector.append(number)
    if not vector:
        raise IndexArtifactIntegrityError("FEL: embeddingvektor far inte vara tom")
    return vector


def compute_embedding_vector_hash(embedding: object) -> str:
    vector = vector_as_float_list(embedding)
    return compute_sha256_bytes(b"".join(struct.pack("<f", value) for value in vector))


def read_vector_collection(collection) -> dict:
    try:
        result = collection.get(include=["documents", "embeddings", "metadatas"])
    except Exception as exc:
        raise IndexArtifactIntegrityError(
            "FEL: vektorindexet kan inte exportera dokument, embeddings och metadata"
        ) from exc
    if not isinstance(result, dict):
        raise IndexArtifactIntegrityError("FEL: vektorindexexport ar inte ett JSON-objekt")
    return result


def validate_vector_index(
    *,
    manifest_bindings: dict,
    collection,
    chunk_records_by_doc_id: dict[str, dict],
    ordered_doc_ids: list[str],
) -> dict:
    collection_metadata = collection.metadata
    if not isinstance(collection_metadata, dict):
        raise IndexArtifactIntegrityError("FEL: vektorindex saknar metadata")
    if collection_metadata.get("artifact_type") != "chroma_vector_index":
        raise IndexArtifactIntegrityError("FEL: vektorindex har fel artifact_type")

    contract_version = manifest_bindings["contract_version"]
    corpus_manifest_hash = manifest_bindings["corpus_manifest_hash"]
    chunk_manifest_hash = manifest_bindings["chunk_manifest_hash"]
    expected_doc_ids = set(ordered_doc_ids)
    if require_string(collection_metadata, "contract_version", "chroma_db") != contract_version:
        raise IndexArtifactIntegrityError("FEL: chroma_db.contract_version matchar inte index_manifest")
    vector_corpus_hash = validate_sha256_hex(
        require_string(collection_metadata, "corpus_manifest_hash", "chroma_db"),
        "chroma_db.corpus_manifest_hash",
    )
    if vector_corpus_hash != corpus_manifest_hash:
        raise IndexArtifactIntegrityError("FEL: chroma_db.corpus_manifest_hash matchar inte index_manifest")
    vector_chunk_hash = validate_sha256_hex(
        require_string(collection_metadata, "chunk_manifest_hash", "chroma_db"),
        "chroma_db.chunk_manifest_hash",
    )
    if vector_chunk_hash != chunk_manifest_hash:
        raise IndexArtifactIntegrityError("FEL: chroma_db.chunk_manifest_hash matchar inte index_manifest")
    doc_count = require_int(collection_metadata, "doc_count", "chroma_db", minimum=1)
    if doc_count != len(ordered_doc_ids):
        raise IndexArtifactIntegrityError("FEL: chroma_db.doc_count matchar inte chunkmanifest")
    expected_doc_id_set_hash = compute_doc_id_set_hash(ordered_doc_ids)
    metadata_doc_id_set_hash = validate_sha256_hex(
        require_string(collection_metadata, "doc_id_set_hash", "chroma_db"),
        "chroma_db.doc_id_set_hash",
    )
    if metadata_doc_id_set_hash != expected_doc_id_set_hash:
        raise IndexArtifactIntegrityError("FEL: chroma_db.doc_id_set_hash matchar inte chunkmanifest")
    embedding_dimension = require_int(collection_metadata, "embedding_dimension", "chroma_db", minimum=1)

    try:
        actual_collection_count = int(collection.count())
    except Exception as exc:
        raise IndexArtifactIntegrityError("FEL: vektorindexet kan inte redovisa vector count") from exc
    if actual_collection_count != len(ordered_doc_ids):
        raise IndexArtifactIntegrityError("FEL: vektorindexets count matchar inte chunkmanifest")

    result = read_vector_collection(collection)
    vector_ids = [validate_sha256_hex(doc_id, "chroma_db.ids") for doc_id in coerce_sequence(result.get("ids"), "ids")]
    documents = coerce_sequence(result.get("documents"), "documents")
    metadatas = coerce_sequence(result.get("metadatas"), "metadatas")
    embeddings = coerce_sequence(result.get("embeddings"), "embeddings")
    if len(vector_ids) != len(documents) or len(vector_ids) != len(metadatas) or len(vector_ids) != len(embeddings):
        raise IndexArtifactIntegrityError("FEL: vektorindexets ids/dokument/metadata/embedding-antal matchar inte")
    if len(vector_ids) != len(ordered_doc_ids):
        raise IndexArtifactIntegrityError("FEL: vektorindexets vectorantal matchar inte chunkmanifest")
    if len(set(vector_ids)) != len(vector_ids):
        raise IndexArtifactIntegrityError("FEL: vektorindexet innehaller duplicerade doc_id")
    if set(vector_ids) != expected_doc_ids:
        raise IndexArtifactIntegrityError("FEL: vektorindexets doc_id-set matchar inte chunkmanifest")

    for doc_id, document, metadata, embedding in zip(vector_ids, documents, metadatas, embeddings):
        if not isinstance(metadata, dict):
            raise IndexArtifactIntegrityError("FEL: vektorindex metadata saknas")
        metadata_doc_id = validate_sha256_hex(metadata.get("doc_id"), "chroma_db.metadata.doc_id")
        if metadata_doc_id != doc_id:
            raise IndexArtifactIntegrityError("FEL: vektorindex metadata.doc_id matchar inte vector-id")
        if doc_id not in chunk_records_by_doc_id:
            raise IndexArtifactIntegrityError("FEL: vektorindex innehaller orphan doc_id")
        chunk_record = chunk_records_by_doc_id[doc_id]
        for field_name in ("file", "content_hash", "contract_version", "corpus_manifest_hash", "source_type", "layer"):
            if str(metadata.get(field_name, "")) != str(chunk_record[field_name]):
                raise IndexArtifactIntegrityError(
                    f"FEL: vektorindex metadata matchar inte chunkmanifest for {field_name}"
                )
        if require_int(metadata, "chunk_index", "chroma_db.metadata", minimum=0) != int(chunk_record["chunk_index"]):
            raise IndexArtifactIntegrityError("FEL: vektorindex metadata.chunk_index matchar inte chunkmanifest")
        metadata_chunk_hash = validate_sha256_hex(
            require_string(metadata, "chunk_manifest_hash", "chroma_db.metadata"),
            "chroma_db.metadata.chunk_manifest_hash",
        )
        if metadata_chunk_hash != chunk_manifest_hash:
            raise IndexArtifactIntegrityError(
                "FEL: vektorindex metadata.chunk_manifest_hash matchar inte index_manifest"
            )
        vector = vector_as_float_list(embedding)
        if len(vector) != embedding_dimension:
            raise IndexArtifactIntegrityError("FEL: embedding_dimension matchar inte vektorlangd")
        if require_int(metadata, "embedding_dimension", "chroma_db.metadata", minimum=1) != embedding_dimension:
            raise IndexArtifactIntegrityError(
                "FEL: vektorindex metadata.embedding_dimension matchar inte samlingsmetadata"
            )
        if "embedding_vector_hash" in metadata:
            actual_vector_hash = compute_embedding_vector_hash(embedding)
            expected_vector_hash = validate_sha256_hex(
                metadata["embedding_vector_hash"],
                "chroma_db.metadata.embedding_vector_hash",
            )
            if actual_vector_hash != expected_vector_hash:
                raise IndexArtifactIntegrityError(
                    "FEL: vektorindex embedding_vector_hash matchar inte lagrad vektor"
                )
        if not isinstance(document, str):
            raise IndexArtifactIntegrityError("FEL: vektorindex dokumenttext maste vara strang")
        if compute_sha256_text(document) != str(chunk_record["content_hash"]):
            raise IndexArtifactIntegrityError(
                "FEL: vektorindex dokumenttext matchar inte chunkmanifest.content_hash"
            )

    return {
        "doc_count": len(vector_ids),
        "doc_id_set_hash": expected_doc_id_set_hash,
        "embedding_dimension": embedding_dimension,
    }


def validate_index_artifact_integrity(
    *,
    root: Path,
    index_root: Path,
    manifest_path: Path,
    chunk_manifest_path: Path,
    chroma_db_dir: Path,
    lexical_index_dir: Path,
    collection,
) -> dict:
    artifact_set = validate_required_artifact_set(
        root=root,
        index_root=index_root,
        manifest_path=manifest_path,
        chunk_manifest_path=chunk_manifest_path,
        chroma_db_dir=chroma_db_dir,
        lexical_index_dir=lexical_index_dir,
    )
    manifest = load_json_object(manifest_path, root, ".repo_index/index_manifest.json")
    manifest_bindings = validate_manifest_bindings(manifest)
    chunk_records = load_jsonl_records(chunk_manifest_path, root, ".repo_index/chunk_manifest.jsonl")
    chunk_report = validate_chunk_manifest_records(manifest_bindings, chunk_records)
    lexical_manifest = load_json_object(
        lexical_index_dir / LEXICAL_INDEX_MANIFEST,
        root,
        "lexical_index/manifest.json",
    )
    lexical_records = load_jsonl_records(
        lexical_index_dir / LEXICAL_INDEX_DOCUMENTS,
        root,
        "lexical_index/documents.jsonl",
    )
    lexical_report = validate_lexical_index(
        manifest_bindings=manifest_bindings,
        lexical_manifest=lexical_manifest,
        lexical_records=lexical_records,
        ordered_doc_ids=chunk_report["ordered_doc_ids"],
    )
    vector_report = validate_vector_index(
        manifest_bindings=manifest_bindings,
        collection=collection,
        chunk_records_by_doc_id=chunk_report["records_by_doc_id"],
        ordered_doc_ids=chunk_report["ordered_doc_ids"],
    )
    return {
        "status": "PASS",
        "artifact_set": artifact_set,
        "manifest": manifest,
        "chunk_records": chunk_records,
        "chunk_manifest": {
            "record_count": chunk_report["record_count"],
            "chunk_manifest_hash": chunk_report["chunk_manifest_hash"],
            "doc_id_set_hash": chunk_report["doc_id_set_hash"],
        },
        "lexical_manifest": lexical_manifest,
        "lexical_records": lexical_records,
        "lexical_index": lexical_report,
        "vector_index": vector_report,
    }
