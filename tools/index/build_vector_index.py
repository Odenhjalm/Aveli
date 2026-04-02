#!/usr/bin/env python3

import hashlib
import json
import os
import shutil
import sys
import unicodedata
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
SEARCH_MANIFEST = INDEX_DIR / "search_manifest.txt"
INDEX_MANIFEST = INDEX_DIR / "index_manifest.json"
CHUNK_MANIFEST = INDEX_DIR / "chunk_manifest.jsonl"
LEXICAL_INDEX_DIR = INDEX_DIR / "lexical_index"
LEXICAL_INDEX_MANIFEST = LEXICAL_INDEX_DIR / "manifest.json"
LEXICAL_INDEX_DOCUMENTS = LEXICAL_INDEX_DIR / "documents.jsonl"
VECTOR_DB_DIR = INDEX_DIR / "chroma_db"

# ---------------------------------------------------------
# Config
# ---------------------------------------------------------

COLLECTION_NAME = "aveli_repo"

BATCH_SIZE_GPU = 16
BATCH_SIZE_CPU = 32
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
    "ranking_policy",
    "classification_rules",
}

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


def is_searchable_file(path: Path, relative_file: str) -> bool:
    if is_excluded_path(relative_file):
        return False
    if "archive" in relative_file:
        return False
    name = path.name.lower()
    suffix = path.suffix.lower()
    if not (name in SEARCHABLE_FILENAMES or suffix in SEARCHABLE_SUFFIXES):
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

    return normalized.as_posix().lstrip("./")


def classify(path: str, manifest: dict) -> str:
    lowered = path.lower()
    classification_rules = manifest.get("classification_rules", {})

    for rule in classification_rules.get("precedence", []):
        rule_type = rule.get("type")
        value = str(rule.get("value", "")).lower()
        layer = str(rule.get("layer", "")).upper()

        if rule_type == "path_substring" and value in lowered:
            return layer
        if rule_type == "path_suffix" and lowered.endswith(value):
            return layer

    return str(classification_rules.get("default_layer", "OTHER")).upper()


def normalize_ingested_text(text: str) -> str:
    normalized = unicodedata.normalize("NFC", text)
    normalized = normalized.replace("\r\n", "\n").replace("\r", "\n")
    normalized = normalized.replace("\t", "    ")
    return "\n".join(line.rstrip() for line in normalized.split("\n"))


def normalize_document_text(text: str) -> str:
    return text.removeprefix("passage: ").strip()


def tokenize_for_lexical(text: str) -> list[str]:
    return normalize_document_text(text).lower().split()


def compute_sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def compute_sha256_text(content: str) -> str:
    return compute_sha256_bytes(content.encode("utf-8"))


def load_json_object(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError(f"FEL: JSON-objekt forvantas i {path}")
    return data


def save_json_object(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def serialize_chunk_record(record: dict) -> str:
    return json.dumps(record, ensure_ascii=False, sort_keys=True)


def build_canonical_doc_id(file_path: str, chunk_index: int, content_hash: str) -> str:
    normalized_file = normalize_repo_relative_path(file_path)
    identity = f"{normalized_file}\n{int(chunk_index)}\n{content_hash}"
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()


def order_chunk_records(records: list[dict]) -> list[dict]:
    return sorted(
        records,
        key=lambda record: (
            str(record["file"]),
            int(record["chunk_index"]),
            str(record["doc_id"]),
        ),
    )


def render_chunk_manifest(records: list[dict]) -> str:
    ordered_records = order_chunk_records(records)
    return "\n".join(serialize_chunk_record(record) for record in ordered_records)


def compute_chunk_manifest_hash(records: list[dict]) -> str:
    serialized = render_chunk_manifest(records)
    return compute_sha256_text(serialized)


def write_chunk_manifest(records: list[dict], contract_version: str) -> None:
    versioned_records = bind_contract_version(records, contract_version)
    CHUNK_MANIFEST.write_text(render_chunk_manifest(versioned_records), encoding="utf-8")


def bind_contract_version(records: list[dict], contract_version: str) -> list[dict]:
    versioned_records = []
    for record in records:
        versioned_record = dict(record)
        versioned_record["contract_version"] = contract_version
        versioned_records.append(versioned_record)
    return versioned_records


def write_lexical_index(documents: list[str], ids: list[str], manifest: dict) -> None:
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

    LEXICAL_INDEX_DIR.mkdir(parents=True, exist_ok=True)
    LEXICAL_INDEX_DOCUMENTS.write_text(
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
    save_json_object(LEXICAL_INDEX_MANIFEST, lexical_manifest)


def resolve_index_manifest(corpus_manifest_hash: str, chunk_manifest_hash: str) -> dict:
    if not INDEX_MANIFEST.exists():
        raise RuntimeError(f"FEL: index_manifest.json saknas vid {INDEX_MANIFEST}")

    manifest = load_json_object(INDEX_MANIFEST)

    manifest["corpus_manifest_hash"] = corpus_manifest_hash
    manifest["chunk_manifest_hash"] = chunk_manifest_hash

    missing = sorted(INDEX_MANIFEST_REQUIRED_FIELDS - set(manifest))
    if missing:
        raise RuntimeError(
            "FEL: index_manifest.json saknar falt: " + ", ".join(missing)
        )

    save_json_object(INDEX_MANIFEST, manifest)
    return manifest

# ---------------------------------------------------------
# Chunking
# ---------------------------------------------------------

def chunk_text(text: str, chunk_size: int, overlap: int) -> Iterable[str]:

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

    if not SEARCH_MANIFEST.exists():
        raise RuntimeError(
            f"{SEARCH_MANIFEST} saknas. Bygg repoindex först."
        )

    print("\n[STEG] Läser fillista...")

    files = [
        line.strip()
        for line in SEARCH_MANIFEST.read_text().splitlines()
        if line.strip()
    ]

    excluded_paths = [file for file in files if is_excluded_path(file)]
    if excluded_paths:
        raise RuntimeError(
            "search_manifest.txt innehaller exkluderade paths: "
            + ", ".join(excluded_paths[:5])
        )

    print(f"[INFO] {len(files)} filer hittades")

    corpus_manifest_hash = compute_sha256_bytes(SEARCH_MANIFEST.read_bytes())

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

    collection = client.get_or_create_collection(name=COLLECTION_NAME)

    # ---------------------------------------------------------
    # Model load
    # ---------------------------------------------------------

    # ---------------------------------------------------------
    # Build documents
    # ---------------------------------------------------------

    documents = []
    metadatas = []
    ids = []
    chunk_records = []

    if not INDEX_MANIFEST.exists():
        raise RuntimeError(f"FEL: index_manifest.json saknas vid {INDEX_MANIFEST}")

    manifest = load_json_object(INDEX_MANIFEST)
    missing = sorted(INDEX_MANIFEST_REQUIRED_FIELDS - set(manifest))
    if missing:
        raise RuntimeError(
            "FEL: index_manifest.json saknar falt: " + ", ".join(missing)
        )

    chunk_size = int(manifest["chunk_size"])
    chunk_overlap = int(manifest["chunk_overlap"])
    embedding_model = str(manifest["embedding_model"])

    print("[STEG] Indexerar filer...")

    for file in tqdm(files):

        path = ROOT / file

        if not path.exists():
            continue

        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        content = normalize_ingested_text(content)

        if not content.strip():
            continue

        chunk_index = 0

        for chunk in chunk_text(content, chunk_size=chunk_size, overlap=chunk_overlap):

            if not chunk.strip():
                continue

            if not is_searchable_file(path, file):
                continue

            document = chunk
            content_hash = compute_sha256_text("passage: " + chunk)
            doc_id = build_canonical_doc_id(file, chunk_index, content_hash)

            documents.append(document)

            metadata = {
                "file": file,
                "chunk_index": chunk_index,
                "type": file.split('.')[-1],
                "layer": classify(file, manifest),
                "source_type": "chunk",
            }
            metadatas.append(metadata)
            ids.append(doc_id)
            chunk_records.append({
                "doc_id": doc_id,
                "file": file,
                "chunk_index": chunk_index,
                "layer": metadata["layer"],
                "source_type": "chunk",
                "content_hash": content_hash,
            })

            chunk_index += 1

    print(f"[INFO] {len(documents)} textblock skapades")

    contract_version = str(manifest["contract_version"])
    versioned_chunk_records = bind_contract_version(chunk_records, contract_version)
    chunk_manifest_hash = compute_chunk_manifest_hash(versioned_chunk_records)
    manifest = resolve_index_manifest(
        corpus_manifest_hash=corpus_manifest_hash,
        chunk_manifest_hash=chunk_manifest_hash,
    )
    embedding_model = str(manifest["embedding_model"])
    write_chunk_manifest(chunk_records, contract_version=str(manifest["contract_version"]))
    write_lexical_index(documents, ids, manifest)
    collection.modify(
        metadata={
            "contract_version": str(manifest["contract_version"]),
            "chunk_manifest_hash": str(manifest["chunk_manifest_hash"]),
        }
    )

    # ---------------------------------------------------------
    # Model load
    # ---------------------------------------------------------

    print("[STEG] Laddar embedding-modell...")

    try:
        model = SentenceTransformer(
            embedding_model,
            device=DEVICE
        )
    except RuntimeError as e:
        raise RuntimeError(
            f"FEL: embedding-modellen kunde inte laddas på enhet {DEVICE}"
        ) from e

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
        raise RuntimeError(
            f"FEL: embedding-generering misslyckades på enhet {DEVICE}"
        ) from e

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
