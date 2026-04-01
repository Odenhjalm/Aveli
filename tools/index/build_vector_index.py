#!/usr/bin/env python3

import os
import shutil
import sys
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"
SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "bin" / "python"

approved_pythons = {path.resolve() for path in (REPO_PYTHON, SEARCH_PYTHON) if path.exists()}
if Path(sys.executable).resolve() not in approved_pythons:
    if not REPO_PYTHON.exists():
        raise SystemExit(f"FEL: repo-Python saknas vid {REPO_PYTHON}")
    os.execv(str(REPO_PYTHON), [str(REPO_PYTHON), __file__, *sys.argv[1:]])

from sentence_transformers import SentenceTransformer
import chromadb
from tqdm import tqdm

try:
    from device_utils import resolve_index_device
except ModuleNotFoundError:
    from tools.index.device_utils import resolve_index_device

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------

INDEX_DIR = ROOT / ".repo_index"
FILES_LIST = INDEX_DIR / "searchable_files.txt"
FALLBACK_FILES_LIST = INDEX_DIR / "files.txt"
VECTOR_DB_DIR = INDEX_DIR / "chroma_db"

# ---------------------------------------------------------
# Config
# ---------------------------------------------------------

COLLECTION_NAME = "aveli_repo"

# Coarser chunks keep rebuild times practical while search_code.py
# still resolves precise local context from the matched file afterward.
CHUNK_SIZE = 2000
CHUNK_OVERLAP = 200
BATCH_SIZE_GPU = 64
BATCH_SIZE_CPU = 32

EMBED_MODEL = "BAAI/bge-m3"

# 🔥 IMPORTANT: set manually when needed
REBUILD = True   # True = wipe index, False = reuse

# ---------------------------------------------------------
# Device selection (canonical)
# ---------------------------------------------------------

DEVICE, DEVICE_SOURCE = resolve_index_device()
print(f"[INFO] Enhet: {DEVICE} ({DEVICE_SOURCE})")

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


def is_searchable_file(path: Path, relative_file: str) -> bool:
    if "node_modules" in relative_file or "archive" in relative_file:
        return False
    name = path.name.lower()
    suffix = path.suffix.lower()
    if not (name in SEARCHABLE_FILENAMES or name.startswith(".env") or suffix in SEARCHABLE_SUFFIXES):
        return False
    try:
        head = path.read_bytes()[:8192]
    except OSError:
        return False
    if not head:
        return False
    if b"\x00" in head:
        return False
    return True


def classify(path: str) -> str:
    p = path.lower()

    if "routes" in p:
        return "ROUTE"
    if "services" in p:
        return "SERVICE"
    if ".sql" in p:
        return "DB"
    if "models" in p:
        return "MODEL"
    if "schema" in p:
        return "SCHEMA"
    if "policy" in p:
        return "POLICY"

    return "OTHER"

# ---------------------------------------------------------
# Chunking
# ---------------------------------------------------------

def chunk_text(text: str,
               chunk_size: int = CHUNK_SIZE,
               overlap: int = CHUNK_OVERLAP) -> Iterable[str]:

    if not text:
        return

    start = 0
    text_len = len(text)

    while start < text_len:

        end = min(start + chunk_size, text_len)

        yield text[start:end]

        if end == text_len:
            break

        start = max(end - overlap, 0)

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------

def main():

    file_list_path = FILES_LIST if FILES_LIST.exists() else FALLBACK_FILES_LIST

    if not file_list_path.exists():
        raise RuntimeError(
            f"{FILES_LIST} saknas. Bygg repoindex först."
        )

    print("\n[STEG] Läser fillista...")

    files = [
        line.strip()
        for line in file_list_path.read_text().splitlines()
        if line.strip()
    ]

    print(f"[INFO] {len(files)} filer hittades")

    INDEX_DIR.mkdir(parents=True, exist_ok=True)

    # ---------------------------------------------------------
    # Optional rebuild
    # ---------------------------------------------------------

    if REBUILD and VECTOR_DB_DIR.exists():
        print("[INFO] Tar bort befintlig vektor-DB...")
        shutil.rmtree(VECTOR_DB_DIR)

    VECTOR_DB_DIR.mkdir(parents=True, exist_ok=True)

    # ---------------------------------------------------------
    # Chroma
    # ---------------------------------------------------------

    print("[STEG] Öppnar Chroma DB...")

    client = chromadb.PersistentClient(
        path=str(VECTOR_DB_DIR)
    )

    collection = client.get_or_create_collection(
        name=COLLECTION_NAME
    )

    # ---------------------------------------------------------
    # Model load
    # ---------------------------------------------------------

    print("[STEG] Laddar embedding-modell...")

    model = SentenceTransformer(
        EMBED_MODEL,
        device=DEVICE
    )

    # ---------------------------------------------------------
    # Build documents
    # ---------------------------------------------------------

    documents = []
    metadatas = []
    ids = []

    print("[STEG] Indexerar filer...")

    counter = 0

    for file in tqdm(files):

        path = ROOT / file

        if not path.exists():
            continue

        try:
            content = path.read_text(
                encoding="utf-8",
                errors="ignore"
            )
        except Exception:
            continue

        if not content.strip():
            continue

        chunk_index = 0

        for chunk in chunk_text(content):

            if not chunk.strip():
                continue

            if not is_searchable_file(path, file):
                continue

            # 🔥 E5 FORMAT
            chunk = "passage: " + chunk

            documents.append(chunk)

            metadatas.append({
                "file": file,
                "chunk_index": chunk_index,
                "type": file.split('.')[-1],
                "layer": classify(file),
            })

            ids.append(f"{file}_{counter}")

            counter += 1
            chunk_index += 1

    print(f"[INFO] {len(documents)} textblock skapades")

    # ---------------------------------------------------------
    # Embedding (GPU optimized)
    # ---------------------------------------------------------

    print("[STEG] Genererar embeddings...")

    batch_size = BATCH_SIZE_GPU if DEVICE == "cuda" else BATCH_SIZE_CPU

    print(f"[INFO] Batchstorlek: {batch_size}")

    try:
        embeddings = model.encode(
            documents,
            show_progress_bar=True,
            batch_size=batch_size,
            normalize_embeddings=True,
            convert_to_numpy=True
        )

    except RuntimeError as e:
        print("\n[VARNING] GPU misslyckades, faller tillbaka till CPU...")
        print(e)

        model = SentenceTransformer(
            EMBED_MODEL,
            device="cpu"
        )

        embeddings = model.encode(
            documents,
            show_progress_bar=True,
            batch_size=BATCH_SIZE_CPU,
            normalize_embeddings=True,
            convert_to_numpy=True
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
            metadatas=metadatas[i:j],
            ids=ids[i:j]
        )

    print("\n[KLAR] Vektorindex byggt.")
    print(f"[INFO] Plats: {VECTOR_DB_DIR}")
    print(f"[INFO] Indexerade textblock: {len(documents)}")

# ---------------------------------------------------------

if __name__ == "__main__":
    main()
