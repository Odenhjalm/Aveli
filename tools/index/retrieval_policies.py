import re
import unicodedata


RETRIEVAL_POLICY_REQUIRED_FIELDS = {
    "normalization_policy",
    "lexical_query_policy",
    "embedding_query_policy",
    "rerank_policy",
    "scoring_policy",
    "evidence_policy",
}

CANONICAL_NORMALIZATION_POLICY = {
    "schema_version": "query_normalization_v1",
    "unicode_normalization": "NFC",
    "strip": True,
    "casefold": True,
    "collapse_whitespace": True,
    "tokenization": "whitespace_v1",
}

CANONICAL_LEXICAL_QUERY_POLICY = {
    "schema_version": "lexical_query_v1",
    "token_source": "persistent_lexical_index",
    "scoring": "bm25_v1",
    "bm25_k1": 1.5,
    "bm25_b": 0.75,
}

CANONICAL_EMBEDDING_QUERY_POLICY = {
    "schema_version": "embedding_query_v1",
    "query_prefix": "query: ",
    "normalize_embeddings": True,
    "batch_size": 1,
}

CANONICAL_RERANK_POLICY = {
    "schema_version": "rerank_v1",
    "enabled": True,
    "batch_size": 16,
    "input_order": "ascending_file_then_doc_id",
    "score_output": "raw_float",
}

CANONICAL_SCORING_POLICY = {
    "schema_version": "score_fusion_v1",
    "formula": "final_score = rerank_score + boost_score",
    "boosts": [],
}

CANONICAL_EVIDENCE_POLICY = {
    "schema_version": "evidence_output_v1",
    "max_snippet_chars": 2500,
    "source_type": "chunk",
}


class RetrievalPolicyError(RuntimeError):
    pass


def canonical_retrieval_policies() -> dict:
    return {
        "normalization_policy": dict(CANONICAL_NORMALIZATION_POLICY),
        "lexical_query_policy": dict(CANONICAL_LEXICAL_QUERY_POLICY),
        "embedding_query_policy": dict(CANONICAL_EMBEDDING_QUERY_POLICY),
        "rerank_policy": dict(CANONICAL_RERANK_POLICY),
        "scoring_policy": {
            **CANONICAL_SCORING_POLICY,
            "boosts": list(CANONICAL_SCORING_POLICY["boosts"]),
        },
        "evidence_policy": dict(CANONICAL_EVIDENCE_POLICY),
    }


def require_policy_object(manifest: dict, field_name: str) -> dict:
    value = manifest.get(field_name)
    if not isinstance(value, dict):
        raise RetrievalPolicyError(f"FEL: index_manifest.json {field_name} maste vara ett JSON-objekt")
    return value


def require_exact_policy(manifest: dict, field_name: str, expected: dict) -> dict:
    policy = require_policy_object(manifest, field_name)
    if policy != expected:
        raise RetrievalPolicyError(f"FEL: index_manifest.json {field_name} matchar inte kanonisk policy")
    return policy


def validate_retrieval_policies(manifest: dict) -> dict:
    missing = sorted(RETRIEVAL_POLICY_REQUIRED_FIELDS - set(manifest))
    if missing:
        raise RetrievalPolicyError(
            "FEL: index_manifest.json saknar retrievalpolicy-falt: " + ", ".join(missing)
        )
    return {
        "normalization_policy": require_exact_policy(
            manifest,
            "normalization_policy",
            CANONICAL_NORMALIZATION_POLICY,
        ),
        "lexical_query_policy": require_exact_policy(
            manifest,
            "lexical_query_policy",
            CANONICAL_LEXICAL_QUERY_POLICY,
        ),
        "embedding_query_policy": require_exact_policy(
            manifest,
            "embedding_query_policy",
            CANONICAL_EMBEDDING_QUERY_POLICY,
        ),
        "rerank_policy": require_exact_policy(
            manifest,
            "rerank_policy",
            CANONICAL_RERANK_POLICY,
        ),
        "scoring_policy": require_exact_policy(
            manifest,
            "scoring_policy",
            CANONICAL_SCORING_POLICY,
        ),
        "evidence_policy": require_exact_policy(
            manifest,
            "evidence_policy",
            CANONICAL_EVIDENCE_POLICY,
        ),
    }


def normalize_query_with_policy(raw_query: str, policy: dict) -> str:
    if policy != CANONICAL_NORMALIZATION_POLICY:
        raise RetrievalPolicyError("FEL: query-normalisering matchar inte manifestets kanoniska policy")
    if not isinstance(raw_query, str):
        raise RetrievalPolicyError("FEL: query maste vara strang")
    normalized = unicodedata.normalize(policy["unicode_normalization"], raw_query)
    if policy["strip"]:
        normalized = normalized.strip()
    if policy["casefold"]:
        normalized = normalized.casefold()
    if policy["collapse_whitespace"]:
        normalized = re.sub(r"\s+", " ", normalized)
    if not normalized:
        raise RetrievalPolicyError("FEL: query ar tom efter kanonisk normalisering")
    return normalized


def tokenize_normalized_query(normalized_query: str, policy: dict) -> list[str]:
    if policy != CANONICAL_NORMALIZATION_POLICY:
        raise RetrievalPolicyError("FEL: query-tokenisering matchar inte manifestets kanoniska policy")
    if policy["tokenization"] != "whitespace_v1":
        raise RetrievalPolicyError("FEL: okand query-tokenisering")
    return normalized_query.split()
