# RETRIEVAL PIPELINE AUTHORITY REMEDIATION DAG SUMMARY

## DAG

```text
RPAR-A01
  -> RPAR-B01
    -> RPAR-C01
      -> RPAR-D01
        -> RPAR-E01
          -> RPAR-F01
```

## Node Semantics

| Task | Slice | Type | Status | Meaning |
| --- | --- | --- | --- | --- |
| `RPAR-A01` | `A` | `OWNER` | `PLANNED` | Lock deterministic active-build detection and runtime reload parity between CLI and MCP. |
| `RPAR-B01` | `B` | `OWNER` | `PLANNED` | Align observability outputs to real upstream artifact schemas and remove phantom/null fields. |
| `RPAR-C01` | `C` | `OWNER` | `PLANNED` | Make build execution reports truthful about actual CUDA execution and fallback behavior. |
| `RPAR-D01` | `D` | `OWNER` | `PLANNED` | Expand integrity validation to the full stored vector metadata contract. |
| `RPAR-E01` | `E` | `OWNER` | `PLANNED` | Reclassify or gate historical task documents so stale narrative cannot surface as active truth. |
| `RPAR-F01` | `F` | `GATE` | `PLANNED` | Add deterministic end-to-end and parity verification for slices `A` through `E`. |

## Affected Implementation Surfaces

- `tools/index/search_code.py`
- `tools/mcp/semantic_search_server.py`
- `tools/index/retrieval_observability.py`
- `tools/index/dependency_authority.py`
- `tools/index/build_vector_index.py`
- `tools/index/index_artifact_integrity.py`

## Affected Artifact Surfaces

- `.repo_index/index_manifest.json`
- `.repo_index/promotion_result.json`
- `.repo_index/observability/retrieval_last_build_status.json`
- `.repo_index/observability/retrieval_dependency_health.json`
- `.repo_index/observability/retrieval_model_health.json`

## Affected Verification Surfaces

- `tools/index`
- `backend/tests`
- `actual_truth/DETERMINED_TASKS/retrieval_pipeline_authority_remediation_tree`

## Execution Rule

No task may be marked completed until its task file contains:

- pre-change audit evidence
- materialized output summary
- verification command evidence
- explicit statement that no out-of-slice authority was changed

## Strict Dependency Law

This tree preserves the validated dependency law from the remediation plan:

- `RPAR-A01` must execute first because runtime cache staleness was confirmed
- `RPAR-B01` must execute immediately after `RPAR-A01` because observability
  mismatch was confirmed
- `RPAR-E01` must not execute before `RPAR-A01` and `RPAR-B01`
- `RPAR-F01` is a final verification gate only and may not substitute for any
  earlier remediation slice

## DAG Validity

This DAG is acyclic and materially ordered for full-chain controlled execution.
