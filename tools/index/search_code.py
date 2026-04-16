import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"

if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
        f"{CANONICAL_SEARCH_PYTHON}"
    )

from chromadb import PersistentClient

# ---------------------------------------------------------
# CONFIG
# ---------------------------------------------------------

INDEX_MANIFEST = ROOT / ".repo_index" / "index_manifest.json"
DB_PATH = str(ROOT / ".repo_index" / "chroma_db")
CHUNK_MANIFEST = ROOT / ".repo_index" / "chunk_manifest.jsonl"
LEXICAL_INDEX_DIR = ROOT / ".repo_index" / "lexical_index"
LEXICAL_INDEX_MANIFEST = LEXICAL_INDEX_DIR / "manifest.json"
LEXICAL_INDEX_DOCUMENTS = LEXICAL_INDEX_DIR / "documents.jsonl"
COLLECTION_NAME = "aveli_repo"
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

MAX_CONTEXT_CHARS = 2500
BM25_K1 = 1.5
BM25_B = 0.75
MODEL_INIT_FORBIDDEN_MESSAGE = "MODEL INITIALIZATION FORBIDDEN IN QUERY MODE"
SOURCE_ACCESS_FORBIDDEN_MESSAGE = "SOURCE ACCESS FORBIDDEN IN QUERY MODE"

SEARCHABLE_SUFFIXES = {
    ".css",
    ".csv",
    ".dart",
    ".go",
    ".graphql",
    ".html",
    ".ini",
    ".js",
    ".json",
    ".jsx",
    ".kt",
    ".md",
    ".mjs",
    ".py",
    ".rb",
    ".scss",
    ".sh",
    ".sql",
    ".svg",
    ".swift",
    ".toml",
    ".ts",
    ".tsx",
    ".txt",
    ".yaml",
    ".yml",
}

SEARCHABLE_FILENAMES = {
    ".gitignore",
    "dockerfile",
    "makefile",
    "procfile",
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

_RUNTIME_STATE = None


def load_json_object(path: Path) -> dict:
    if not path.exists():
        return {}

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"FEL: JSON-objekt forvantas i {path}")
    return data


def validate_manifest_corpus_files(manifest: dict) -> None:
    corpus = manifest.get("corpus")
    if not isinstance(corpus, dict):
        raise SystemExit("FEL: indexmanifest corpus maste vara ett JSON-objekt")

    files = corpus.get("files")
    if not isinstance(files, list) or not files:
        raise SystemExit("FEL: indexmanifest corpus.files maste vara en icke-tom lista")

    seen: set[str] = set()
    normalized_files: list[str] = []
    for entry in files:
        if not isinstance(entry, str) or not entry:
            raise SystemExit("FEL: corpus.files far endast innehalla icke-tomma strangsokvagar")
        if "\\" in entry:
            raise SystemExit(f"FEL: corpus.files maste anvanda forward slash: {entry}")
        path = Path(entry)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"FEL: ogiltig repo-relativ corpusfil: {entry}")

        normalized = path.as_posix()
        if normalized.startswith("./"):
            normalized = normalized[2:]
        if normalized != entry:
            raise SystemExit(f"FEL: corpus.files maste vara normaliserad: {entry}")
        if normalized in seen:
            raise SystemExit(f"FEL: duplicerad corpusfil i indexmanifestet: {normalized}")

        normalized_files.append(normalized)
        seen.add(normalized)

    if normalized_files != sorted(normalized_files, key=lambda item: item.encode("utf-8")):
        raise SystemExit("FEL: corpus.files maste vara sorterad enligt UTF-8 byteordning")


def reject_deprecated_manifest_config(manifest: dict) -> None:
    present = sorted(DEPRECATED_MANIFEST_CONFIG_FIELDS & set(manifest))
    if present:
        raise SystemExit(
            "FEL: indexmanifest innehaller foraldrade config-falt: "
            + ", ".join(present)
        )


def require_manifest_root_str(manifest: dict, field_name: str) -> str:
    value = manifest.get(field_name)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"FEL: indexmanifest {field_name} maste vara en icke-tom strang")
    return value


def require_manifest_root_int(manifest: dict, field_name: str) -> int:
    value = manifest.get(field_name)
    if not isinstance(value, int) or isinstance(value, bool):
        raise SystemExit(f"FEL: indexmanifest {field_name} maste vara heltal")
    if value <= 0:
        raise SystemExit(f"FEL: indexmanifest {field_name} maste vara positivt")
    return value


def validate_flat_manifest_fields(manifest: dict) -> None:
    require_manifest_root_str(manifest, "contract_version")
    require_manifest_root_str(manifest, "corpus_manifest_hash")
    require_manifest_root_str(manifest, "chunk_manifest_hash")
    require_manifest_root_str(manifest, "embedding_model")
    require_manifest_root_str(manifest, "rerank_model")
    chunk_size = require_manifest_root_int(manifest, "chunk_size")
    chunk_overlap = require_manifest_root_int(manifest, "chunk_overlap")
    if chunk_overlap >= chunk_size:
        raise SystemExit("FEL: indexmanifest chunk_overlap maste vara mindre an chunk_size")
    require_manifest_root_int(manifest, "top_k")
    require_manifest_root_int(manifest, "vector_candidate_k")
    require_manifest_root_int(manifest, "lexical_candidate_k")
    if not isinstance(manifest.get("classification_policy"), dict):
        raise SystemExit("FEL: classification_policy saknas i indexmanifestet")


def load_index_manifest() -> dict:
    if not INDEX_MANIFEST.exists():
        raise SystemExit(f"FEL: indexmanifest saknas vid {INDEX_MANIFEST}")

    manifest = load_json_object(INDEX_MANIFEST)
    missing = sorted(INDEX_MANIFEST_REQUIRED_FIELDS - set(manifest))
    if missing:
        raise SystemExit(
            "FEL: indexmanifest saknar falt: " + ", ".join(missing)
        )
    reject_deprecated_manifest_config(manifest)
    validate_flat_manifest_fields(manifest)
    validate_manifest_corpus_files(manifest)
    return manifest


def validate_canonical_index_health() -> None:
    required_files = [
        INDEX_MANIFEST,
        CHUNK_MANIFEST,
        LEXICAL_INDEX_MANIFEST,
        LEXICAL_INDEX_DOCUMENTS,
    ]
    for path in required_files:
        if not path.exists() or not path.is_file():
            raise SystemExit(f"FEL: kanonisk indexartefakt saknas vid {path}")

    vector_db_path = Path(DB_PATH)
    if not vector_db_path.exists() or not vector_db_path.is_dir():
        raise SystemExit(f"FEL: kanonisk vektorartefakt saknas vid {vector_db_path}")

    if not LEXICAL_INDEX_DIR.exists() or not LEXICAL_INDEX_DIR.is_dir():
        raise SystemExit(f"FEL: kanonisk lexical-index saknas vid {LEXICAL_INDEX_DIR}")


def normalize_query(raw_query: str) -> str:
    return " ".join(raw_query.strip().lower().split())


def require_query_model_surface() -> None:
    raise SystemExit(MODEL_INIT_FORBIDDEN_MESSAGE)


def normalize_document_text(text: str) -> str:
    return text.removeprefix("passage: ").strip()


def tokenize_for_bm25(text: str) -> list[str]:
    return normalize_document_text(text).lower().split()


def load_lexical_index() -> tuple[dict, list[dict]]:
    if not LEXICAL_INDEX_MANIFEST.exists():
        raise SystemExit(f"FEL: lexical-indexmanifest saknas vid {LEXICAL_INDEX_MANIFEST}")
    if not LEXICAL_INDEX_DOCUMENTS.exists():
        raise SystemExit(f"FEL: lexical-indexdokument saknas vid {LEXICAL_INDEX_DOCUMENTS}")

    manifest = load_json_object(LEXICAL_INDEX_MANIFEST)
    records = [
        json.loads(line)
        for line in LEXICAL_INDEX_DOCUMENTS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    return manifest, records


def load_chunk_manifest_records() -> list[dict]:
    if not CHUNK_MANIFEST.exists():
        raise SystemExit(f"FEL: chunkmanifest saknas vid {CHUNK_MANIFEST}")

    return [
        json.loads(line)
        for line in CHUNK_MANIFEST.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def compute_chunk_manifest_hash(records: list[dict]) -> str:
    ordered_records = sorted(
        records,
        key=lambda record: (
            str(record["file"]),
            int(record["chunk_index"]),
            str(record["doc_id"]),
        ),
    )
    serialized = "\n".join(
        json.dumps(record, ensure_ascii=False, sort_keys=True)
        for record in ordered_records
    )
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()


def validate_contract_version_bindings(index_manifest: dict, chunk_records: list[dict], lexical_manifest: dict, collection) -> None:
    contract_version = str(index_manifest["contract_version"])
    chunk_manifest_hash = str(index_manifest["chunk_manifest_hash"])

    lexical_contract_version = str(lexical_manifest.get("contract_version", ""))
    if lexical_contract_version != contract_version:
        raise SystemExit(
            "FEL: lexical-indexens contract_version matchar inte indexmanifestet"
        )
    lexical_chunk_manifest_hash = str(lexical_manifest.get("chunk_manifest_hash", ""))
    if lexical_chunk_manifest_hash != chunk_manifest_hash:
        raise SystemExit(
            "FEL: lexical-indexens chunk_manifest_hash matchar inte indexmanifestet"
        )

    chunk_contract_versions = {str(record.get("contract_version", "")) for record in chunk_records}
    if chunk_contract_versions != {contract_version}:
        raise SystemExit(
            "FEL: chunkmanifestets contract_version matchar inte indexmanifestet"
        )
    actual_chunk_manifest_hash = compute_chunk_manifest_hash(chunk_records)
    if actual_chunk_manifest_hash != chunk_manifest_hash:
        raise SystemExit(
            "FEL: chunkmanifestets chunk_manifest_hash matchar inte indexmanifestet"
        )

    collection_contract_version = str((collection.metadata or {}).get("contract_version", ""))
    if collection_contract_version != contract_version:
        raise SystemExit(
            "FEL: vektorindexets contract_version matchar inte indexmanifestet"
        )
    collection_chunk_manifest_hash = str((collection.metadata or {}).get("chunk_manifest_hash", ""))
    if collection_chunk_manifest_hash != chunk_manifest_hash:
        raise SystemExit(
            "FEL: vektorindexets chunk_manifest_hash matchar inte indexmanifestet"
        )


def load_runtime_state() -> dict:
    global _RUNTIME_STATE

    if _RUNTIME_STATE is not None:
        return _RUNTIME_STATE

    validate_canonical_index_health()
    index_manifest = load_index_manifest()
    lexical_manifest, lexical_records = load_lexical_index()
    chunk_records = load_chunk_manifest_records()
    client = PersistentClient(path=DB_PATH)
    collection = client.get_collection(COLLECTION_NAME)
    validate_contract_version_bindings(
        index_manifest=index_manifest,
        chunk_records=chunk_records,
        lexical_manifest=lexical_manifest,
        collection=collection,
    )

    _RUNTIME_STATE = {
        "index_manifest": index_manifest,
        "lexical_manifest": lexical_manifest,
        "lexical_records": lexical_records,
        "chunk_records": chunk_records,
        "collection": collection,
    }
    return _RUNTIME_STATE


def preflight_runtime_prerequisites() -> None:
    validate_canonical_index_health()
    index_manifest = load_index_manifest()
    lexical_manifest, _ = load_lexical_index()
    chunk_records = load_chunk_manifest_records()

    try:
        client = PersistentClient(path=DB_PATH)
        collection = client.get_collection(COLLECTION_NAME)
    except Exception as exc:
        raise SystemExit(
            f"FEL: vektorindexets samling saknas eller kan inte öppnas i {DB_PATH}"
        ) from exc

    validate_contract_version_bindings(
        index_manifest=index_manifest,
        chunk_records=chunk_records,
        lexical_manifest=lexical_manifest,
        collection=collection,
    )


def lexical_search(query_text: str, lexical_records: list[dict], lexical_manifest: dict, top_n: int) -> list[str]:
    query_tokens = tokenize_for_bm25(query_text)
    if not query_tokens:
        return []

    total_docs = int(lexical_manifest.get("doc_count", 0))
    avg_doc_length = float(lexical_manifest.get("avg_doc_length", 0.0)) or 1.0
    document_frequency = lexical_manifest.get("document_frequency", {})

    scored: list[tuple[str, float]] = []

    for record in lexical_records:
        doc_id = str(record.get("doc_id", ""))
        length = max(1, int(record.get("length", 0)))
        term_freqs = record.get("term_freqs", {})
        score = 0.0

        for token in query_tokens:
            doc_freq = int(document_frequency.get(token, 0))
            term_freq = int(term_freqs.get(token, 0))
            if doc_freq <= 0 or term_freq <= 0 or total_docs <= 0:
                continue

            idf = math.log(1.0 + ((total_docs - doc_freq + 0.5) / (doc_freq + 0.5)))
            numerator = term_freq * (BM25_K1 + 1.0)
            denominator = term_freq + BM25_K1 * (1.0 - BM25_B + BM25_B * (length / avg_doc_length))
            score += idf * (numerator / denominator)

        if score > 0.0:
            scored.append((doc_id, score))

    scored.sort(key=lambda item: (-item[1], item[0]))
    return [doc_id for doc_id, _ in scored[:top_n]]


def is_excluded_path(file_path: str) -> bool:
    path = Path(file_path)

    lowered_parts = [part.lower() for part in path.parts]
    if any(part in EXCLUDED_DIRECTORIES for part in lowered_parts):
        return True

    name = path.name.lower()
    if name.startswith(".env"):
        return True
    if name.endswith(".log"):
        return True

    return False


def is_non_searchable_path(file_path: str) -> bool:
    if is_excluded_path(file_path):
        return True
    path = Path(file_path)
    name = path.name.lower()
    suffix = path.suffix.lower()
    if name in SEARCHABLE_FILENAMES:
        return False
    return suffix not in SEARCHABLE_SUFFIXES


def normalize_file_for_order(file_path: str) -> str:
    path = Path(file_path)
    if path.is_absolute():
        try:
            path = path.resolve().relative_to(ROOT)
        except ValueError:
            return path.as_posix()
    return Path(path.as_posix()).as_posix().lstrip("./")


def filter_excluded_entries(entries: list[dict]) -> list[dict]:
    return [
        entry for entry in entries
        if isinstance(entry, dict)
        and not is_excluded_path(str(entry.get("file", "")))
    ]


def find_context(file_path: str, snippet: str) -> str:
    raise SystemExit(SOURCE_ACCESS_FORBIDDEN_MESSAGE)


def build_rerank_document(file_path: str, fallback_doc: str, query_text: str) -> str:
    raise SystemExit(SOURCE_ACCESS_FORBIDDEN_MESSAGE)


def classify(path: str, index_manifest: dict) -> str:
    lowered = path.lower()
    classification_policy = index_manifest.get("classification_policy")
    if not isinstance(classification_policy, dict):
        raise SystemExit("FEL: classification_policy saknas i indexmanifestet")

    for rule in classification_policy.get("precedence", []):
        rule_type = rule.get("type")
        value = str(rule.get("value", "")).lower()
        layer = str(rule.get("layer", "")).upper()

        if rule_type == "path_substring" and value in lowered:
            return layer
        if rule_type == "path_suffix" and lowered.endswith(value):
            return layer

    return str(classification_policy.get("default_layer", "OTHER")).upper()


def build_result_content(file_path: str, doc: str) -> tuple[str, str]:
    return "chunk", normalize_document_text(doc)[:MAX_CONTEXT_CHARS]


def build_output_entry(file_path: str, doc: str, dist: float | None, final_score: float, index_manifest: dict) -> dict:
    source_type, snippet = build_result_content(file_path, doc)
    normalized_file = normalize_file_for_order(file_path)
    return {
        "file": normalized_file,
        "layer": classify(normalized_file, index_manifest),
        "snippet": snippet,
        "source_type": source_type,
        "score": float(final_score),
    }


def render_results_text(entries: list[dict], top_k: int) -> str:
    lines = ["", "================ RESULTAT ================", ""]
    printed = False

    for entry in entries:
        printed = True

        file_path = entry.get("file", "UNKNOWN")
        score = float(entry.get("score", 0.0))
        content = str(entry.get("snippet", ""))

        lines.append(f"[SIMILARITY: 0.0000 | FINAL: {score:.4f}]")
        lines.append(f"FILE: {file_path}")
        lines.append("-" * 60)
        lines.append(content)
        lines.append("")

        if len([line for line in lines if line.startswith("FILE: ")]) >= top_k:
            break

    if not printed:
        lines.append("INGA SOKRESULTAT")

    return "\n".join(lines) + "\n"


def render_results(entries: list[dict], top_k: int) -> None:
    print(render_results_text(entries, top_k=top_k), end="")


def fetch_collection_entries(collection, doc_ids: list[str]) -> dict[str, dict]:
    if not doc_ids:
        return {}

    result = collection.get(ids=doc_ids, include=["documents", "metadatas"])
    entries = {}

    for doc_id, doc, meta in zip(result.get("ids") or [], result.get("documents") or [], result.get("metadatas") or []):
        if not meta:
            continue

        file_path = meta.get("file", "UNKNOWN")
        if is_non_searchable_path(file_path):
            continue

        entries[doc_id] = {
            "id": doc_id,
            "doc": doc,
            "meta": meta,
        }

    return entries


def execute_query(raw_query: str, runtime_state: dict) -> tuple[list[dict], int]:
    index_manifest = runtime_state["index_manifest"]
    validate_flat_manifest_fields(index_manifest)
    require_query_model_surface()


def handle_query_request(raw_query: str) -> str:
    runtime_state = load_runtime_state()
    output_entries, top_k = execute_query(raw_query, runtime_state)
    return render_results_text(output_entries, top_k=top_k)


def handle_query_json(raw_query: str) -> str:
    runtime_state = load_runtime_state()
    output_entries, _ = execute_query(raw_query, runtime_state)
    return json.dumps(output_entries, ensure_ascii=False, indent=2)


def dispatch_query(raw_query: str, output_format: str = "text") -> None:
    preflight_runtime_prerequisites()
    if output_format == "json":
        sys.stdout.write(handle_query_json(raw_query))
    else:
        sys.stdout.write(handle_query_request(raw_query))


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "--server":
        raise SystemExit("FEL: varm Unix-sokserver ar inte en kanonisk Windows-runtimeyta")

    output_format = "text"
    args = sys.argv[1:]
    if args and args[0] == "--json":
        output_format = "json"
        args = args[1:]

    raw_query = " ".join(args).strip()
    if not raw_query:
        print("FEL: Ingen fråga angavs")
        sys.exit(1)

    dispatch_query(raw_query, output_format=output_format)


if __name__ == "__main__":
    main()
