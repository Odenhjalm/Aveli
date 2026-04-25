# RETRIEVAL_PIPELINE_AUTHORITY_REMEDIATION_TREE

`input(task="Materialize deterministic DAG task tree for retrieval pipeline authority remediation", mode="generate")`

## Scope

This task tree governs the controlled remediation phase for the retrieval
pipeline issues validated from repo-visible code, contracts, and active
`.repo_index` observability artifacts.

The implementation goal is:

- runtime serves the promoted active build deterministically without MCP
  restart
- observability files expose only source-backed fields
- build results tell the truth about CUDA execution and fallback behavior
- vector integrity validation covers every stored metadata field
- historical task documents cannot surface as active LAW or active current
  truth
- deterministic tests prove the full chain after the authority fixes land

## Parent State

The parent retrieval controller DAG is complete through `T15`.

This tree depends on:

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T15_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_index_build_execution/B01_controller_governed_index_build.md`
- active retrieval artifacts in `.repo_index/`

This tree does not reopen `T01` through `T15`. It is a post-controller
remediation tree for concrete runtime, observability, build-truthfulness,
integrity, corpus-authority, and verification gaps discovered in the live
pipeline.

## Controller Model

Current execution state:

- `RPAR-A01`: `PLANNED`
- `RPAR-B01`: `PLANNED`
- `RPAR-C01`: `PLANNED`
- `RPAR-D01`: `PLANNED`
- `RPAR-E01`: `PLANNED`
- `RPAR-F01`: `PLANNED`

Next executable task:

- `RPAR-A01`

The controller must:

- load `task_manifest.json`
- validate every task file exists
- validate DAG order against `DAG_SUMMARY.md`
- execute tasks in topological order only
- run retrieval before every task using that task's `retrieval_queries`
- perform a pre-change audit before file edits
- perform a post-change audit before marking a task completed
- record verification evidence in the task file before advancing
- stop on any contradiction between active contract truth and implementation

## Materialized Task Order

1. `RPAR-A01` runtime authority
2. `RPAR-B01` observability authority
3. `RPAR-C01` build truthfulness
4. `RPAR-D01` vector integrity authority
5. `RPAR-E01` corpus authority
6. `RPAR-F01` test surface

## Hard Law

`RPAR-A01` is the only valid next task. No later slice may execute first.

`RPAR-B01` must follow immediately after `RPAR-A01`.

`RPAR-E01` is blocked until `RPAR-A01` and `RPAR-B01` are complete.

This tree is intentionally stricter than the minimal dependency requirement:
`RPAR-E01` is deferred until after `RPAR-D01` so corpus authority executes only
after runtime, observability, build truthfulness, and integrity truth are
stabilized.

## Stop Conditions

Stop if no single canonical active-build source can be selected for runtime
freshness.

Stop if any observability field has no single upstream authority source.

Stop if build-truthfulness reporting still depends on synthetic PASS states.

Stop if the integrity validator cannot enumerate the full stored metadata key
set.

Stop if corpus authority would be changed before runtime and observability
authority are locked.

Stop if tests are proposed before slices `A` through `E` stabilize their
acceptance criteria.
