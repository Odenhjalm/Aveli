from copy import deepcopy
import hashlib
import json
import shutil
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

CANONICAL_CONTRACT_VERSION = "retrieval-v1"
CANONICAL_CHUNK_SIZE = 2000
CANONICAL_CHUNK_OVERLAP = 200
CANONICAL_EMBEDDING_MODEL = "BAAI/bge-m3"
CANONICAL_RERANK_MODEL = "BAAI/bge-reranker-large"
CANONICAL_TOP_K = 16
CANONICAL_VECTOR_CANDIDATE_K = 30
CANONICAL_LEXICAL_CANDIDATE_K = 30
CANONICAL_RANKING_FORMULA = "final_score(doc_id) = rerank_score(doc_id) + boost_score(doc_id)"
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
CANONICAL_RANKING_POLICY = {
    "formula": CANONICAL_RANKING_FORMULA,
    "layer_boosts": {},
    "path_substring_boosts": {},
    "path_suffix_boosts": {},
    "route_override": {
        "enabled": False,
        "score": 0.0,
    },
    "use_rerank": True,
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
    except OSError as exc:
        raise RuntimeError(f"FEL: kunde inte läsa filhuvud för {relative_file}") from exc
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


def try_load_optional_json_object(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return load_json_object(path)
    except (OSError, RuntimeError, json.JSONDecodeError):
        return None


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


def build_canonical_index_manifest(corpus_manifest_hash: str, chunk_manifest_hash: str = "") -> dict:
    return {
        "chunk_manifest_hash": str(chunk_manifest_hash),
        "chunk_overlap": CANONICAL_CHUNK_OVERLAP,
        "chunk_size": CANONICAL_CHUNK_SIZE,
        "classification_rules": deepcopy(CANONICAL_CLASSIFICATION_RULES),
        "contract_version": CANONICAL_CONTRACT_VERSION,
        "corpus_manifest_hash": corpus_manifest_hash,
        "embedding_model": CANONICAL_EMBEDDING_MODEL,
        "lexical_candidate_k": CANONICAL_LEXICAL_CANDIDATE_K,
        "ranking_policy": deepcopy(CANONICAL_RANKING_POLICY),
        "rerank_model": CANONICAL_RERANK_MODEL,
        "top_k": CANONICAL_TOP_K,
        "vector_candidate_k": CANONICAL_VECTOR_CANDIDATE_K,
    }


def validate_classification_rules(classification_rules: object) -> None:
    if not isinstance(classification_rules, dict):
        raise RuntimeError("FEL: classification_rules måste vara ett JSON-objekt")
    if classification_rules != CANONICAL_CLASSIFICATION_RULES:
        raise RuntimeError("FEL: classification_rules matchar inte kanonisk klassificering")

    default_layer = classification_rules.get("default_layer")
    if default_layer not in CANONICAL_LAYERS:
        raise RuntimeError("FEL: classification_rules.default_layer är ogiltig")

    precedence = classification_rules.get("precedence")
    if not isinstance(precedence, list) or not precedence:
        raise RuntimeError("FEL: classification_rules.precedence saknas eller är tom")

    for rule in precedence:
        if not isinstance(rule, dict):
            raise RuntimeError("FEL: classification_rules.precedence innehåller ogiltig regel")
        if str(rule.get("type", "")) not in {"path_substring", "path_suffix"}:
            raise RuntimeError("FEL: classification_rules innehåller ogiltig regeltyp")
        if not str(rule.get("value", "")).strip():
            raise RuntimeError("FEL: classification_rules innehåller tomt regelvärde")
        if str(rule.get("layer", "")).upper() not in CANONICAL_LAYERS:
            raise RuntimeError("FEL: classification_rules innehåller ogiltigt lager")


def validate_ranking_policy(ranking_policy: object) -> None:
    if not isinstance(ranking_policy, dict):
        raise RuntimeError("FEL: ranking_policy måste vara ett JSON-objekt")
    if ranking_policy != CANONICAL_RANKING_POLICY:
        raise RuntimeError("FEL: ranking_policy matchar inte kanonisk rankingpolicy")
    if str(ranking_policy.get("formula", "")) != CANONICAL_RANKING_FORMULA:
        raise RuntimeError("FEL: ranking_policy.formula matchar inte kanonisk formel")


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

    if str(manifest["contract_version"]) != CANONICAL_CONTRACT_VERSION:
        raise RuntimeError("FEL: contract_version matchar inte kanoniskt värde")
    if str(manifest["corpus_manifest_hash"]) != corpus_manifest_hash:
        raise RuntimeError("FEL: corpus_manifest_hash matchar inte search_manifest.txt")
    if int(manifest["chunk_size"]) != CANONICAL_CHUNK_SIZE:
        raise RuntimeError("FEL: chunk_size matchar inte kanoniskt värde")
    if int(manifest["chunk_overlap"]) != CANONICAL_CHUNK_OVERLAP:
        raise RuntimeError("FEL: chunk_overlap matchar inte kanoniskt värde")
    if str(manifest["embedding_model"]) != CANONICAL_EMBEDDING_MODEL:
        raise RuntimeError("FEL: embedding_model matchar inte kanoniskt värde")
    if str(manifest["rerank_model"]) != CANONICAL_RERANK_MODEL:
        raise RuntimeError("FEL: rerank_model matchar inte kanoniskt värde")
    if int(manifest["top_k"]) != CANONICAL_TOP_K:
        raise RuntimeError("FEL: top_k matchar inte kanoniskt värde")
    if int(manifest["vector_candidate_k"]) != CANONICAL_VECTOR_CANDIDATE_K:
        raise RuntimeError("FEL: vector_candidate_k matchar inte kanoniskt värde")
    if int(manifest["lexical_candidate_k"]) != CANONICAL_LEXICAL_CANDIDATE_K:
        raise RuntimeError("FEL: lexical_candidate_k matchar inte kanoniskt värde")

    chunk_manifest_hash = manifest.get("chunk_manifest_hash")
    if not isinstance(chunk_manifest_hash, str):
        raise RuntimeError("FEL: chunk_manifest_hash måste vara en sträng")
    if require_chunk_manifest_hash and not chunk_manifest_hash.strip():
        raise RuntimeError("FEL: chunk_manifest_hash saknas i index_manifest.json")

    validate_classification_rules(manifest.get("classification_rules"))
    validate_ranking_policy(manifest.get("ranking_policy"))


def bootstrap_index_manifest(corpus_manifest_hash: str, path: Path = INDEX_MANIFEST) -> dict:
    existing_manifest = try_load_optional_json_object(path)
    preserved_chunk_manifest_hash = ""

    if existing_manifest is not None:
        existing_chunk_manifest_hash = existing_manifest.get("chunk_manifest_hash", "")
        if isinstance(existing_chunk_manifest_hash, str):
            preserved_chunk_manifest_hash = existing_chunk_manifest_hash

    manifest = build_canonical_index_manifest(
        corpus_manifest_hash=corpus_manifest_hash,
        chunk_manifest_hash=preserved_chunk_manifest_hash,
    )
    if existing_manifest != manifest:
        save_json_object(path, manifest)

    materialized_manifest = load_json_object(path)
    validate_index_manifest(
        materialized_manifest,
        corpus_manifest_hash,
        require_chunk_manifest_hash=False,
    )
    return materialized_manifest


def finalize_index_manifest(
    corpus_manifest_hash: str,
    chunk_manifest_hash: str,
    path: Path = INDEX_MANIFEST,
) -> dict:
    manifest = build_canonical_index_manifest(
        corpus_manifest_hash=corpus_manifest_hash,
        chunk_manifest_hash=chunk_manifest_hash,
    )
    save_json_object(path, manifest)
    materialized_manifest = load_json_object(path)
    validate_index_manifest(
        materialized_manifest,
        corpus_manifest_hash,
        require_chunk_manifest_hash=True,
    )
    return materialized_manifest


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

def build_chunk_artifacts(files: list[str], manifest: dict) -> tuple[list[str], list[dict], list[str], list[dict]]:
    documents = []
    metadatas = []
    ids = []
    chunk_records = []

    chunk_size = int(manifest["chunk_size"])
    chunk_overlap = int(manifest["chunk_overlap"])

    print("[STEG] Indexerar filer...")

    for file in tqdm(files):
        path = ROOT / file

        if not path.exists():
            raise RuntimeError(f"FEL: fil i search_manifest.txt saknas: {file}")

        if not is_searchable_file(path, file):
            continue

        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            raise RuntimeError(f"FEL: kunde inte läsa textinnehåll för {file}") from exc

        content = normalize_ingested_text(content)

        if not content.strip():
            continue

        chunk_index = 0

        for chunk in chunk_text(content, chunk_size=chunk_size, overlap=chunk_overlap):
            if not chunk.strip():
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

    return documents, metadatas, ids, chunk_records

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

    print("\n[STEG] Bootstrappar indexmanifest...")
    manifest = bootstrap_index_manifest(corpus_manifest_hash)

    documents, metadatas, ids, chunk_records = build_chunk_artifacts(files, manifest)

    print(f"[INFO] {len(documents)} textblock skapades")

    contract_version = str(manifest["contract_version"])
    versioned_chunk_records = bind_contract_version(chunk_records, contract_version)
    chunk_manifest_hash = compute_chunk_manifest_hash(versioned_chunk_records)
    manifest = finalize_index_manifest(
        corpus_manifest_hash=corpus_manifest_hash,
        chunk_manifest_hash=chunk_manifest_hash,
    )
    embedding_model = str(manifest["embedding_model"])
    write_chunk_manifest(chunk_records, contract_version=str(manifest["contract_version"]))
    write_lexical_index(documents, ids, manifest)

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
