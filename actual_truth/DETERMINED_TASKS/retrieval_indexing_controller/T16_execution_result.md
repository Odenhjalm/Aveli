# T16 Execution Result - Verification Suite Deterministic Tests

TASK_ID: T16
EXECUTION_STATUS: BLOCKED
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller
BLOCKING_CLASSIFICATION: CONTRACT_DRIFT

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T16_define_verification_suite_deterministic_tests.md`
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
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T15_execution_result.md`
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

## Controller State Before T16

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
- `T15` was repo-visible `PASS`.
- `T16` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T16` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

BLOCKED.

T16 was eligible to execute, but final system verification could not produce
`PASS` because T01 through T15 are not yet fully authority-aligned with the
current repository contracts and runtime surfaces. Multiple prior execution
results explicitly record `CONTRACT_DRIFT identified for later correction`, and
those corrections have not been applied.

Because the requested T16 gate requires absence of conflicting contracts,
undefined behavior, implicit fallback paths, and hidden mutation paths, T16 must
fail closed.

T16 does not create test files, does not run tests, does not modify prior task
outputs, does not create `.repo_index`, does not install dependencies, does not
download or load models, does not execute CUDA, does not run retrieval, and
does not build an index.

## T16 Audit Plan

1. Load T16 task authority and controller state.
2. Verify T01 through T15 are repo-visible `PASS`.
3. Verify T16 is repo-visible `NOT_STARTED`.
4. Verify T16 is the only eligible next task.
5. Confirm `.repo_index` is absent.
6. Cross-validate T01 through T15 execution results against retrieval
   contracts, OS rules, and current tool surfaces.
7. Identify remaining authority conflicts, undefined boundaries, fallback
   paths, and mutation paths.
8. If clean, mark T16 `PASS`.
9. If not clean, mark T16 `BLOCKED` and stop.

## Verification Findings

### Passing Controller-State Checks

- `task_manifest.json` is valid JSON.
- DAG dependencies are internally ordered.
- T01 through T15 are repo-visible `PASS`.
- T16 is the only eligible next executable task before this result.
- `.repo_index` is absent.
- no index build was started.
- no model download was started.
- no retrieval query was run.
- no CUDA execution occurred.

### Blocking Authority Conflicts

1. Corpus authority is still contradictory.

   Locked controller authority:

   - T01 and T02 require `.repo_index/index_manifest.json` as the only corpus
     and configuration authority.
   - T04 requires corpus resolution from manifest-owned file entries only.
   - T15 rejects `search_manifest.txt` and `searchable_files.txt` as authority.

   Conflicting repository contracts and code:

   - `actual_truth/contracts/retrieval/ingestion_contract.md` still names
     `.repo_index/search_manifest.txt` as the canonical ingestion manifest.
   - `actual_truth/contracts/retrieval/index_structure_contract.md` still lists
     `.repo_index/searchable_files.txt` as an authoritative artifact.
   - `tools/index/build_repo_index.sh` creates `search_manifest.txt` and
     `searchable_files.txt`.
   - `tools/index/build_vector_index.py` reads `search_manifest.txt`.
   - `tools/index/search_code.py` requires `search_manifest.txt`.

   Result: BLOCKED. T16 cannot certify single authority while these surfaces
   still conflict.

2. Windows runtime authority is still contradictory.

   Locked controller authority:

   - T13 requires `.repo_index/.search_venv/Scripts/python.exe`.
   - T13 forbids `/bin`, `.repo_index/.search_venv/bin/python`, `.venv`, bare
     Python, bash, shell activation, AF_UNIX, and `pgrep`.

   Conflicting repository contracts and code:

   - `codex/AVELI_OPERATING_SYSTEM.md` still contains older
     `.repo_index/.search_venv/bin/python` language.
   - `tools/index/search_code.py` defines `.venv/bin/python` and
     `.repo_index/.search_venv/bin/python`.
   - `tools/index/build_vector_index.py` defines `.venv/bin/python` and
     `.repo_index/.search_venv/bin/python`.
   - `tools/mcp/semantic_search_server.py` defines
     `.repo_index/.search_venv/bin/python`.
   - `tools/index/semantic_search.sh`, `build_repo_index.sh`, and
     `ENVIRONMENT_SETUP.sh` are bash-based.
   - `tools/index/search_code.py` uses AF_UNIX sockets and invokes `pgrep`.

   Result: BLOCKED. T16 cannot certify Windows-only execution while Linux and
   Unix runtime paths remain active in authority surfaces.

3. Build path still has uncontrolled mutation paths.

   Locked controller authority:

   - T07 requires staging before promotion.
   - T14 requires explicit approval before build.
   - T15 requires all build execution through controller governance.

   Conflicting code:

   - `tools/index/build_repo_index.sh` can create `.repo_index` directly.
   - `tools/index/build_vector_index.py` sets `REBUILD = True`.
   - `tools/index/build_vector_index.py` can remove active `chroma_db/`.
   - `tools/index/build_vector_index.py` writes active `.repo_index` artifacts.
   - `tools/index/build_vector_index.py` uses Chroma `get_or_create_collection`
     rather than fail-closed collection validation.
   - `tools/index/ENVIRONMENT_SETUP.sh` creates `.repo_index/.search_venv` and
     installs dependencies outside controller governance.

   Result: BLOCKED. T16 cannot certify absence of hidden state mutation paths.

4. Query path still violates read-only retrieval.

   Locked controller authority:

   - T11 requires retrieval to be read-only.
   - T15 query mode forbids build, repair, cache writes, memory writes, source
     scan, Chroma collection creation, and model loading in the query path.

   Conflicting code:

   - `tools/index/search_code.py` writes `query_cache.json`.
   - `tools/index/search_code.py` writes `query_memory.json`.
   - `tools/index/search_code.py` uses `search_code.sock`.
   - `tools/index/search_code.py` loads `SentenceTransformer` and
     `CrossEncoder` in query path.
   - `tools/index/search_code.py` depends on `search_manifest.txt`.

   Result: BLOCKED. T16 cannot certify retrieval read-only behavior.

5. MCP wrapper is not yet a thin transport wrapper.

   Locked controller authority:

   - T12 requires MCP to wrap canonical retrieval only.
   - MCP must not own model loading, embedding, rerank, top_k, ranking, corpus,
     fallback, rebuild, or evidence semantics.

   Conflicting code:

   - `tools/mcp/semantic_search_server.py` imports `SentenceTransformer`,
     `torch`, and `numpy`.
   - `tools/mcp/semantic_search_server.py` hardcodes `intfloat/e5-large-v2`.
   - `tools/mcp/semantic_search_server.py` resolves device at runtime.
   - `tools/mcp/semantic_search_server.py` defines `semantic_rerank`.
   - `tools/mcp/semantic_search_server.py` invokes `tools/index/search_code.py`
     and parses CLI text output.

   Result: BLOCKED. T16 cannot certify MCP equivalence to canonical retrieval.

6. CPU/GPU embedding hash semantics remain underspecified.

   Locked controller authority:

   - T08 allows CPU/GPU embedding equivalence within a manifest-declared
     floating-point tolerance.
   - T10 defines `embedding_vector_hash` as
     `sha256(float32_little_endian_embedding_bytes)`.
   - T15 requires device choice not to alter artifact semantics.

   Remaining undefined behavior:

   - If CPU and GPU vectors differ within tolerance but not byte-for-byte, the
     raw vector hash can differ.
   - The controller does not yet specify whether canonical vector hashes are
     computed from CPU reference vectors, device-produced bytes, or a
     deterministic quantized/canonicalized vector serialization.

   Result: BLOCKED. T16 cannot certify CPU/GPU artifact equivalence until vector
   hash canonicalization is explicit.

7. Evidence source validation boundary remains underspecified.

   Locked controller authority:

   - T11 query mode forbids source tree scanning during retrieval.
   - T11 requires canonical evidence output only.

   Existing contract language:

   - `actual_truth/contracts/retrieval/evidence_contract.md` requires snippets
     to remain source-grounded and includes verification language about
     re-deriving snippets from source files.

   Remaining undefined behavior:

   - The system needs an explicit boundary distinguishing offline/audit-time
     source validation from query-time source scanning.
   - Without that boundary, a verifier or runtime could wrongly treat source
     reads as query-path behavior.

   Result: BLOCKED. T16 cannot certify absence of undefined behavior.

## Cross-Layer Consistency Matrix

| Layer | Result | Reason |
| --- | --- | --- |
| Corpus authority T01/T02/T04 | BLOCKED | Current contracts and tools still reference `search_manifest.txt` and `searchable_files.txt`. |
| Chunking T05 | BLOCKED | Current tools still derive chunks from `search_manifest.txt` paths instead of manifest-owned corpus entries. |
| Hashing T06 | BLOCKED | Current tools still compute corpus hash from raw legacy manifest bytes. |
| Artifacts T07 | BLOCKED | Current tools can write active `.repo_index` directly and use noncanonical artifacts. |
| Model policy T08 | BLOCKED | Current tools load models directly and select device at runtime. |
| Lexical/vector T09/T10 | BLOCKED | Current vector build uses legacy corpus input, runtime device selection, and Chroma collection creation. |
| Retrieval T11 | BLOCKED | Current query path writes cache/memory and loads models. |
| MCP T12 | BLOCKED | Current MCP owns model, device, embedding, rerank, and CLI parsing. |
| Windows T13 | BLOCKED | Current OS and tools still contain Linux path and Unix process/socket constructs. |
| Rebuild gate T14 | BLOCKED | Current build scripts can create or mutate index state outside approval gate. |
| Controller loop T15 | BLOCKED | Current runtime entrypoints still bypass controller governance. |

## Stop Conditions Triggered

T16 triggers fail-closed blocking conditions:

- conflicting corpus authority.
- conflicting Windows interpreter authority.
- implicit fallback paths remain in runtime surfaces.
- hidden build mutation paths remain in runtime surfaces.
- query write paths remain in runtime surfaces.
- MCP owns behavior outside transport wrapping.
- CPU/GPU artifact equivalence is not fully specified.
- evidence validation boundary is not fully specified.

## Verification Result

T16 is `BLOCKED`, not `PASS`.

Confirmed:

- authority load was complete.
- controller state before T16 was valid.
- T16 was the only eligible next task.
- DAG integrity was structurally valid.
- `.repo_index` still does not exist.
- `task_manifest.json` remains valid JSON before this result.
- no prior task output was modified.
- no index was built.
- no model was downloaded.
- no dependency was installed.
- no retrieval query was run.
- no CUDA execution occurred.
- no `tools/index/*` file was modified.
- no `tools/mcp/semantic_search_server.py` file was modified.
- T17 was not executed.

Not confirmed:

- absence of conflicting contracts.
- absence of undefined behavior.
- absence of implicit fallback paths.
- absence of hidden state mutation paths.
- full consistency between all locked layers and current repository surfaces.

## Required Corrections Before T16 Can Pass

Before T16 can be re-run as `PASS`, later correction work must:

1. Rewrite retrieval contracts so `index_manifest.json` is the only corpus,
   configuration, version, classification, and ranking authority.
2. Remove `search_manifest.txt` and `searchable_files.txt` from authority
   language and retain them only as non-authoritative debug/export artifacts if
   retained at all.
3. Replace Linux and `.venv` interpreter paths with
   `.repo_index/.search_venv/Scripts/python.exe` for retrieval/indexing.
4. Remove bash, shell activation, AF_UNIX, `pgrep`, and shell process discovery
   from canonical retrieval/indexing paths.
5. Put build entrypoints behind controller preflight, T14 approval, and T07
   staging.
6. Make query execution strictly read-only.
7. Make MCP a thin wrapper over canonical retrieval only.
8. Define canonical vector hash behavior across CPU/GPU tolerance.
9. Define audit-time evidence source validation separately from query-time
   retrieval behavior.
10. Ensure all runtime tool surfaces fail closed instead of falling back.

## Next Transition

No later task may execute while T16 is `BLOCKED`.

T17 requires T16 to be `PASS`.
