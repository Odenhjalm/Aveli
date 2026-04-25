# FULL CHAIN CONTROLLED EXCAVATION BATCHES

`input(task="Propose controlled full-chain excavation batches for retrieval pipeline authority remediation", mode="generate")`

## Status

BATCH_PLAN_STATUS: `PLANNED`

Created on: `2026-04-25`

This batch plan sequences the `RPAR-*` tasks into one controlled remediation
chain. Each batch has one primary mutation axis, one verification boundary,
and explicit STOP conditions.

## Batch 0 - Runtime Authority

Tasks:

- `RPAR-A01`

Purpose:

- lock one canonical active-build detection rule
- remove or govern stale runtime cache behavior
- force MCP parity with the CLI runtime

Mutation scope:

- `tools/index/search_code.py`
- `tools/mcp/semantic_search_server.py`
- minimal runtime-state support surfaces required by those files

Required verification:

- promote a new build and confirm CLI and long-lived MCP both serve the same
  build without restart
- confirm runtime freshness binds to the canonical promoted artifact state
- confirm no ranking, model, or corpus behavior changed

Stop if:

- no single active-build source can be chosen
- MCP still requires restart to see a promoted build
- runtime freshness fix requires observability or corpus changes to proceed

## Batch 1 - Observability Authority

Tasks:

- `RPAR-B01`

Purpose:

- align observability schema names to real upstream artifacts
- remove phantom and null placeholder fields
- make observability source-backed and deterministic

Mutation scope:

- `tools/index/retrieval_observability.py`
- `tools/index/dependency_authority.py`
- any strictly required build-result serialization surfaces

Required verification:

- diff observability outputs against the live upstream artifact fields
- confirm no field survives without a real source
- confirm aligned names for promotion, dependency, and model health outputs

Stop if:

- any field exists only as an inferred alias
- observability needs runtime semantics changes to stay coherent
- null placeholders remain for values that are already authoritative upstream

## Batch 2 - Build Truthfulness

Tasks:

- `RPAR-C01`

Purpose:

- prove actual CUDA execution rather than CUDA availability
- remove false PASS states
- correct fallback reporting

Mutation scope:

- `tools/index/build_vector_index.py`
- any directly coupled build-result contract surface needed to preserve truth

Required verification:

- controlled CUDA-approved build emits evidence-backed device execution fields
- `device_check` represents actual execution truth
- `no_fallback_used` is derived from real behavior rather than hard-coded

Stop if:

- truthfulness requires model or corpus policy changes
- device proof cannot be measured from the build runtime
- any PASS field still exists without evidence

## Batch 3 - Vector Integrity Authority

Tasks:

- `RPAR-D01`

Purpose:

- define the canonical stored vector metadata contract
- make integrity validation cover all record and collection metadata fields

Mutation scope:

- `tools/index/build_vector_index.py`
- `tools/index/index_artifact_integrity.py`
- directly coupled integrity-contract documentation if required

Required verification:

- builder metadata inventory equals validator coverage
- drift in any stored metadata field fails integrity verification
- vector metadata parity check becomes complete rather than partial

Stop if:

- the full stored metadata key set cannot be enumerated deterministically
- integrity changes require runtime or corpus reclassification work

## Batch 4 - Corpus Authority

Tasks:

- `RPAR-E01`

Purpose:

- define explicit authority hierarchy for retrieval corpus classes
- prevent historical task documents from surfacing as active LAW or current
  truth

Mutation scope:

- `tools/index/build_vector_index.py`
- `tools/index/search_code.py`
- only directly coupled authority/evidence contract surfaces if required

Required verification:

- targeted queries that previously hit stale task narratives no longer surface
  them as active truth
- current authority remains retrievable without historical contamination
- evidence output makes authority class explicit where required

Stop if:

- `RPAR-A01` or `RPAR-B01` is incomplete
- the authority hierarchy is not fully explicit
- corpus fix depends on hidden runtime fallback or ad hoc query suppression

## Batch 5 - Test Surface

Tasks:

- `RPAR-F01`

Purpose:

- encode slices `A` through `E` as deterministic regression and parity gates
- prove the full chain under fresh-process and long-lived-process execution

Mutation scope:

- targeted retrieval tests under `tools/index`
- targeted integration and audit gates under `backend/tests`
- execution evidence updates in this task tree

Required verification:

- promotion to runtime reload correctness
- observability parity
- build truthfulness
- integrity drift detection
- MCP versus CLI parity

Stop if:

- any earlier slice acceptance criteria is still unstable
- tests rely on manual restart, hidden local state, or non-deterministic timing
- a test is asked to compensate for an unresolved production contradiction

## Recommended Execution Strategy

Execute one batch at a time.

After every batch:

- update the corresponding `RPAR-*` task execution record
- update `task_manifest.json` status for completed tasks
- rerun DAG validation
- record verification evidence before proceeding

Do not combine Batch 0 with Batch 1. Runtime authority must be stable before
observability outputs are reinterpreted.

Do not execute Batch 4 before Batches 0 and 1 are complete.

Do not execute Batch 5 until all production slices are complete.
