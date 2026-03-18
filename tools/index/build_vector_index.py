#!/usr/bin/env python3

from pathlib import Path
from typing import Iterable
from sentence_transformers import SentenceTransformer
import chromadb
from tqdm import tqdm

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------

ROOT = Path(__file__).resolve().parents[2]
INDEX_DIR = ROOT / ".repo_index"
FILES_LIST = INDEX_DIR / "files.txt"
VECTOR_DB_DIR = INDEX_DIR / "chroma_db"

# ---------------------------------------------------------
# Config
# ---------------------------------------------------------

COLLECTION_NAME = "aveli_repo"

CHUNK_SIZE = 1200
CHUNK_OVERLAP = 150
BATCH_SIZE = 4000

EMBED_MODEL = "sentence-transformers/all-MiniLM-L6-v2"

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

    if not FILES_LIST.exists():
        raise RuntimeError(
            f"{FILES_LIST} missing. Run repoindex first."
        )

    print("Loading file list...")

    files = [
        line.strip()
        for line in FILES_LIST.read_text().splitlines()
        if line.strip()
    ]

    print(f"{len(files)} files discovered")

    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    VECTOR_DB_DIR.mkdir(parents=True, exist_ok=True)

    # ---------------------------------------------------------
    # Persistent Chroma
    # ---------------------------------------------------------

    print("Opening persistent Chroma DB...")

    client = chromadb.PersistentClient(
        path=str(VECTOR_DB_DIR)
    )

    existing = [c.name for c in client.list_collections()]

    if COLLECTION_NAME in existing:
        print("Deleting existing collection...")
        client.delete_collection(COLLECTION_NAME)

    collection = client.get_or_create_collection(
        name=COLLECTION_NAME
    )

    # ---------------------------------------------------------
    # Load embedding model
    # ---------------------------------------------------------

    print("Loading embedding model...")

    model = SentenceTransformer(EMBED_MODEL)

    documents = []
    metadatas = []
    ids = []

    print("Indexing files...")

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

            documents.append(chunk)

            metadatas.append({
                "file": file,
                "chunk_index": chunk_index
            })

            ids.append(f"{file}_{counter}")

            counter += 1
            chunk_index += 1

    print(f"{len(documents)} chunks generated")

    # ---------------------------------------------------------
    # Generate embeddings
    # ---------------------------------------------------------

    print("Generating embeddings...")

    embeddings = model.encode(
        documents,
        show_progress_bar=True,
        batch_size=64,
        normalize_embeddings=True
    )

    # ---------------------------------------------------------
    # Store vectors
    # ---------------------------------------------------------

    print("Writing to vector DB in batches...")

    for i in tqdm(range(0, len(documents), BATCH_SIZE)):

        j = i + BATCH_SIZE

        collection.add(
            documents=documents[i:j],
            embeddings=embeddings[i:j].tolist(),
            metadatas=metadatas[i:j],
            ids=ids[i:j]
        )

    print("\nVector index built successfully.")

    print("Location:", VECTOR_DB_DIR)
    print("Collection:", COLLECTION_NAME)
    print("Chunks indexed:", len(documents))


# ---------------------------------------------------------

if __name__ == "__main__":
    main()