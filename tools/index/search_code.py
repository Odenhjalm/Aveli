import hashlib
import json
import math
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INDEX_TOOL_ROOT = Path(__file__).resolve().parent
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"

if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
        f"{CANONICAL_SEARCH_PYTHON}"
    )

if str(INDEX_TOOL_ROOT) not in sys.path:
    sys.path.insert(0, str(INDEX_TOOL_ROOT))

from model_authority import (
    ModelAuthorityError,
    validate_model_authority_for_manifest,
)
from index_artifact_integrity import (
    IndexArtifactIntegrityError,
    validate_index_artifact_integrity,
)
from retrieval_policies import (
    RetrievalPolicyError,
    normalize_query_with_policy,
    tokenize_normalized_query,
    validate_retrieval_policies,
)
from dependency_authority import (
    DependencyAuthorityError,
    require_valid_d01_pass_from_environment,
)
from retrieval_observability import (
    RETRIEVAL_QUERY_TRACE_PATH,
    RetrievalObservabilityError,
    append_jsonl,
    base_surface,
    utc_now_iso,
)

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
    "normalization_policy",
    "lexical_query_policy",
    "embedding_query_policy",
    "rerank_policy",
    "scoring_policy",
    "evidence_policy",
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

CANONICAL_EVIDENCE_FIELDS = {"file", "layer", "snippet", "source_type", "score"}
CANONICAL_SOURCE_TYPES = {"chunk", "ast", "context"}
CANONICAL_LAYERS = {"LAW", "ROUTE", "SERVICE", "DB", "POLICY", "SCHEMA", "MODEL", "OTHER"}
REQUEST_ID_ENV_VARS = (
    "AVELI_RETRIEVAL_REQUEST_ID",
    "AVELI_REQUEST_ID",
    "MCP_REQUEST_ID",
)

_RUNTIME_STATE = None


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def resolve_request_id(trace_id: str) -> str:
    for env_var in REQUEST_ID_ENV_VARS:
        value = os.environ.get(env_var, "").strip()
        if value:
            return value
    return trace_id


def model_trace_bindings(runtime_state: dict) -> dict:
    models = runtime_state.get("model_authority", {}).get("models", {})
    trace_models = {}
    for role in ("embedding", "rerank"):
        binding = models.get(role, {})
        if not isinstance(binding, dict):
            trace_models[role] = {"model_id": None, "model_revision": None}
            continue
        trace_models[role] = {
            "model_id": binding.get("model_id"),
            "model_revision": binding.get("model_revision"),
        }
    return trace_models


def timed_stage(stage_timings: dict, stage_name: str, callable_):
    stage_started = time.perf_counter()
    try:
        return callable_()
    finally:
        stage_timings[stage_name] = round((time.perf_counter() - stage_started) * 1000.0, 3)


def emit_query_trace(trace_record: dict) -> None:
    try:
        append_jsonl(RETRIEVAL_QUERY_TRACE_PATH, trace_record)
    except RetrievalObservabilityError as exc:
        raise SystemExit("FEL: querytrace kunde inte skrivas till kanonisk observability-yta") from exc


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
    try:
        validate_retrieval_policies(manifest)
    except RetrievalPolicyError as exc:
        raise SystemExit(str(exc)) from exc


def validate_runtime_model_authority(manifest: dict) -> dict:
    try:
        return validate_model_authority_for_manifest(ROOT, manifest)
    except ModelAuthorityError as exc:
        raise SystemExit(str(exc)) from exc


def validate_runtime_dependency_authority() -> dict:
    try:
        return require_valid_d01_pass_from_environment(ROOT)
    except DependencyAuthorityError as exc:
        raise SystemExit(str(exc)) from exc


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


def normalize_query(raw_query: str, policies: dict) -> str:
    try:
        return normalize_query_with_policy(raw_query, policies["normalization_policy"])
    except RetrievalPolicyError as exc:
        raise SystemExit(str(exc)) from exc


def normalize_document_text(text: str) -> str:
    return text


def open_vector_collection():
    try:
        from chromadb import PersistentClient

        client = PersistentClient(path=DB_PATH)
        return client.get_collection(COLLECTION_NAME)
    except Exception as exc:
        raise SystemExit(
            f"FEL: vektorindexets samling saknas eller kan inte oppnas i {DB_PATH}"
        ) from exc


def validate_runtime_artifact_integrity(collection) -> dict:
    try:
        return validate_index_artifact_integrity(
            root=ROOT,
            index_root=ROOT / ".repo_index",
            manifest_path=INDEX_MANIFEST,
            chunk_manifest_path=CHUNK_MANIFEST,
            chroma_db_dir=Path(DB_PATH),
            lexical_index_dir=LEXICAL_INDEX_DIR,
            collection=collection,
        )
    except IndexArtifactIntegrityError as exc:
        raise SystemExit(str(exc)) from exc


def load_sentence_transformer_classes():
    try:
        from sentence_transformers import CrossEncoder, SentenceTransformer
    except Exception as exc:
        raise SystemExit("FEL: sentence-transformers saknas i kanonisk retrievalmiljo") from exc
    return SentenceTransformer, CrossEncoder


def load_warm_model_surface(model_authority: dict) -> dict:
    SentenceTransformer, CrossEncoder = load_sentence_transformer_classes()
    embedding_binding = model_authority["models"].get("embedding")
    rerank_binding = model_authority["models"].get("rerank")
    if not isinstance(embedding_binding, dict) or not isinstance(rerank_binding, dict):
        raise SystemExit("FEL: modellauktoritet saknar embedding- eller rerank-bindning")

    try:
        embedding_model = SentenceTransformer(
            str(embedding_binding["local_path"]),
            device="cpu",
            local_files_only=True,
            trust_remote_code=False,
        )
    except Exception as exc:
        raise SystemExit("FEL: embeddingmodell kunde inte varmas fran kanonisk modellauktoritet") from exc

    try:
        rerank_model = CrossEncoder(
            str(rerank_binding["local_path"]),
            device="cpu",
            local_files_only=True,
            trust_remote_code=False,
        )
    except Exception as exc:
        raise SystemExit("FEL: rerankmodell kunde inte varmas fran kanonisk modellauktoritet") from exc

    return {
        "embedding": embedding_model,
        "rerank": rerank_model,
        "authority_path": model_authority["authority_path_text"],
    }


def build_lexical_runtime_index(lexical_records: list[dict], lexical_manifest: dict) -> dict:
    postings: dict[str, list[tuple[str, int, int]]] = {}
    doc_lengths: dict[str, int] = {}
    for record in lexical_records:
        doc_id = str(record.get("doc_id", ""))
        length = int(record.get("length", 0))
        term_freqs = record.get("term_freqs")
        if not doc_id or not isinstance(term_freqs, dict):
            raise SystemExit("FEL: lexical-indexet saknar lagrade termfrekvenser")
        doc_lengths[doc_id] = length
        for token, raw_term_freq in term_freqs.items():
            term_freq = int(raw_term_freq)
            if term_freq <= 0:
                raise SystemExit("FEL: lexical-indexet innehaller ogiltig termfrekvens")
            postings.setdefault(str(token), []).append((doc_id, term_freq, length))

    for token in postings:
        postings[token].sort(key=lambda item: item[0])

    return {
        "postings": postings,
        "doc_lengths": doc_lengths,
        "doc_count": int(lexical_manifest["doc_count"]),
        "avg_doc_length": float(lexical_manifest["avg_doc_length"]),
        "document_frequency": lexical_manifest["document_frequency"],
    }


def load_runtime_state() -> dict:
    global _RUNTIME_STATE

    if _RUNTIME_STATE is not None:
        return _RUNTIME_STATE

    dependency_authority = validate_runtime_dependency_authority()
    validate_canonical_index_health()
    index_manifest = load_index_manifest()
    policies = validate_retrieval_policies(index_manifest)
    model_authority = validate_runtime_model_authority(index_manifest)
    collection = open_vector_collection()
    artifact_integrity = validate_runtime_artifact_integrity(collection)
    lexical_runtime_index = build_lexical_runtime_index(
        artifact_integrity["lexical_records"],
        artifact_integrity["lexical_manifest"],
    )
    warm_models = load_warm_model_surface(model_authority)

    _RUNTIME_STATE = {
        "index_manifest": artifact_integrity["manifest"],
        "dependency_authority": dependency_authority,
        "retrieval_policies": policies,
        "model_authority": model_authority,
        "warm_models": warm_models,
        "artifact_integrity": {
            "status": artifact_integrity["status"],
            "artifact_set": artifact_integrity["artifact_set"],
            "chunk_manifest": artifact_integrity["chunk_manifest"],
            "lexical_index": artifact_integrity["lexical_index"],
            "vector_index": artifact_integrity["vector_index"],
        },
        "lexical_manifest": artifact_integrity["lexical_manifest"],
        "lexical_records": artifact_integrity["lexical_records"],
        "lexical_runtime_index": lexical_runtime_index,
        "chunk_records": artifact_integrity["chunk_records"],
        "chunk_records_by_doc_id": {
            str(record["doc_id"]): record
            for record in artifact_integrity["chunk_records"]
        },
        "collection": collection,
    }
    return _RUNTIME_STATE


def preflight_runtime_prerequisites() -> None:
    load_runtime_state()


def lexical_search(normalized_query: str, runtime_state: dict, top_n: int) -> list[str]:
    policies = runtime_state["retrieval_policies"]
    lexical_policy = policies["lexical_query_policy"]
    try:
        query_tokens = tokenize_normalized_query(
            normalized_query,
            policies["normalization_policy"],
        )
    except RetrievalPolicyError as exc:
        raise SystemExit(str(exc)) from exc
    if not query_tokens:
        raise SystemExit("FEL: query saknar token efter kanonisk normalisering")

    lexical_index = runtime_state["lexical_runtime_index"]
    postings = lexical_index["postings"]
    total_docs = int(lexical_index["doc_count"])
    avg_doc_length = float(lexical_index["avg_doc_length"])
    document_frequency = lexical_index["document_frequency"]
    bm25_k1 = float(lexical_policy["bm25_k1"])
    bm25_b = float(lexical_policy["bm25_b"])

    scored_by_doc_id: dict[str, float] = {}
    for token in query_tokens:
        doc_freq = int(document_frequency.get(token, 0))
        if doc_freq <= 0 or total_docs <= 0:
            continue
        idf = math.log(1.0 + ((total_docs - doc_freq + 0.5) / (doc_freq + 0.5)))
        for doc_id, term_freq, length in postings.get(token, []):
            normalized_length = max(1, int(length))
            numerator = term_freq * (bm25_k1 + 1.0)
            denominator = term_freq + bm25_k1 * (1.0 - bm25_b + bm25_b * (normalized_length / avg_doc_length))
            scored_by_doc_id[doc_id] = scored_by_doc_id.get(doc_id, 0.0) + idf * (numerator / denominator)

    scored = [
        (doc_id, score)
        for doc_id, score in scored_by_doc_id.items()
        if score > 0.0 and math.isfinite(score)
    ]
    scored.sort(key=lambda item: (-item[1], item[0]))
    return [doc_id for doc_id, _ in scored[:top_n]]


def normalize_file_for_order(file_path: str) -> str:
    path = Path(file_path)
    if path.is_absolute():
        try:
            path = path.resolve().relative_to(ROOT)
        except ValueError as exc:
            raise SystemExit("FEL: evidensfil ligger utanfor repo-root") from exc
    normalized = Path(path.as_posix())
    if normalized.is_absolute() or ".." in normalized.parts:
        raise SystemExit("FEL: evidensfil ar inte repo-relativt normaliserad")
    return normalized.as_posix().lstrip("./")


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


def build_result_content(doc: str, source_type: str, evidence_policy: dict) -> tuple[str, str]:
    if source_type != evidence_policy["source_type"]:
        raise SystemExit("FEL: evidensens source_type matchar inte manifestets evidenspolicy")
    max_snippet_chars = int(evidence_policy["max_snippet_chars"])
    return source_type, normalize_document_text(doc)[:max_snippet_chars]


def validate_evidence_object(entry: dict) -> None:
    if set(entry) != CANONICAL_EVIDENCE_FIELDS:
        raise SystemExit("FEL: evidensobjektet matchar inte kanonisk form")
    if not isinstance(entry["file"], str) or not entry["file"]:
        raise SystemExit("FEL: evidens.file maste vara en icke-tom strang")
    if str(entry["layer"]) not in CANONICAL_LAYERS:
        raise SystemExit("FEL: evidens.layer ar inte kanoniskt")
    if not isinstance(entry["snippet"], str):
        raise SystemExit("FEL: evidens.snippet maste vara strang")
    if str(entry["source_type"]) not in CANONICAL_SOURCE_TYPES:
        raise SystemExit("FEL: evidens.source_type ar inte kanoniskt")
    if not isinstance(entry["score"], float) or not math.isfinite(entry["score"]):
        raise SystemExit("FEL: evidens.score maste vara en finit float")


def build_output_entry(entry: dict, final_score: float, index_manifest: dict, evidence_policy: dict) -> dict:
    meta = entry["meta"]
    normalized_file = normalize_file_for_order(str(meta["file"]))
    source_type, snippet = build_result_content(str(entry["doc"]), str(meta["source_type"]), evidence_policy)
    output_entry = {
        "file": normalized_file,
        "layer": classify(normalized_file, index_manifest),
        "snippet": snippet,
        "source_type": source_type,
        "score": float(final_score),
    }
    validate_evidence_object(output_entry)
    return output_entry


def render_results_text(entries: list[dict], top_k: int) -> str:
    lines = ["", "================ RESULTAT ================", ""]
    printed = False

    for entry in entries:
        printed = True

        file_path = entry.get("file", "OKAND")
        score = float(entry.get("score", 0.0))
        content = str(entry.get("snippet", ""))

        lines.append(f"[SIMILARITET: 0.0000 | SLUTPOANG: {score:.4f}]")
        lines.append(f"FIL: {file_path}")
        lines.append("-" * 60)
        lines.append(content)
        lines.append("")

        if len([line for line in lines if line.startswith("FIL: ")]) >= top_k:
            break

    if not printed:
        lines.append("INGA SOKRESULTAT")

    return "\n".join(lines) + "\n"


def render_results(entries: list[dict], top_k: int) -> None:
    print(render_results_text(entries, top_k=top_k), end="")


def fetch_collection_entries(collection, doc_ids: list[str], chunk_records_by_doc_id: dict[str, dict]) -> dict[str, dict]:
    if not doc_ids:
        return {}

    result = collection.get(ids=doc_ids, include=["documents", "metadatas"])
    returned_ids = [str(doc_id) for doc_id in (result.get("ids") or [])]
    if set(returned_ids) != set(doc_ids):
        raise SystemExit("FEL: vektorindexet returnerade inte exakt begart kandidatset")
    entries = {}

    for doc_id, doc, meta in zip(returned_ids, result.get("documents") or [], result.get("metadatas") or []):
        if doc_id not in chunk_records_by_doc_id:
            raise SystemExit("FEL: kandidat saknas i chunkmanifestet")
        if not isinstance(doc, str):
            raise SystemExit("FEL: kandidatdokument saknar text")
        if not isinstance(meta, dict):
            raise SystemExit("FEL: kandidatdokument saknar metadata")
        if str(meta.get("doc_id", "")) != doc_id:
            raise SystemExit("FEL: kandidatmetadata doc_id matchar inte vektorindex")

        entries[doc_id] = {
            "id": doc_id,
            "doc": doc,
            "meta": meta,
        }

    if set(entries) != set(doc_ids):
        raise SystemExit("FEL: kandidatmaterialisering matchar inte kandidatunion")
    return entries


def encode_query_embedding(normalized_query: str, runtime_state: dict) -> list[float]:
    policy = runtime_state["retrieval_policies"]["embedding_query_policy"]
    query_text = str(policy["query_prefix"]) + normalized_query
    model = runtime_state["warm_models"].get("embedding")
    if model is None:
        raise SystemExit("FEL: varm embeddingmodell saknas i retrievalruntime")
    try:
        matrix = model.encode(
            [query_text],
            batch_size=int(policy["batch_size"]),
            normalize_embeddings=bool(policy["normalize_embeddings"]),
            show_progress_bar=False,
            convert_to_numpy=True,
        )
    except Exception as exc:
        raise SystemExit("FEL: query-embedding misslyckades i varm retrievalruntime") from exc
    if len(matrix) != 1:
        raise SystemExit("FEL: query-embedding returnerade fel antal vektorer")
    vector = [float(value) for value in matrix[0]]
    if not vector or not all(math.isfinite(value) for value in vector):
        raise SystemExit("FEL: query-embedding ar inte en finit vektor")
    expected_dimension = int(runtime_state["artifact_integrity"]["vector_index"]["embedding_dimension"])
    if len(vector) != expected_dimension:
        raise SystemExit("FEL: query-embeddingdimension matchar inte aktivt vektorindex")
    return vector


def query_vector_index(query_embedding: list[float], runtime_state: dict, top_n: int) -> list[str]:
    collection = runtime_state["collection"]
    try:
        result = collection.query(
            query_embeddings=[query_embedding],
            n_results=top_n,
            include=["metadatas", "distances"],
        )
    except Exception as exc:
        raise SystemExit("FEL: vektorkandidater kunde inte hamtas fran aktivt Chroma-index") from exc
    ids_batches = result.get("ids")
    if not isinstance(ids_batches, list) or len(ids_batches) != 1 or not isinstance(ids_batches[0], list):
        raise SystemExit("FEL: vektorindexet returnerade ogiltig kandidatstruktur")
    vector_doc_ids = [str(doc_id) for doc_id in ids_batches[0]]
    if len(vector_doc_ids) > top_n:
        raise SystemExit("FEL: vektorindexet returnerade fler kandidater an manifestgransen")
    if len(set(vector_doc_ids)) != len(vector_doc_ids):
        raise SystemExit("FEL: vektorindexet returnerade duplicerade kandidater")
    valid_doc_ids = set(runtime_state["chunk_records_by_doc_id"])
    if any(doc_id not in valid_doc_ids for doc_id in vector_doc_ids):
        raise SystemExit("FEL: vektorindexet returnerade kandidat utan chunkmanifestpost")
    return vector_doc_ids


def vector_search(normalized_query: str, runtime_state: dict, top_n: int) -> list[str]:
    query_embedding = encode_query_embedding(normalized_query, runtime_state)
    return query_vector_index(query_embedding, runtime_state, top_n)


def union_candidate_doc_ids(lexical_doc_ids: list[str], vector_doc_ids: list[str], runtime_state: dict) -> list[str]:
    chunk_records_by_doc_id = runtime_state["chunk_records_by_doc_id"]
    candidate_ids = set(lexical_doc_ids) | set(vector_doc_ids)
    if any(doc_id not in chunk_records_by_doc_id for doc_id in candidate_ids):
        raise SystemExit("FEL: kandidatunion innehaller doc_id utan chunkmanifestpost")
    return sorted(
        candidate_ids,
        key=lambda doc_id: (
            normalize_file_for_order(str(chunk_records_by_doc_id[doc_id]["file"])),
            doc_id,
        ),
    )


def boost_score_for_candidate(scoring_policy: dict) -> float:
    if scoring_policy["boosts"] != []:
        raise SystemExit("FEL: scoring_policy.boosts maste vara tom for denna kontraktsversion")
    return 0.0


def rerank_candidates(normalized_query: str, candidate_entries: dict[str, dict], runtime_state: dict) -> list[tuple[str, dict, float]]:
    rerank_policy = runtime_state["retrieval_policies"]["rerank_policy"]
    scoring_policy = runtime_state["retrieval_policies"]["scoring_policy"]
    if rerank_policy["enabled"] is not True:
        raise SystemExit("FEL: rerank ar obligatorisk for denna retrievalkontraktversion")
    rerank_model = runtime_state["warm_models"].get("rerank")
    if rerank_model is None:
        raise SystemExit("FEL: varm rerankmodell saknas i retrievalruntime")

    ordered_items = sorted(
        candidate_entries.items(),
        key=lambda item: (
            normalize_file_for_order(str(item[1]["meta"]["file"])),
            item[0],
        ),
    )
    pairs = [
        [normalized_query, str(entry["doc"])]
        for _, entry in ordered_items
    ]
    if not pairs:
        return []
    try:
        raw_scores = rerank_model.predict(
            pairs,
            batch_size=int(rerank_policy["batch_size"]),
            show_progress_bar=False,
            apply_softmax=False,
            convert_to_numpy=True,
        )
    except Exception as exc:
        raise SystemExit("FEL: begransad rerank misslyckades i varm retrievalruntime") from exc
    scores = [float(score) for score in raw_scores]
    if len(scores) != len(ordered_items):
        raise SystemExit("FEL: rerank returnerade fel antal scorer")

    scored_entries = []
    boost_score = boost_score_for_candidate(scoring_policy)
    for (doc_id, entry), rerank_score in zip(ordered_items, scores):
        if not math.isfinite(rerank_score):
            raise SystemExit("FEL: rerank_score maste vara finit")
        final_score = rerank_score + boost_score
        if not math.isfinite(final_score):
            raise SystemExit("FEL: final_score maste vara finit")
        scored_entries.append((doc_id, entry, final_score))

    scored_entries.sort(
        key=lambda item: (
            -item[2],
            normalize_file_for_order(str(item[1]["meta"]["file"])),
            item[0],
        )
    )
    return scored_entries


def execute_query(raw_query: str, runtime_state: dict) -> tuple[list[dict], int]:
    query_hash = sha256_text(raw_query)
    started_at_utc = utc_now_iso()
    started_perf = time.perf_counter()
    trace_id = sha256_text(f"retrieval_query_trace_v1:{started_at_utc}:{query_hash}")
    request_id = resolve_request_id(trace_id)
    normalized_query_hash = None
    stage_timings: dict[str, float] = {}
    candidate_counts = {
        "lexical": 0,
        "vector": 0,
        "union": 0,
        "rerank_input": 0,
        "rerank_output": 0,
    }
    evidence_count = 0
    trace_status = "FAIL"
    failure_code = "preflight_failed"
    current_stage = "preflight"

    index_manifest = runtime_state["index_manifest"]
    top_k = 0

    try:
        validate_flat_manifest_fields(index_manifest)
        if "warm_models" not in runtime_state:
            raise SystemExit("FEL: retrievalruntime ar inte varm")

        policies = runtime_state["retrieval_policies"]
        current_stage = "normalization"
        normalized_query = timed_stage(
            stage_timings,
            "normalization_ms",
            lambda: normalize_query(raw_query, policies),
        )
        normalized_query_hash = sha256_text(normalized_query)
        lexical_candidate_k = int(index_manifest["lexical_candidate_k"])
        vector_candidate_k = int(index_manifest["vector_candidate_k"])
        top_k = int(index_manifest["top_k"])

        current_stage = "lexical_search"
        lexical_doc_ids = timed_stage(
            stage_timings,
            "lexical_search_ms",
            lambda: lexical_search(normalized_query, runtime_state, lexical_candidate_k),
        )
        candidate_counts["lexical"] = len(lexical_doc_ids)

        current_stage = "vector_embedding"
        query_embedding = timed_stage(
            stage_timings,
            "vector_embedding_ms",
            lambda: encode_query_embedding(normalized_query, runtime_state),
        )

        current_stage = "vector_retrieval"
        vector_doc_ids = timed_stage(
            stage_timings,
            "vector_retrieval_ms",
            lambda: query_vector_index(query_embedding, runtime_state, vector_candidate_k),
        )
        candidate_counts["vector"] = len(vector_doc_ids)

        current_stage = "candidate_union"
        candidate_doc_ids = timed_stage(
            stage_timings,
            "candidate_union_ms",
            lambda: union_candidate_doc_ids(lexical_doc_ids, vector_doc_ids, runtime_state),
        )
        candidate_counts["union"] = len(candidate_doc_ids)

        candidate_entries = fetch_collection_entries(
            runtime_state["collection"],
            candidate_doc_ids,
            runtime_state["chunk_records_by_doc_id"],
        )
        candidate_counts["rerank_input"] = len(candidate_entries)

        current_stage = "rerank"
        scored_entries = timed_stage(
            stage_timings,
            "rerank_ms",
            lambda: rerank_candidates(normalized_query, candidate_entries, runtime_state),
        )
        candidate_counts["rerank_output"] = len(scored_entries)

        current_stage = "evidence_emission"
        evidence_policy = policies["evidence_policy"]

        def build_evidence_entries() -> list[dict]:
            output = [
                build_output_entry(entry, final_score, index_manifest, evidence_policy)
                for _, entry, final_score in scored_entries[:top_k]
            ]
            for entry in output:
                validate_evidence_object(entry)
            return output

        output_entries = timed_stage(
            stage_timings,
            "evidence_emission_ms",
            build_evidence_entries,
        )
        evidence_count = len(output_entries)
        trace_status = "PASS"
        failure_code = None
        return output_entries, top_k
    except SystemExit:
        failure_code = f"{current_stage}_failed"
        raise
    except Exception:
        failure_code = f"{current_stage}_failed"
        raise
    finally:
        finished_at_utc = utc_now_iso()
        trace_record = base_surface(
            "retrieval_query_trace",
            trace_status,
            generated_at_utc=finished_at_utc,
        )
        trace_record.update(
            {
                "trace_id": trace_id,
                "request_id": request_id,
                "started_at_utc": started_at_utc,
                "duration_ms": round((time.perf_counter() - started_perf) * 1000.0, 3),
                "failure_code": failure_code,
                "query_hash": query_hash,
                "normalized_query_hash": normalized_query_hash,
                "models": model_trace_bindings(runtime_state),
                "stage_timings": stage_timings,
                "candidate_counts": candidate_counts,
                "evidence_count": evidence_count,
            }
        )
        emit_query_trace(trace_record)


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
        print("FEL: Ingen fraga angavs")
        sys.exit(1)

    dispatch_query(raw_query, output_format=output_format)


if __name__ == "__main__":
    main()
