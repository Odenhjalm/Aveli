# T00 - Retrieval Indexing Execution Controller

TYPE: design
OS_ROLE: AGGREGATE
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: []

## Purpose

Define the execution controller that governs Aveli retrieval and indexing work
from authority resolution through verification. This file is the entry document
for the task tree and is not itself an index build, retrieval execution, model
download, or tool implementation.

## Scope

This controller task tree covers only the retrieval/indexing control plane:
corpus authority, index manifest authority, preflight, corpus normalization,
chunking, hashing, artifact structure, model reproducibility, lexical index,
vector index, read-only retrieval, MCP wrapping, Windows enforcement, rebuild
approval, verification, and failure handling.

It does not modify `tools/index/*`, create `.repo_index`, build indexes, run
retrieval, download models, or introduce CUDA.

## Authority References

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `tools/index/*`
- `tools/mcp/semantic_search_server.py`

## Dependencies

None. T00 is controller context and is not an executable dependency for T01
through T17.

## Global Controller Invariants

- Every run begins with `input(task, mode)`.
- T01 through T17 execute by dependency graph only.
- `index_manifest.json` is the proposed single configuration and corpus authority pending T01/T02 execution.
- Query-time retrieval is read-only.
- The controller never auto-builds an index.
- Missing `.repo_index` is a STOP condition, not a rebuild trigger.
- CPU is the canonical embedding baseline.
- Windows interpreter for retrieval/indexing is `.repo_index/.search_venv/Scripts/python.exe`.
- No task may introduce bash-only tooling, `/bin` paths, AF_UNIX, `pgrep`, implicit CUDA, model downloads, or cache authority.

## Stop Conditions

- Any task attempts to build an index.
- Any task creates `.repo_index`.
- Any task downloads a model.
- Any task changes `tools/index/*` before the relevant design and gate tasks are complete.
- Any task introduces a non-controller path for build, indexing, embedding, storage, retrieval, or MCP search.
- Any task mutates outside `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/` during this materialization phase.

## Verification Requirements

- All T01 through T17 task files exist.
- `task_manifest.json` lists T00 through T17.
- Every executable task T01 through T17 has `EXECUTION_STATUS: NOT_STARTED`.
- Every executable task declares exact dependencies matching `DAG_SUMMARY.md`.
- No dependency points to a later undefined task.
- No DAG edge exists outside the approved graph.

## Mutation Rules

This materialization task may create only controller artifacts under:

`actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/`

No other mutation is allowed.

## Next Transitions

After materialization verification passes, the only allowed next execution task is T01.
