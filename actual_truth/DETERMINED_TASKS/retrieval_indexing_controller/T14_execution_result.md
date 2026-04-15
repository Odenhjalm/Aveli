# T14 Execution Result - Rebuild Approval Gate

TASK_ID: T14
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T14_define_rebuild_approval_gate.md`
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

## Controller State Before T14

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
- `T14` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T14` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T14 defines the explicit rebuild approval gate required before any future index
build or rebuild can begin. The gate prevents missing indexes, query failures,
age, quality concerns, repo changes, background work, MCP calls, or tooling
assumptions from triggering a build.

T14 does not request approval, does not create an approval record, does not
create `.repo_index`, does not write staging artifacts, does not install
dependencies, does not download or load models, does not execute CUDA, does not
run retrieval, and does not build an index.

## T14 Execution Plan

1. Load the T14 task file and controller state artifacts.
2. Verify T01, T03, T07, and T13 are repo-visible `PASS`.
3. Verify all prior locked layers T04 through T13 remain authority for build
   semantics.
4. Verify T14 is repo-visible `NOT_STARTED`.
5. Verify T14 is the only eligible next task.
6. Confirm `.repo_index` is absent.
7. Audit current rebuild/autobuild drift surfaces statically.
8. Define the explicit approval phrase, required approval fields, validation
   rules, build-mode rules, device/model lock rules, and STOP conditions.
9. Materialize only the T14 execution result and controller status updates.
10. Stop after T14 with T15 as the only next eligible task.

## Approval Authority Spec

T14 owns only the approval gate for entering future build mode.

T14 does not own:

- corpus membership.
- manifest schema.
- normalization.
- chunking.
- doc_id or hashing.
- artifact structure.
- model or embedding semantics.
- Windows runtime semantics.
- retrieval behavior.
- MCP behavior.

Those remain locked by T01 through T13.

The approval gate has one purpose: no build or rebuild can start unless a
controller-valid approval record exists and exactly matches the active
manifest-controlled build request.

The gate is fail-closed:

- missing approval means STOP.
- partial approval means STOP.
- ambiguous approval means STOP.
- approval mismatch means STOP.
- query-mode rebuild attempt means STOP.
- MCP-triggered rebuild attempt means STOP.
- background or automatic rebuild attempt means STOP.

## Approval Format

Future build mode requires an explicit user-declared approval record. The record
must contain the exact approval phrase:

`APPROVE AVELI INDEX REBUILD`

The phrase must match byte-for-byte after LF line normalization. It is not valid
if translated, paraphrased, lowercased, abbreviated, embedded only in a
conversation summary, or inferred from intent.

The approval record must include all fields below:

- `approval_phrase`: exactly `APPROVE AVELI INDEX REBUILD`.
- `repo_root`: repo-root path being approved for build.
- `corpus_scope`: manifest-owned corpus scope from `index_manifest.json`.
- `manifest_authority`: `.repo_index/index_manifest.json`.
- `target_path`: `.repo_index`.
- `staging_required`: `true`.
- `direct_active_write_allowed`: `false`.
- `selected_mode`: `build`.
- `query_mode_allowed_to_build`: `false`.
- `canonical_interpreter`: `.repo_index/.search_venv/Scripts/python.exe`.
- `canonical_baseline`: `cpu`.
- `selected_build_device`: explicit `cpu` or manifest-permitted `cuda`.
- `cuda_required_for_correctness`: `false`.
- `cuda_allowed_only_if_manifest_permits`: `true`.
- `implicit_device_switch_allowed`: `false`.
- `embedding_batch_size`: explicit manifest value.
- `model_id`: exact manifest value.
- `model_revision`: exact manifest value.
- `model_snapshot_hash`: exact manifest value.
- `tokenizer_id`: exact manifest value.
- `tokenizer_revision`: exact manifest value.
- `tokenizer_files_hash`: exact manifest value.
- `network_download_allowed`: `false`.
- `fallback_model_allowed`: `false`.
- `fallback_interpreter_allowed`: `false`.
- `fallback_retrieval_allowed`: `false`.
- `approval_scope`: one controller build attempt only.

The approval record must be treated as input to build-mode preflight, not as a
runtime override source. If any approval field conflicts with
`index_manifest.json`, the manifest remains authoritative and execution stops.

## Build Mode Rules

Build mode may begin only if all of the following are true:

1. The controller was invoked explicitly with `mode = build`.
2. T01 through T14 are repo-visible `PASS`.
3. The approval phrase is present exactly.
4. Every required approval field is present.
5. Approval values match manifest-owned build policy.
6. The canonical Windows interpreter from T13 is used.
7. T07 staging is used.
8. The target path is `.repo_index`.
9. No active index artifact is written before verification.
10. No model download is required.
11. No dependency installation is required.
12. No fallback device, model, interpreter, retrieval, or corpus source is used.

Query mode is always read-only:

- query mode must never create `.repo_index`.
- query mode must never create staging.
- query mode must never request approval.
- query mode must never call build mode.
- query mode must never return partial results from an unapproved build path.
- missing `.repo_index` in query mode means STOP, not build.

Mixed mode is forbidden. A single controller invocation cannot be both query and
build.

## Device And Model Lock Rules

CPU remains the canonical correctness baseline.

CUDA/GPU may be selected only as future local build acceleration when all of the
following are true:

- `index_manifest.json` permits CUDA.
- the approval record explicitly selects `cuda`.
- `cuda_required_for_correctness` is `false`.
- no artifact semantics can change because of the selected device.
- no implicit CPU/GPU fallback occurs.

T14 does not permit CUDA execution by itself. It only defines the approval
requirement for a later build-mode controller step.

Model and tokenizer locks must match T08 and the manifest exactly:

- no `latest`.
- no `main`.
- no implicit cache-only identity.
- no fallback model.
- no model download.
- no tokenizer drift.
- no runtime prefix or normalization override.

Batch size is locked by approval and manifest:

- the chosen `embedding_batch_size` must be present in the manifest.
- the approval record must repeat the exact value.
- dynamic batch sizing is forbidden.
- batch size cannot alter chunk order, embedding identity, artifact hashes, or
  evidence semantics.

## Validation Rules

Before a future build can start, approval validation must verify:

- exact approval phrase.
- approval record is complete.
- selected task and mode are explicit.
- selected mode is `build`.
- repo root matches the controller repo root.
- target path is `.repo_index`.
- target path is not a derived or alternate index root.
- staging is required.
- direct active writes are forbidden.
- manifest authority is `.repo_index/index_manifest.json`.
- no runtime override is present.
- selected device matches manifest policy.
- batch size matches manifest policy.
- model and tokenizer locks match manifest policy.
- no approval field is derived from Chroma metadata, lexical metadata, cache,
  MCP output, source scan, `search_manifest.txt`, or `searchable_files.txt`.

Any mismatch is terminal and must not be repaired automatically.

## Failure Conditions

| Condition | Classification | Required Result |
| --- | --- | --- |
| Missing approval phrase | STOP | Build does not start. |
| Approval phrase is paraphrased or translated | STOP | Build does not start. |
| Approval record is partial | STOP | Build does not start. |
| Approval record conflicts with manifest | STOP | Build does not start. |
| Query mode attempts build | STOP | Query returns no partial results. |
| MCP attempts build | STOP | MCP surfaces controller failure. |
| Missing index triggers build automatically | STOP | Missing index remains query failure. |
| Repo age/change triggers rebuild | STOP | Build does not start. |
| Search quality triggers rebuild | STOP | Build does not start. |
| Background indexing starts | STOP | Build is invalid. |
| Device is auto-selected | DEVICE_DRIFT | Build does not start. |
| CUDA selected without manifest permission | DEVICE_DRIFT | Build does not start. |
| GPU failure causes implicit CPU fallback | DEVICE_DRIFT | Build does not continue. |
| Model lock mismatch | STOP | Build does not start. |
| Model download would be required | STOP | Build does not start. |
| Runtime override changes manifest policy | CONTRACT_DRIFT | Build does not start. |
| Direct active `.repo_index` write occurs | CORRUPT_INDEX | Active index is not trusted. |

User-facing failure messages must be Swedish. Any generated prompt or approval
template emitted by a future implementation must be English, complete, and
copy-paste-ready.

## Contract Drift Analysis

The current repository does not yet satisfy this T14 approval gate:

- `codex/AVELI_OPERATING_SYSTEM.md` already forbids implicit rebuilds, but its
  older index environment wording still conflicts with the T13 Windows
  interpreter.
- `tools/index/build_repo_index.sh` can create `.repo_index` directly and is not
  gated by a controller approval record.
- `tools/index/build_vector_index.py` sets `REBUILD = True`.
- `tools/index/build_vector_index.py` can remove active `chroma_db/` when
  rebuild is enabled.
- `tools/index/build_vector_index.py` writes active `.repo_index` artifacts
  instead of requiring T07 staging and promotion.
- `tools/index/build_vector_index.py` bootstraps manifest content from code,
  which conflicts with `index_manifest.json` as the single authority.
- `tools/index/build_vector_index.py` selects device from runtime availability
  rather than approval plus manifest policy.
- `tools/index/ENVIRONMENT_SETUP.sh` creates `.repo_index/.search_venv`, uses
  shell activation, installs dependencies, and is not gated by controller
  approval.
- `tools/index/search_code.py` uses `.repo_index` query cache, memory, and
  socket artifacts in the query path.
- `tools/index/search_code.py` can depend on legacy search manifests and source
  scans instead of stopping on missing healthy canonical artifacts.
- `tools/mcp/semantic_search_server.py` invokes `tools/index/search_code.py`
  and does not enforce a no-build MCP boundary through canonical retrieval.
- `ingestion_contract.md` and `index_structure_contract.md` still contain
  legacy artifact authority language that must be corrected by later
  implementation tasks.

These are later correction targets. T14 does not patch them.

## Verification Result

T14 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, `T06`, `T07`, `T08`, `T09`, `T10`,
  `T11`, `T12`, and `T13` were repo-visible `PASS`.
- `T14` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T14` as the next executable task.
- `.repo_index` was absent before execution.
- T14 scope was limited to rebuild approval gate design.
- the exact approval phrase is specified.
- required approval fields are specified.
- build-mode and query-mode separation is specified.
- manifest, device, model, tokenizer, batch, staging, and Windows interpreter
  locks are specified.
- missing, partial, ambiguous, mismatched, or query-triggered approval failures
  are fail-closed.
- existing drift is identified for later controller tasks.
- no approval record was created.
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
- T15 and later tasks were not executed.

## Next Transition

Only `T15` may execute next under the strict controller order.
