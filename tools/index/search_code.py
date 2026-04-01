#!/usr/bin/env python3

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

from sentence_transformers import SentenceTransformer
from chromadb import PersistentClient

from ast_extract import extract_functions  # 🔥 NY
try:
    from device_utils import resolve_index_device
except ModuleNotFoundError:
    from tools.index.device_utils import resolve_index_device

# ---------------------------------------------------------
# CONFIG
# ---------------------------------------------------------

DB_PATH = str(ROOT / ".repo_index" / "chroma_db")
COLLECTION_NAME = "aveli_repo"
EMBED_MODEL = "intfloat/e5-large-v2"

TOP_K = 16
EXPANSION = 100
MAX_CONTEXT_CHARS = 2500

DEVICE, DEVICE_SOURCE = resolve_index_device()
print(f"[INFO] Enhet: {DEVICE} ({DEVICE_SOURCE})")

model = SentenceTransformer(EMBED_MODEL, device=DEVICE)

raw_query = " ".join(sys.argv[1:]).strip()

if not raw_query:
    print("FEL: Ingen fråga angavs")
    sys.exit(1)

query = "query: " + raw_query

# ---------------------------------------------------------
# DB
# ---------------------------------------------------------

client = PersistentClient(path=DB_PATH)
collection = client.get_collection(COLLECTION_NAME)

embedding = model.encode(
    [query],
    normalize_embeddings=True,
    convert_to_numpy=True,
).tolist()

results = collection.query(
    query_embeddings=embedding,
    n_results=TOP_K,
)

documents = results["documents"][0]
metadatas = results["metadatas"][0]
distances = results["distances"][0]

# ---------------------------------------------------------
# HELPERS
# ---------------------------------------------------------

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


def score_result(file_path: str, dist: float) -> float:
    similarity = 1.0 - float(dist)
    lowered = file_path.lower()

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

    return similarity


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


def is_non_searchable_path(file_path: str) -> bool:
    path = Path(file_path)
    name = path.name.lower()
    suffix = path.suffix.lower()
    if name in SEARCHABLE_FILENAMES or name.startswith(".env"):
        return False
    return suffix not in SEARCHABLE_SUFFIXES


# ---------------------------------------------------------
# BUILD SCORED RESULTS
# ---------------------------------------------------------

scored = []

for doc, meta, dist in zip(documents, metadatas, distances):
    file_path = meta.get("file", "UNKNOWN")
    if is_non_searchable_path(file_path):
        continue
    final_score = score_result(file_path, dist)
    scored.append((final_score, doc, meta, dist))

scored.sort(key=lambda x: x[0], reverse=True)

# ---------------------------------------------------------
# FORCE AT LEAST ONE ROUTE
# ---------------------------------------------------------

has_route = any("routes" in item[2].get("file", "").lower() for item in scored)

if not has_route:
    for doc, meta, dist in zip(documents, metadatas, distances):
        file_path = meta.get("file", "")
        if "routes" in file_path.lower():
            scored.insert(0, (999.0, doc, meta, dist))
            break

# ---------------------------------------------------------
# OUTPUT
# ---------------------------------------------------------

print("\n================ RESULTAT ================\n")

seen = set()
printed = False

for final_score, doc, meta, dist in scored:
    file_path = meta.get("file", "UNKNOWN")

    if file_path in seen:
        continue

    seen.add(file_path)

    similarity = 1.0 - float(dist)
    printed = True

    print(f"[SIMILARITY: {similarity:.4f} | FINAL: {final_score:.4f}]")
    print(f"FILE: {file_path}")
    print("-" * 60)

    # 🔥 1. AST extraction
    functions = extract_functions(file_path, doc)

    if functions.strip():
        print(functions[:MAX_CONTEXT_CHARS])
    else:
        # 🔥 2. fallback till fungerande context
        context = find_context(file_path, doc)

        if context.strip():
            print(context[:MAX_CONTEXT_CHARS])
        else:
            print("[VARNING] Ingen kontext hittades")

    print("\n")

if not printed:
    print("INGA SOKRESULTAT")
