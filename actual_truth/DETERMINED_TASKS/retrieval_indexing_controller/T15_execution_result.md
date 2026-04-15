# T15 Execution Result - Controller Execution Loop

TASK_ID: T15
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T15_define_controller_execution_loop.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T05_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T06_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T07_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T08_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T09_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T10_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T11_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T12_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T13_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T14_execution_result.md`
- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `tools/index/ENVIRONMENT_SETUP.sh`
- `tools/index/analyze_results.py`
- `tools/index/ast_extract.py`
- `tools/index/build_repo_index.sh`
- `tools/index/build_vector_index.py`
- `tools/index/codex_query.py`
- `tools/index/device_utils.py`
- `tools/index/requirements.txt`
- `tools/index/run_codex.py`
- `tools/index/run_codex_auto.py`
- `tools/index/search_code.py`
- `tools/index/semantic_search.sh`
- `tools/index/test_build_vector_index_manifest_bootstrap.py`
- `tools/index/validate_codex.py`
- `tools/mcp/semantic_search_server.py`

## Controller State Before T15

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `PASS`.
- `T05` was repo-visible `PASS`.
- `T06` was repo-visible `PASS`.
- `T07` was repo-visible `PASS`.
- `T08` was repo-visible `PASS`.
- `T09` was repo-visible `PASS`.
- `T10` was repo-visible `PASS`.
- `T11` was repo-visible `PASS`.
- `T12` was repo-visible `PASS`.
- `T13` was repo-visible `PASS`.
- `T14` was repo-visible `PASS`.
- `T15` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T15` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T15 defines the deterministic controller execution loop that all future
retrieval, indexing, MCP, build, verification, and artifact state transitions
must use. The loop is controller-first, task-explicit, mode-explicit,
single-task, fail-closed, and non-advancing.

T15 does not implement the controller, does not modify runtime tools, does not
create `.repo_index`, does not write staging artifacts, does not install
dependencies, does not download or load models, does not execute CUDA, does not
run retrieval, and does not build an index.

## T15 Execution Plan

1. Load the T15 task file and controller state artifacts.
2. Verify T01 through T14 are repo-visible `PASS`.
3. Verify T15 is repo-visible `NOT_STARTED`.
4. Verify T15 is the only eligible next task.
5. Confirm `.repo_index` is absent.
6. Audit current runtime drift surfaces against controller-first execution.
7. Define the deterministic controller loop, input model, preflight integration,
   mode separation, state transitions, and failure handling.
8. Materialize only the T15 execution result and controller status updates.
9. Stop after T15 with T16 as the only next eligible task.

## Controller Loop Spec

Every controller invocation must execute this loop:

1. Receive explicit input.
   - `task_id` is required.
   - `mode` is required.
   - allowed modes are `query` and `build`.
   - no implicit task selection is allowed.
   - no automatic advancement is allowed.

2. Load complete authority.
   - load operating system rules.
   - load system decisions.
   - load system manifest.
   - load retrieval contracts.
   - load task manifest.
   - load DAG summary.
   - load selected task definition.
   - load all dependency execution results.
   - missing authority means STOP or BLOCKED.

3. Validate controller state.
   - `task_manifest.json` must be valid JSON.
   - DAG dependencies must match task manifest dependencies.
   - selected task must be `NOT_STARTED`.
   - all selected task dependencies must be `PASS`.
   - selected task must be the only eligible task.
   - no later task may execute.

4. Validate task scope.
   - task scope must be explicit.
   - mutation boundary must be explicit.
   - selected task cannot mutate outside its declared boundary.
   - selected task cannot consume undeclared authority.
   - selected task cannot blend with later tasks.

5. Run common preflight.
   - enforce T03 preflight contract.
   - enforce T13 Windows path contract.
   - enforce T14 rebuild approval gate when build mode is requested.
   - enforce `index_manifest.json` as the only manifest authority.
   - reject fallback authority.

6. Branch by mode.
   - query mode enters the read-only query loop.
   - build mode enters the explicit-approval build loop.
   - mixed mode is forbidden.

7. Execute one controlled unit.
   - only one task or runtime operation executes.
   - no auto-advance occurs.
   - no retry with modified parameters occurs.
   - no fallback path executes.

8. Verify output.
   - verify selected task contract.
   - verify mode invariants.
   - verify no forbidden side effect occurred.
   - verify controller state consistency.

9. Materialize state.
   - write only declared controller result/state artifacts.
   - do not mark a later task.
   - do not create runtime artifacts unless build mode has valid approval and
     the selected task explicitly permits it.

10. Stop.
    - return explicit status.
    - report the next eligible task.
    - do not continue automatically.

## Input Model

The controller accepts only:

- `task_id`
- `mode`

Both inputs are mandatory.

Allowed `mode` values:

- `query`
- `build`

Forbidden inputs:

- implicit task selection.
- "continue".
- "run next".
- "auto".
- runtime override of manifest fields.
- corpus path override.
- model override.
- batch override.
- device override outside manifest and approval policy.
- top_k or ranking override outside manifest policy.
- index path override.

If a future interface accepts extra user-facing fields, they must be transport
metadata only and must not alter controller semantics.

## Task Execution Rules

Task execution rules:

- only the selected `task_id` may execute.
- dependencies must be `PASS`.
- selected task must be `NOT_STARTED`.
- selected task must be the only eligible task.
- no task can skip the DAG.
- no task can update a later task.
- no task can widen its scope.
- no task can perform runtime work forbidden by its own definition.
- no implementation work can occur inside design-only tasks.
- no task can treat conversational state as controller state without a
  repo-visible execution result.

Design task mutation rules:

- may write the selected task execution result only when the task allows future
  result materialization or the controller requires state materialization.
- may update the selected task status.
- may update `task_manifest.json`.
- may update `DAG_SUMMARY.md`.
- must not update runtime code.
- must not create `.repo_index`.
- must not create model, cache, staging, lexical, vector, or retrieval
  artifacts.

Runtime task mutation rules:

- query mode is read-only.
- build mode requires T14 approval.
- build mode uses T07 staging.
- active promotion requires full verification.
- failed build leaves active index untouched.

## Preflight Integration

Every controller invocation must run preflight before any selected operation.

Common preflight:

- load all authority.
- validate task manifest.
- validate DAG.
- validate dependency status.
- validate selected task eligibility.
- validate selected task scope.
- enforce Windows interpreter:
  `.repo_index/.search_venv/Scripts/python.exe`.
- reject `/bin`, `.venv`, bare Python, bash, shell activation, AF_UNIX,
  `pgrep`, and shell process discovery.
- enforce `index_manifest.json` as sole runtime manifest authority.
- reject `search_manifest.txt`, `searchable_files.txt`, Chroma metadata,
  lexical metadata, cache, MCP output, or source scan as authority.
- enforce CPU baseline and GPU acceleration-only policy.
- reject model download, fallback model, fallback interpreter, fallback device,
  or fallback retrieval.

Build-mode preflight additionally:

- requires exact T14 approval.
- requires `mode = build`.
- requires staging.
- requires manifest-bound corpus, chunking, model, tokenizer, batch, device,
  artifact, retrieval, and ranking policies.
- must not create interpreter, dependencies, models, approval, or index during
  preflight.

Query-mode preflight additionally:

- requires healthy active `.repo_index` artifacts.
- missing `.repo_index` means STOP.
- corrupt artifacts mean CORRUPT_INDEX.
- query path cannot call build path.
- query path cannot scan source files.
- query path cannot write cache or memory.

## Mode Separation Rules

Query mode:

- read-only.
- requires healthy active index.
- consumes existing canonical artifacts only.
- returns canonical evidence objects only.
- cannot rebuild, repair, stage, promote, cache, or write memory.
- cannot scan corpus or filesystem for retrieval.
- cannot download or load alternate models.
- cannot request approval.

Build mode:

- requires T14 explicit approval.
- uses T07 staging.
- resolves corpus only from `index_manifest.json`.
- normalizes corpus through T04.
- chunks through T05.
- derives hashes and IDs through T06.
- embeds through T08 policy.
- builds lexical index through T09.
- builds Chroma vector index through T10.
- verifies parity before promotion.
- promotes only after full verification.
- never writes active artifacts directly.

No controller invocation may switch modes after preflight. A failed query cannot
become a build. A failed build cannot become a query. A CUDA failure cannot
become CPU execution unless a new explicit approval selects CPU.

## Build Loop Definition

Future build mode must execute this order:

1. bind `task_id` and `mode = build`.
2. load complete authority.
3. validate manifest and DAG state.
4. run common preflight.
5. validate T14 approval.
6. validate Windows runtime from T13.
7. load and validate `.repo_index/index_manifest.json` authority.
8. compute deterministic staging target from manifest-owned inputs.
9. resolve corpus from manifest only.
10. normalize corpus paths and text.
11. generate deterministic chunks.
12. compute `content_hash`, `doc_id`, and chunk manifest hash.
13. write staging `chunk_manifest.jsonl`.
14. build staging lexical index from chunk manifest only.
15. build staging Chroma index from chunk manifest and T08 model policy only.
16. compute artifact hashes.
17. verify manifest, corpus, chunk, lexical, vector, model, tokenizer, and
    doc_id parity.
18. promote staged artifacts atomically.
19. mark result explicitly.
20. stop.

Any failure before promotion discards staging and leaves active index untouched.

## Query Loop Definition

Future query mode must execute this order:

1. bind `task_id` and `mode = query`.
2. load complete authority.
3. validate manifest and DAG state.
4. run common preflight.
5. validate Windows runtime from T13.
6. validate active `.repo_index/index_manifest.json`.
7. validate active `chunk_manifest.jsonl`.
8. validate active `lexical_index/`.
9. validate active `chroma_db/`.
10. verify artifact hashes and doc_id parity.
11. normalize query under T11 retrieval contract.
12. retrieve bounded lexical candidates.
13. retrieve bounded vector candidates.
14. union candidates by `doc_id`.
15. optionally rerank only if manifest allows.
16. apply deterministic final ranking.
17. emit canonical evidence objects only.
18. stop.

Query mode must not build, repair, write cache, write memory, scan corpus,
create Chroma collections, create MCP-local ranking, or return partial results
after a STOP condition.

## State Transition Model

Repo-visible task statuses:

- `NOT_STARTED`
- `PASS`
- `BLOCKED`
- `CONTRACT_DRIFT`
- `CORRUPT_INDEX`
- `DEVICE_DRIFT`

Allowed transition for a selected task:

- `NOT_STARTED` to one terminal result.

Forbidden transitions:

- a terminal result back to `NOT_STARTED`.
- a task result without dependency `PASS`.
- updating a later task.
- marking multiple tasks in one invocation.
- partial success.
- conversational-only completion.

Controller-level outcome meanings:

- `PASS`: selected task completed within scope and verified.
- `BLOCKED`: required authority, dependency, or eligibility is missing.
- `CONTRACT_DRIFT`: contracts or code surfaces contradict locked authority.
- `CORRUPT_INDEX`: active artifacts are invalid or mismatched.
- `DEVICE_DRIFT`: selected device violates manifest or approval policy.

STOP is the runtime behavior for any terminal failure. STOP is not a task status
unless a selected task explicitly records it as the failure intent.

## Failure Handling Rules

On any failure:

- stop immediately.
- do not retry with different parameters.
- do not fallback.
- do not repair.
- do not auto-build.
- do not auto-download.
- do not switch devices.
- do not scan corpus.
- do not return partial query results.
- do not mark later tasks.
- do not hide the classification.

Design task failure:

- no runtime artifacts may exist.
- no tooling files may be modified.
- selected task may be marked with the terminal failure only if the controller
  execution result documents the blocker.

Build failure:

- staging is discarded or invalidated.
- active index remains untouched.
- no partial active state is trusted.

Query failure:

- no rebuild is attempted.
- no cache is written.
- no partial evidence is returned.

## Contract Drift Analysis

The current repository does not yet satisfy this T15 controller loop:

- `tools/index/build_repo_index.sh` can create `.repo_index` directly outside
  controller governance.
- `tools/index/build_vector_index.py` can build active artifacts directly,
  bootstraps manifest content from code, uses `search_manifest.txt`, sets
  `REBUILD = True`, selects device at runtime, and uses Chroma
  `get_or_create_collection`.
- `tools/index/search_code.py` requires `search_manifest.txt`, uses
  `query_cache.json`, `query_memory.json`, and `search_code.sock`, loads models
  in query path, resolves device at runtime, and writes during query.
- `tools/mcp/semantic_search_server.py` owns model loading, embedding, rerank,
  device selection, and CLI text parsing instead of thin wrapping canonical
  retrieval.
- `tools/index/device_utils.py` auto-selects CPU/CUDA from runtime availability
  and environment override.
- `tools/index/ENVIRONMENT_SETUP.sh` creates environment state and installs
  dependencies outside controller governance.
- `ingestion_contract.md` still names `search_manifest.txt`.
- `index_structure_contract.md` still names `searchable_files.txt` as an
  artifact and contains legacy manifest structure.
- older OS wording still contains Linux `.search_venv/bin/python` rules in
  tension with T13 Windows path.

These are later correction targets. T15 does not patch them.

## Verification Result

T15 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, `T06`, `T07`, `T08`, `T09`, `T10`,
  `T11`, `T12`, `T13`, and `T14` were repo-visible `PASS`.
- `T15` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T15` as the next executable task.
- `.repo_index` was absent before execution.
- T15 scope was limited to controller loop design.
- the input model is specified.
- task execution rules are specified.
- preflight integration is specified.
- build/query mode separation is specified.
- build loop and query loop order are specified.
- state transition rules are specified.
- failure handling is fail-closed.
- existing drift is identified for later controller tasks.
- no `.repo_index` directory was created.
- no staging path was created.
- no retrieval query was run.
- no MCP server was run.
- no dependency was installed.
- no model was loaded or downloaded.
- CUDA was not executed.
- no index was built.
- `tools/index/*` was not modified.
- `tools/mcp/semantic_search_server.py` was not modified.
- T16 and later tasks were not executed.

## Next Transition

Only `T16` may execute next under the strict controller order.
