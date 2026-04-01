#!/usr/bin/env python3

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"
SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "bin" / "python"

approved_pythons = {path.resolve() for path in (REPO_PYTHON, SEARCH_PYTHON) if path.exists()}
if Path(sys.executable).resolve() not in approved_pythons:
    if not REPO_PYTHON.exists():
        raise SystemExit(f"FEL: repo-Python saknas vid {REPO_PYTHON}")
    os.execv(str(REPO_PYTHON), [str(REPO_PYTHON), __file__, *sys.argv[1:]])

from chromadb import PersistentClient
from rank_bm25 import BM25Okapi
from sentence_transformers import CrossEncoder, SentenceTransformer

from ast_extract import extract_functions
try:
    from device_utils import resolve_index_device
except ModuleNotFoundError:
    from tools.index.device_utils import resolve_index_device

# ---------------------------------------------------------
# CONFIG
# ---------------------------------------------------------

DB_PATH = str(ROOT / ".repo_index" / "chroma_db")
COLLECTION_NAME = "aveli_repo"
EMBED_MODEL = "BAAI/bge-m3"
RERANK_MODEL = "BAAI/bge-reranker-large"

TOP_K = 16
VECTOR_CANDIDATE_K = 30
BM25_CANDIDATE_K = 30
EXPANSION = 100
MAX_CONTEXT_CHARS = 2500
RERANK_BATCH_SIZE_GPU = 8
RERANK_BATCH_SIZE_CPU = 2
RERANK_MAX_CHARS = 1600
RERANK_CONTEXT_LINES_BEFORE = 30
RERANK_CONTEXT_LINES_AFTER = 70

CACHE_FILE = ROOT / ".repo_index" / "query_cache.json"
MEMORY_FILE = ROOT / ".repo_index" / "query_memory.json"

SEARCHABLE_SUFFIXES = {
    ".css",
    ".csv",
    ".dart",
    ".env",
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
    ".env.example",
    ".env.example.backend",
    ".env.example.flutter",
    ".env.docker.example",
    ".gitignore",
    "dockerfile",
    "makefile",
    "procfile",
}


def load_json_object(path: Path) -> dict:
    if not path.exists():
        return {}

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"FEL: JSON-objekt forvantas i {path}")
    return data


def save_json_object(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def update_query_memory(raw_query: str) -> None:
    memory = load_json_object(MEMORY_FILE)
    memory[raw_query] = int(memory.get(raw_query, 0)) + 1
    save_json_object(MEMORY_FILE, memory)


def normalize_document_text(text: str) -> str:
    return text.removeprefix("passage: ").strip()


def tokenize_for_bm25(text: str) -> list[str]:
    return normalize_document_text(text).lower().split()


def is_non_searchable_path(file_path: str) -> bool:
    path = Path(file_path)
    name = path.name.lower()
    suffix = path.suffix.lower()
    if name in SEARCHABLE_FILENAMES or name.startswith(".env"):
        return False
    return suffix not in SEARCHABLE_SUFFIXES


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


def classify(path: str) -> str:
    lowered = path.lower()

    if "routes" in lowered:
        return "ROUTE"
    if "services" in lowered:
        return "SERVICE"
    if ".sql" in lowered:
        return "DB"
    if "models" in lowered:
        return "MODEL"
    if "schema" in lowered:
        return "SCHEMA"
    if "policy" in lowered:
        return "POLICY"

    return "OTHER"


def score_result(file_path: str, dist: float | None) -> float:
    similarity = 0.0 if dist is None else 1.0 - float(dist)
    lowered = file_path.lower()
    layer = classify(file_path)

    if "aveli_system_decisions.md" in lowered:
        similarity += 0.15

    if "routes" in lowered:
        similarity += 0.12

    if "playback.py" in lowered:
        similarity += 0.15

    if "services" in lowered:
        similarity += 0.10

    if "courses_service.py" in lowered:
        similarity += 0.12

    if "lesson_playback_service.py" in lowered:
        similarity += 0.12

    if lowered.endswith(".sql"):
        similarity += 0.12

    if "enrolled_read" in lowered or "enrollments" in lowered:
        similarity += 0.18

    if "models" in lowered or layer == "MODEL":
        similarity += 0.10

    if "schema" in lowered or layer == "SCHEMA":
        similarity += 0.15

    if "policy" in lowered or layer == "POLICY":
        similarity += 0.20

    if "db" in lowered or layer == "DB":
        similarity += 0.12

    if "route" in lowered or layer == "ROUTE":
        similarity += 0.10

    if layer == "SERVICE":
        similarity += 0.10

    return similarity


def build_result_content(file_path: str, doc: str) -> str:
    functions = extract_functions(file_path, doc)
    if functions.strip():
        return functions[:MAX_CONTEXT_CHARS]

    context = find_context(file_path, doc)
    if context.strip():
        return context[:MAX_CONTEXT_CHARS]

    return "[VARNING] Ingen kontext hittades"


def build_output_entry(file_path: str, doc: str, dist: float | None, final_score: float) -> dict:
    similarity = 0.0 if dist is None else 1.0 - float(dist)
    return {
        "file": file_path,
        "similarity": similarity,
        "final_score": float(final_score),
        "content": build_result_content(file_path, doc),
    }


def render_results(entries: list[dict]) -> None:
    print("\n================ RESULTAT ================\n")

    seen = set()
    printed = False

    for entry in entries:
        file_path = entry.get("file", "UNKNOWN")
        if file_path in seen:
            continue

        seen.add(file_path)
        printed = True

        similarity = float(entry.get("similarity", 0.0))
        final_score = float(entry.get("final_score", 0.0))
        content = str(entry.get("content", ""))

        print(f"[SIMILARITY: {similarity:.4f} | FINAL: {final_score:.4f}]")
        print(f"FILE: {file_path}")
        print("-" * 60)
        print(content)
        print("\n")

        if len(seen) >= TOP_K:
            break

    if not printed:
        print("INGA SOKRESULTAT")


def main() -> None:
    raw_query = " ".join(sys.argv[1:]).strip()
    if not raw_query:
        print("FEL: Ingen fråga angavs")
        sys.exit(1)

    update_query_memory(raw_query)

    query_cache = load_json_object(CACHE_FILE)
    cached_entries = query_cache.get(raw_query)
    if isinstance(cached_entries, list):
        print("[CACHE TRAFF]", file=sys.stderr)
        render_results(cached_entries)
        return

    DEVICE, DEVICE_SOURCE = resolve_index_device()
    print(f"[INFO] Enhet: {DEVICE} ({DEVICE_SOURCE})")

    model = SentenceTransformer(EMBED_MODEL, device=DEVICE)
    reranker = CrossEncoder(RERANK_MODEL, device=DEVICE)
    query = "query: " + raw_query

    client = PersistentClient(path=DB_PATH)
    collection = client.get_collection(COLLECTION_NAME)

    corpus = collection.get(include=["documents", "metadatas"])
    corpus_ids = corpus.get("ids") or []
    corpus_documents = corpus.get("documents") or []
    corpus_metadatas = corpus.get("metadatas") or []

    if not corpus_ids or not corpus_documents or not corpus_metadatas:
        render_results([])
        query_cache[raw_query] = []
        save_json_object(CACHE_FILE, query_cache)
        return

    corpus_entries = []
    id_to_corpus_index = {}

    for doc_id, doc, meta in zip(corpus_ids, corpus_documents, corpus_metadatas):
        if not meta:
            continue

        file_path = meta.get("file", "UNKNOWN")
        if is_non_searchable_path(file_path):
            continue

        corpus_index = len(corpus_entries)
        corpus_entries.append({
            "id": doc_id,
            "doc": doc,
            "meta": meta,
        })
        id_to_corpus_index[doc_id] = corpus_index

    if not corpus_entries:
        render_results([])
        query_cache[raw_query] = []
        save_json_object(CACHE_FILE, query_cache)
        return

    tokenized_corpus = [tokenize_for_bm25(entry["doc"]) for entry in corpus_entries]
    bm25 = BM25Okapi(tokenized_corpus)
    query_tokens = raw_query.lower().split()
    bm25_scores = bm25.get_scores(query_tokens)
    top_bm25_idx = sorted(
        range(len(bm25_scores)),
        key=lambda i: (-float(bm25_scores[i]), i),
    )[:BM25_CANDIDATE_K]

    embedding = model.encode(
        [query],
        normalize_embeddings=True,
        convert_to_numpy=True,
    ).tolist()

    vector_results = collection.query(
        query_embeddings=embedding,
        n_results=VECTOR_CANDIDATE_K,
    )

    if "ids" not in vector_results:
        raise RuntimeError("FEL: Chroma-query saknar dokument-id:n for hybrid fusion.")

    vector_ids = vector_results["ids"][0]
    vector_distances = vector_results["distances"][0]

    vector_distance_by_index = {}
    top_vector_idx = []

    for doc_id, dist in zip(vector_ids, vector_distances):
        corpus_index = id_to_corpus_index.get(doc_id)
        if corpus_index is None:
            continue
        top_vector_idx.append(corpus_index)
        vector_distance_by_index[corpus_index] = float(dist)

    combined_indices = list(dict.fromkeys(top_bm25_idx + top_vector_idx))
    if not combined_indices:
        render_results([])
        query_cache[raw_query] = []
        save_json_object(CACHE_FILE, query_cache)
        return

    rerank_batch_size = RERANK_BATCH_SIZE_GPU if DEVICE == "cuda" else RERANK_BATCH_SIZE_CPU
    pairs = [
        (
            raw_query,
            build_rerank_document(
                corpus_entries[index]["meta"].get("file", "UNKNOWN"),
                corpus_entries[index]["doc"],
                raw_query,
            ),
        )
        for index in combined_indices
    ]
    reranker_scores = reranker.predict(
        pairs,
        batch_size=rerank_batch_size,
        show_progress_bar=False,
    )

    reranked = []

    for reranker_score, index in zip(reranker_scores, combined_indices):
        entry = corpus_entries[index]
        file_path = entry["meta"].get("file", "UNKNOWN")
        dist = vector_distance_by_index.get(index)
        final_score = float(reranker_score) + score_result(file_path, dist)
        reranked.append((final_score, float(reranker_score), index))

    reranked.sort(key=lambda item: (-item[0], -item[1], item[2]))

    has_route = any(
        "routes" in corpus_entries[index]["meta"].get("file", "").lower()
        for _, _, index in reranked
    )
    if not has_route:
        for index in top_vector_idx:
            file_path = corpus_entries[index]["meta"].get("file", "")
            if "routes" in file_path.lower():
                reranked.insert(0, (999.0, 999.0, index))
                break

    output_entries = []

    for final_score, _, index in reranked:
        entry = corpus_entries[index]
        file_path = entry["meta"].get("file", "UNKNOWN")
        dist = vector_distance_by_index.get(index)
        output_entries.append(
            build_output_entry(
                file_path=file_path,
                doc=entry["doc"],
                dist=dist,
                final_score=final_score,
            )
        )

    query_cache[raw_query] = output_entries
    save_json_object(CACHE_FILE, query_cache)
    render_results(output_entries)


if __name__ == "__main__":
    main()
