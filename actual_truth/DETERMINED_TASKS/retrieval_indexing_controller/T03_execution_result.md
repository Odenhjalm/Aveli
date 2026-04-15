# T03 Execution Result - Controller Preflight Validation Contract

TASK_ID: T03
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_define_controller_preflight_validation_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `tools/index/*`
- `tools/mcp/semantic_search_server.py`

## Controller State Before T03

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T03` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T03 defines the fail-closed preflight validation contract for retrieval,
indexing, embedding, storage, and MCP wrapper execution. It does not implement
preflight code, does not build an index, does not create `.repo_index`, does not
download models, does not run CUDA, and does not execute retrieval.

## Preflight Authority Decision

Preflight owns readiness gating only. It decides whether a requested controller
operation may begin, but it does not own corpus membership, ranking,
embedding semantics, artifact content, rebuild authorization wording, or
retrieval output.

Preflight must enforce:

- explicit `task_id`
- explicit `mode` with allowed values `query` or `build`
- dependency and DAG eligibility
- complete authority load for the selected task
- manifest schema validity from T02
- Windows runtime invariants
- local-only model availability
- artifact health in query mode
- approval presence in build mode
- no fallback, repair, auto-build, download, or runtime scanning

Any missing, ambiguous, or mismatched prerequisite is terminal.

## Common Preflight Checks

These checks must run before every build-mode or query-mode operation:

1. Task input is explicit.
   - `task_id` must be provided.
   - `mode` must be provided.
   - no implicit task selection is allowed.
   - no automatic advancement is allowed.

2. Controller state is valid.
   - `task_manifest.json` must be valid JSON.
   - `DAG_SUMMARY.md` must match the manifest dependency graph.
   - all task dependencies must be `PASS`.
   - the selected task must be the only task allowed by controller ordering.

3. Authority load is complete.
   - OS file is readable.
   - retrieval contracts are readable.
   - prior dependency execution results are readable.
   - selected task file is readable.
   - missing authority means STOP.

4. Manifest authority is singular.
   - `.repo_index/index_manifest.json` is the only corpus/config/version/ranking
     authority when a runtime manifest is required.
   - `search_manifest.txt` and `searchable_files.txt` are non-authoritative.
   - `rg --files` is not an authority.
   - Chroma metadata, lexical metadata, caches, and MCP output are not authority.

5. Runtime must be Windows-compatible.
   - canonical retrieval interpreter is `.repo_index/.search_venv/Scripts/python.exe`.
   - no bare `python` fallback.
   - no `.venv` or system Python fallback.
   - no shell activation.
   - no bash-only path.
   - no `/bin` path.
   - no AF_UNIX.
   - no `pgrep`.

6. Device semantics are locked.
   - CPU remains canonical correctness baseline.
   - CUDA may be used only if the manifest explicitly permits it.
   - device choice must not alter corpus, chunking, identity, hashes, artifacts,
     ranking policy, or evidence shape.

7. Model behavior is locked.
   - model and tokenizer identity must be locked by manifest fields from T02.
   - local model presence must be verified without network access.
   - no auto-download is allowed.
   - no fallback model is allowed.

8. Language surface policy is active.
   - user-facing preflight errors must be Swedish.
   - generated prompts, if any future stage emits them, must be English,
     complete, plain text, and copy-paste-ready.

## Build-Mode Preflight Checks

Build mode is allowed to proceed only after all common checks pass and all
build-only checks pass:

1. Explicit rebuild/build approval is present.
   - missing approval means STOP.
   - partial approval means STOP.
   - query-mode request must never transform into build mode.

2. Build target is canonical.
   - target path must be `.repo_index`.
   - active index must not be written directly.
   - build must later use staging defined by T07.

3. Manifest authority is available before build execution.
   - build configuration must come from the T02 schema contract.
   - runtime overrides are forbidden.
   - hardcoded chunk/model/ranking/candidate values are forbidden.

4. Interpreter is exact.
   - `.repo_index/.search_venv/Scripts/python.exe` must exist before any build
     code runs.
   - missing interpreter means STOP.
   - build preflight must not create the interpreter.
   - environment setup, dependency install, and venv creation are outside T03.

5. Dependencies are locally available.
   - required packages must be importable through the canonical interpreter.
   - dependency installation is forbidden during preflight.
   - system Python and `.venv` are forbidden for retrieval/indexing.

6. Model files are locally available.
   - embedding model and tokenizer files must exist locally.
   - exact model revision/hash and tokenizer revision/hash must match manifest
     locks.
   - no network access, fallback model, or implicit cache resolution is allowed.

7. Device selection is explicit.
   - selected build device must match manifest policy.
   - CUDA may be preferred but not required for correctness.
   - if selected CUDA is unavailable, STOP unless a later approved build policy
     explicitly selects CPU.
   - no automatic CPU/GPU switch is allowed.

8. Batch policy is explicit.
   - `embedding_batch_size` must be present in the manifest.
   - value must be inside the manifest-declared range.
   - dynamic batch sizing is forbidden.

## Query-Mode Preflight Checks

Query mode is read-only and may proceed only after all common checks pass and
all query-only checks pass:

1. Active index exists.
   - missing `.repo_index` means STOP.
   - missing active manifest means STOP.
   - missing index must never trigger build.

2. Active manifest is valid.
   - `.repo_index/index_manifest.json` must validate against the T02 schema.
   - manifest state must be `ACTIVE_VERIFIED`.
   - manifest must declare the required artifact paths and hashes.

3. Required artifacts exist and are readable.
   - `.repo_index/index_manifest.json`
   - `.repo_index/chunk_manifest.jsonl`
   - `.repo_index/lexical_index/`
   - `.repo_index/chroma_db/`

4. Artifact bindings match the manifest.
   - `contract_version` must match across artifacts.
   - `corpus_manifest_hash` must match across artifacts.
   - `chunk_manifest_hash` must match across artifacts.
   - model/tokenizer snapshot locks must match vector metadata.

5. Artifact parity is healthy.
   - chunk manifest `doc_id` set must be unique.
   - lexical index `doc_id` set must match the chunk manifest.
   - vector index `doc_id` set must match the chunk manifest.
   - mismatch means CORRUPT_INDEX and STOP.

6. Query path remains read-only.
   - no cache writes.
   - no query memory writes.
   - no index rebuild.
   - no repo scan.
   - no Chroma collection creation.
   - no model download.
   - no artifact repair.

7. Query execution surface is bounded.
   - `top_k`, `lexical_candidate_k`, `vector_candidate_k`, and union limits
     must come from `index_manifest.json`.
   - MCP and CLI inputs may not override manifest limits.

## Windows Runtime Enforcement

The only allowed interpreter for retrieval/indexing runtime is:

`.repo_index/.search_venv/Scripts/python.exe`

Forbidden constructs:

- `.repo_index/.search_venv/bin/python`
- `.venv/bin/python`
- `.venv/Scripts/python.exe` for retrieval/indexing
- bare `python`
- `python3`
- `bash`
- `sh`
- `zsh`
- `source`
- shell activation
- `/bin/*`
- AF_UNIX sockets
- `pgrep`
- process discovery through shell text matching
- environment-dependent interpreter discovery

Preflight must reject Linux-only or shell-dependent execution surfaces before
any model load, artifact read, query execution, build execution, or MCP wrapper
dispatch occurs.

## GPU/CUDA Preflight Policy

GPU acceleration is build performance policy, not correctness policy.

Rules:

- CPU is the canonical baseline.
- CUDA may be selected only when the manifest permits it.
- CUDA must not be required for correctness.
- device selection must be explicit and manifest-bound.
- device auto-selection from runtime availability is forbidden.
- device override from environment variables is forbidden unless the manifest
  explicitly authorizes that override channel.
- embedding/rerank batch sizes must be explicit manifest values.
- CUDA failure must STOP unless an explicit approved policy chooses CPU for the
  build.

Preflight must treat device drift as STOP because accepting a different device
without approval would create hidden runtime behavior.

## Model And Manifest Availability Checks

Manifest checks:

- required T02 top-level fields are present.
- required nested fields for `model_policy`, `embedding_policy`,
  `device_policy`, `batch_policy`, `retrieval_policy`, `ranking_policy`,
  `artifact_policy`, `windows_runtime_policy`, and `rebuild_policy` are present.
- no legacy flat field may override the canonical nested policy.
- no derived artifact may define missing manifest fields.
- no runtime code constant may supply a missing canonical value.

Model checks:

- `model_id` is present.
- exact `model_revision` is present.
- exact `model_snapshot_hash` is present.
- `tokenizer_id` is present.
- exact `tokenizer_revision` is present.
- `tokenizer_files_hash` is present.
- `embedding_dimension` is present.
- `dtype` is `float32` for canonical baseline.
- prefix policy is explicit.
- `local_files_only` is true.
- network access is not used.
- no fallback model is attempted.

## Failure Matrix

| Condition | Classification | Failure Intent |
| --- | --- | --- |
| Missing task id or mode | STOP | Swedish error names missing input field. |
| Task not next in controller order | BLOCKED | Swedish error names expected and actual task. |
| Missing dependency PASS | BLOCKED | Swedish error names dependency and status. |
| Missing authority file | BLOCKED | Swedish error names missing authority path. |
| Invalid `task_manifest.json` | CONTRACT_DRIFT | Swedish error names invalid JSON/schema. |
| DAG and manifest mismatch | CONTRACT_DRIFT | Swedish error names mismatched edge/status. |
| Missing canonical Windows interpreter | STOP | Swedish error names `.repo_index/.search_venv/Scripts/python.exe`. |
| Use of `/bin/python` or `.venv` for retrieval/indexing | STOP | Swedish error names forbidden interpreter. |
| Shell activation or bash requirement | STOP | Swedish error names forbidden shell dependency. |
| AF_UNIX or `pgrep` usage in runtime path | STOP | Swedish error names forbidden Windows-incompatible feature. |
| Missing runtime manifest in query mode | STOP | Swedish error says index is missing and query cannot build. |
| Missing active index artifact in query mode | CORRUPT_INDEX | Swedish error names artifact path. |
| Artifact hash or doc_id parity mismatch | CORRUPT_INDEX | Swedish error names mismatched artifact set. |
| Missing build approval | STOP | Swedish error says rebuild/build is not approved. |
| Partial build approval | STOP | Swedish error names missing approval field. |
| Runtime parameter override | CONTRACT_DRIFT | Swedish error names forbidden override source. |
| Missing local model files | STOP | Swedish error names missing model/tokenizer lock. |
| Model download would be required | STOP | Swedish error says network/model download is forbidden. |
| CUDA required for correctness | CONTRACT_DRIFT | Swedish error says CPU baseline was violated. |
| CUDA unavailable after explicit CUDA selection | DEVICE_DRIFT | Swedish error names selected device and availability. |
| Cache/query-memory write in query mode | CONTRACT_DRIFT | Swedish error names forbidden write path. |
| Query attempts index rebuild | STOP | Swedish error says query-time rebuild is forbidden. |
| MCP attempts independent embedding/ranking/rebuild | CONTRACT_DRIFT | Swedish error names MCP authority violation. |

## Contract Drift Analysis

The current repository does not yet satisfy this T03 preflight contract:

- `codex/AVELI_OPERATING_SYSTEM.md` still contains an older Linux index
  interpreter rule under the index environment law, while its Python execution
  rules include the Windows semantic-search interpreter. T03 resolves the
  retrieval/indexing controller path to the Windows interpreter from T02.
- `tools/index/analyze_results.py`, `codex_query.py`, `run_codex.py`,
  `run_codex_auto.py`, and `validate_codex.py` use `.venv/bin/python` for
  retrieval-adjacent flows.
- `tools/index/build_vector_index.py` allows `.venv/bin/python` and
  `.repo_index/.search_venv/bin/python`, reads `search_manifest.txt`, creates
  or finalizes manifest content from code, uses hardcoded canonical constants,
  selects device from runtime, sets `REBUILD = True`, uses device-derived batch
  sizing, and uses Chroma `get_or_create_collection`.
- `tools/index/search_code.py` allows `.venv/bin/python` and
  `.repo_index/.search_venv/bin/python`, requires `search_manifest.txt`, uses
  AF_UNIX sockets, invokes `pgrep`, writes `query_cache.json` and
  `query_memory.json` during query execution, and loads models in the query
  runtime path.
- `tools/index/device_utils.py` auto-selects CPU/CUDA from runtime availability
  and environment override instead of manifest-only policy.
- `tools/index/build_repo_index.sh`, `semantic_search.sh`, and
  `ENVIRONMENT_SETUP.sh` are bash-based and use Linux path conventions.
- `tools/index/ENVIRONMENT_SETUP.sh` creates `.repo_index/.search_venv`, uses
  shell activation, installs CUDA PyTorch, and requires CUDA availability.
- `tools/index/requirements.txt` pins CUDA wheels, which conflicts with CPU
  baseline as canonical correctness policy.
- `tools/mcp/semantic_search_server.py` uses
  `.repo_index/.search_venv/bin/python`, hardcodes `intfloat/e5-large-v2`,
  selects device at runtime, owns embedding/rerank behavior, and calls the base
  search flow instead of deferring to canonical retrieval.
- `ingestion_contract.md` still names `search_manifest.txt` as corpus authority.
- `index_structure_contract.md` still lists `searchable_files.txt` as an
  authoritative artifact and defines a legacy flat minimum manifest schema.

These are later correction targets. T03 does not patch them.

## Verification Result

T03 passed because:

- all user-provided authority files existed and were inspected.
- `T01` and `T02` were repo-visible `PASS`.
- `T03` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T03` as the next executable task.
- the preflight contract is fully specified for common, build-only, query-only,
  Windows, GPU/CUDA, model, manifest, artifact, approval, and failure handling.
- the contract remains controller-first and fail-closed.
- no index was built.
- `.repo_index` was not created.
- no model was downloaded or executed.
- CUDA was not used.
- no retrieval query was executed.
- T04 and later tasks were not executed.

## Next Transition

Only `T04` may execute next under the strict controller order.
