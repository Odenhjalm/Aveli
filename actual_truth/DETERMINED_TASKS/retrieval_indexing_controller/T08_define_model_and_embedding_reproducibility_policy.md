# T08 - Define Model And Embedding Reproducibility Policy

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: PASS
DEPENDS_ON: [T02, T03]

## Purpose

Define the model, tokenizer, embedding, and device policy required for
reproducible retrieval/indexing behavior.

## Scope

Design only. Do not load models, download models, install dependencies, or test
CUDA.

## Authority References

- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- T02 manifest schema
- T03 preflight contract
- observed current surfaces: `tools/index/requirements.txt`,
  `tools/index/device_utils.py`, `tools/mcp/semantic_search_server.py`

## Dependencies

- T02
- T03

## Expected Outcome

The policy defines CPU as canonical correctness baseline, CUDA as non-canonical
and never required for correctness, no implicit device auto-selection for
canonical output, embedding model name and exact revision/hash lock, tokenizer
revision/hash lock, embedding dimension, query/document prefix behavior,
embedding normalization behavior, rerank model and exact revision/hash when
enabled, local model availability check without download, and dependency lock
sufficient for reproducibility.

## Stop Conditions

- Model can be downloaded implicitly.
- Hardcoded MCP model differs from manifest.
- CUDA availability changes canonical output.
- Dependency set requires CUDA-only packages for canonical correctness.
- Tokenizer behavior is implicit.

## Verification Requirements

- Preflight can prove local model availability without network.
- Manifest contains all model and tokenizer locks.
- CPU execution is the required reproducibility baseline.

## Mutation Rules

No runtime mutation is allowed during this design task. Controller execution may
update this task status and write `T08_execution_result.md` only.

## Output Artifacts

- `T08_execution_result.md`

## Next Transitions

- T10
- T13
