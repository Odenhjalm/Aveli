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
from sentence_transformers import CrossEncoder, SentenceTransformer

from ast_extract import extract_functions
try:
    from device_utils import resolve_index_device
except ModuleNotFoundError:
    from tools.index.device_utils import resolve_index_device

# ---------------------------------------------------------
# CONFIG
# ---------------------------------------------------------

INDEX_MANIFEST = ROOT / ".repo_index" / "index_manifest.json"
SEARCH_MANIFEST = ROOT / ".repo_index" / "search_manifest.txt"
DB_PATH = str(ROOT / ".repo_index" / "chroma_db")
CHUNK_MANIFEST = ROOT / ".repo_index" / "chunk_manifest.jsonl"
LEXICAL_INDEX_DIR = ROOT / ".repo_index" / "lexical_index"
LEXICAL_INDEX_MANIFEST = LEXICAL_INDEX_DIR / "manifest.json"
LEXICAL_INDEX_DOCUMENTS = LEXICAL_INDEX_DIR / "documents.jsonl"
COLLECTION_NAME = "aveli_repo"
INDEX_MANIFEST_REQUIRED_FIELDS = {
    "contract_version",
    "corpus_manifest_hash",
    "chunk_manifest_hash",
    "chunk_size",
    "chunk_overlap",
    "embedding_model",
    "rerank_model",
    "top_k",
    "vector_candidate_k",
    "lexical_candidate_k",
}

EXPANSION = 100
MAX_CONTEXT_CHARS = 2500
RERANK_BATCH_SIZE_GPU = 8
RERANK_BATCH_SIZE_CPU = 2
RERANK_MAX_CHARS = 1600
RERANK_CONTEXT_LINES_BEFORE = 30
RERANK_CONTEXT_LINES_AFTER = 70
BM25_K1 = 1.5
BM25_B = 0.75

CACHE_FILE = ROOT / ".repo_index" / "query_cache.json"
MEMORY_FILE = ROOT / ".repo_index" / "query_memory.json"

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


def load_index_manifest() -> dict:
    if not INDEX_MANIFEST.exists():
        raise SystemExit(f"FEL: indexmanifest saknas vid {INDEX_MANIFEST}")

    manifest = load_json_object(INDEX_MANIFEST)
    missing = sorted(INDEX_MANIFEST_REQUIRED_FIELDS - set(manifest))
    if missing:
        raise SystemExit(
            "FEL: indexmanifest saknar falt: " + ", ".join(missing)
        )
    if "classification_rules" not in manifest:
        raise SystemExit("FEL: classification_rules saknas i indexmanifestet")
    return manifest


def validate_canonical_index_health() -> None:
    required_files = [
        SEARCH_MANIFEST,
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


def save_json_object(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def normalize_query(raw_query: str) -> str:
    return " ".join(raw_query.strip().lower().split())


def build_cache_key(raw_query: str, index_manifest: dict) -> str:
    return "||".join(
        [
            normalize_query(raw_query),
            str(index_manifest["contract_version"]),
            str(index_manifest["corpus_manifest_hash"]),
            str(index_manifest["chunk_manifest_hash"]),
        ]
    )


def build_safe_cache_entry(entries: list[dict]) -> dict:
    return {
        "result_count": len(entries),
        "files": [entry["file"] for entry in entries],
        "layers": [entry["layer"] for entry in entries],
        "source_types": [entry["source_type"] for entry in entries],
        "scores": [entry["score"] for entry in entries],
    }


def sanitize_query_cache(cache: dict) -> dict:
    sanitized = {}
    for key, value in cache.items():
        if not isinstance(key, str):
            continue
        if not isinstance(value, dict):
            continue
        sanitized[key] = {
            "result_count": int(value.get("result_count", 0)),
            "files": [str(item) for item in value.get("files", []) if isinstance(item, str)],
            "layers": [str(item) for item in value.get("layers", []) if isinstance(item, str)],
            "source_types": [str(item) for item in value.get("source_types", []) if isinstance(item, str)],
            "scores": [float(item) for item in value.get("scores", [])],
        }
    return sanitized


def sanitize_query_memory(memory: dict) -> dict:
    sanitized = {}
    for key, value in memory.items():
        if not isinstance(key, str):
            continue
        if key.count("||") != 3:
            continue
        sanitized[key] = int(value)
    return sanitized


def update_query_memory(cache_key: str) -> None:
    memory = load_json_object(MEMORY_FILE)
    memory = sanitize_query_memory(memory)
    memory[cache_key] = int(memory.get(cache_key, 0)) + 1
    save_json_object(MEMORY_FILE, memory)


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


def load_ranking_policy(index_manifest: dict) -> dict:
    ranking_policy = index_manifest.get("ranking_policy")
    if not isinstance(ranking_policy, dict):
        raise SystemExit("FEL: ranking_policy saknas i indexmanifestet")
    return ranking_policy


def load_runtime_state() -> dict:
    global _RUNTIME_STATE

    if _RUNTIME_STATE is not None:
        return _RUNTIME_STATE

    validate_canonical_index_health()
    index_manifest = load_index_manifest()
    lexical_manifest, lexical_records = load_lexical_index()
    chunk_records = load_chunk_manifest_records()
    device, device_source = resolve_index_device()
    client = PersistentClient(path=DB_PATH)
    collection = client.get_collection(COLLECTION_NAME)
    validate_contract_version_bindings(
        index_manifest=index_manifest,
        chunk_records=chunk_records,
        lexical_manifest=lexical_manifest,
        collection=collection,
    )

    embedding_model = str(index_manifest["embedding_model"])
    rerank_model = str(index_manifest["rerank_model"])

    _RUNTIME_STATE = {
        "index_manifest": index_manifest,
        "lexical_manifest": lexical_manifest,
        "lexical_records": lexical_records,
        "chunk_records": chunk_records,
        "device": device,
        "device_source": device_source,
        "collection": collection,
        "model": SentenceTransformer(embedding_model, device=device),
        "reranker": CrossEncoder(rerank_model, device=device),
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
    path = ROOT / file_path

    if not path.exists():
        return ""

    try:
        lines = path.read_text(errors="ignore").splitlines()
    except Exception:
        return ""

    if not lines:
        return ""

    snippet = snippet.strip().lower()
    best_index = None

    short_snippet = snippet[:80]
    if short_snippet:
        for i, line in enumerate(lines):
            if short_snippet in line.lower():
                best_index = i
                break

    if best_index is None and snippet:
        words = [w for w in snippet.split()[:5] if len(w) > 2]
        for i, line in enumerate(lines):
            lowered = line.lower()
            if words and any(word in lowered for word in words):
                best_index = i
                break

    if best_index is None:
        best_index = min(len(lines) // 4, max(0, len(lines) - 1))

    start = max(0, best_index - EXPANSION)
    end = min(len(lines), best_index + EXPANSION)

    context = "\n".join(lines[start:end]).strip()

    if not context:
        context = "\n".join(lines[: min(200, len(lines))]).strip()

    return context


def build_rerank_document(file_path: str, fallback_doc: str, query_text: str) -> str:
    path = ROOT / file_path
    query_terms = [term.lower() for term in query_text.split() if len(term) > 2]

    try:
        lines = path.read_text(errors="ignore").splitlines()
    except Exception:
        cleaned = normalize_document_text(fallback_doc)
        return f"{file_path}\n{cleaned[:RERANK_MAX_CHARS]}"

    best_index = None

    for i, line in enumerate(lines):
        lowered = line.lower()
        if any(term in lowered for term in query_terms):
            best_index = i
            break

    if best_index is None:
        cleaned = normalize_document_text(fallback_doc)
        return f"{file_path}\n{cleaned[:RERANK_MAX_CHARS]}"

    start = max(0, best_index - RERANK_CONTEXT_LINES_BEFORE)
    end = min(len(lines), best_index + RERANK_CONTEXT_LINES_AFTER)
    excerpt = "\n".join(lines[start:end]).strip()

    return f"{file_path}\n{excerpt[:RERANK_MAX_CHARS]}"


def classify(path: str, index_manifest: dict) -> str:
    lowered = path.lower()
    classification_rules = index_manifest.get("classification_rules", {})

    for rule in classification_rules.get("precedence", []):
        rule_type = rule.get("type")
        value = str(rule.get("value", "")).lower()
        layer = str(rule.get("layer", "")).upper()

        if rule_type == "path_substring" and value in lowered:
            return layer
        if rule_type == "path_suffix" and lowered.endswith(value):
            return layer

    return str(classification_rules.get("default_layer", "OTHER")).upper()


def score_result(file_path: str, dist: float | None, ranking_policy: dict, index_manifest: dict) -> float:
    similarity = 0.0 if dist is None else - float(dist)
    lowered = file_path.lower()
    layer = classify(file_path, index_manifest)

    for substring, boost in ranking_policy.get("path_substring_boosts", {}).items():
        if substring in lowered:
            similarity += float(boost)

    for suffix, boost in ranking_policy.get("path_suffix_boosts", {}).items():
        if lowered.endswith(str(suffix)):
            similarity += float(boost)

    similarity += float(ranking_policy.get("layer_boosts", {}).get(layer, 0.0))

    return similarity


def route_override_boost(doc_id: str, route_override_doc_id: str | None, ranking_policy: dict) -> float:
    route_override = ranking_policy.get("route_override", {})
    if not route_override.get("enabled", False):
        return 0.0
    if route_override_doc_id is None:
        return 0.0
    if doc_id != route_override_doc_id:
        return 0.0
    return float(route_override.get("score", 0.0))


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
    lexical_manifest = runtime_state["lexical_manifest"]
    lexical_records = runtime_state["lexical_records"]
    collection = runtime_state["collection"]
    model = runtime_state["model"]
    reranker = runtime_state["reranker"]
    device = runtime_state["device"]
    ranking_policy = load_ranking_policy(index_manifest)

    top_k = int(index_manifest["top_k"])
    vector_candidate_k = int(index_manifest["vector_candidate_k"])
    lexical_candidate_k = int(index_manifest["lexical_candidate_k"])
    cache_key = build_cache_key(raw_query, index_manifest)

    update_query_memory(cache_key)

    query_cache = load_json_object(CACHE_FILE)
    sanitized_cache = sanitize_query_cache(query_cache)
    if sanitized_cache != query_cache:
        query_cache = sanitized_cache
        save_json_object(CACHE_FILE, query_cache)

    lexical_doc_ids = lexical_search(
        query_text=raw_query,
        lexical_records=lexical_records,
        lexical_manifest=lexical_manifest,
        top_n=lexical_candidate_k,
    )

    embedding = model.encode(
        ["query: " + raw_query],
        normalize_embeddings=True,
        convert_to_numpy=True,
    ).tolist()

    vector_results = collection.query(
        query_embeddings=embedding,
        n_results=vector_candidate_k,
        include=["distances", "documents", "metadatas"],
    )

    if "ids" not in vector_results:
        raise RuntimeError("FEL: Chroma-query saknar dokument-id:n for hybrid fusion.")

    vector_ids = vector_results["ids"][0]
    vector_distances = vector_results["distances"][0]
    vector_documents = vector_results.get("documents", [[]])[0]
    vector_metadatas = vector_results.get("metadatas", [[]])[0]

    candidate_entries: dict[str, dict] = {}
    vector_distance_by_doc_id: dict[str, float] = {}
    top_vector_ids: list[str] = []

    for doc_id, dist, doc, meta in zip(vector_ids, vector_distances, vector_documents, vector_metadatas):
        if not meta:
            continue

        file_path = meta.get("file", "UNKNOWN")
        if is_non_searchable_path(file_path):
            continue

        top_vector_ids.append(doc_id)
        vector_distance_by_doc_id[doc_id] = float(dist)
        candidate_entries[doc_id] = {
            "id": doc_id,
            "doc": doc,
            "meta": meta,
        }

    lexical_only_ids = [doc_id for doc_id in lexical_doc_ids if doc_id not in candidate_entries]
    candidate_entries.update(fetch_collection_entries(collection, lexical_only_ids))

    combined_ids = [
        doc_id
        for doc_id in dict.fromkeys(lexical_doc_ids + top_vector_ids)
        if doc_id in candidate_entries
    ]
    if not combined_ids:
        query_cache[cache_key] = build_safe_cache_entry([])
        save_json_object(CACHE_FILE, query_cache)
        return [], top_k

    rerank_batch_size = RERANK_BATCH_SIZE_GPU if device == "cuda" else RERANK_BATCH_SIZE_CPU
    position_by_doc_id = {doc_id: index for index, doc_id in enumerate(combined_ids)}
    pairs = [
        (
            raw_query,
            build_rerank_document(
                candidate_entries[doc_id]["meta"].get("file", "UNKNOWN"),
                candidate_entries[doc_id]["doc"],
                raw_query,
            ),
        )
        for doc_id in combined_ids
    ]
    if ranking_policy.get("use_rerank", True):
        reranker_scores = reranker.predict(
            pairs,
            batch_size=rerank_batch_size,
            show_progress_bar=False,
        )
    else:
        reranker_scores = [0.0 for _ in combined_ids]

    route_override_doc_id = None
    route_override = ranking_policy.get("route_override", {})
    if route_override.get("enabled", False):
        has_route = any(
            "routes" in candidate_entries[doc_id]["meta"].get("file", "").lower()
            for doc_id in combined_ids
        )
        if not has_route:
            for doc_id in top_vector_ids:
                file_path = candidate_entries.get(doc_id, {}).get("meta", {}).get("file", "")
                if "routes" in file_path.lower():
                    route_override_doc_id = doc_id
                    break

    reranked = []

    for reranker_score, doc_id in zip(reranker_scores, combined_ids):
        entry = candidate_entries[doc_id]
        file_path = entry["meta"].get("file", "UNKNOWN")
        dist = vector_distance_by_doc_id.get(doc_id)
        final_score = float(reranker_score) + score_result(
            file_path,
            dist,
            ranking_policy,
            index_manifest,
        )
        final_score += route_override_boost(doc_id, route_override_doc_id, ranking_policy)
        reranked.append((final_score, float(reranker_score), doc_id))

    reranked.sort(
        key=lambda item: (
            -item[0],
            normalize_file_for_order(candidate_entries[item[2]]["meta"].get("file", "UNKNOWN")),
            item[2],
        )
    )

    output_entries = []

    for final_score, _, doc_id in reranked[:top_k]:
        entry = candidate_entries[doc_id]
        file_path = entry["meta"].get("file", "UNKNOWN")
        dist = vector_distance_by_doc_id.get(doc_id)
        output_entries.append(
            build_output_entry(
                file_path=file_path,
                doc=entry["doc"],
                dist=dist,
                final_score=final_score,
                index_manifest=index_manifest,
            )
        )

    output_entries = filter_excluded_entries(output_entries)
    query_cache[cache_key] = build_safe_cache_entry(output_entries)
    save_json_object(CACHE_FILE, query_cache)
    return output_entries, top_k


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
