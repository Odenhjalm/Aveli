# T13 Execution Result - Windows Compatibility Enforcement

TASK_ID: T13
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T13_define_windows_compatibility_enforcement.md`
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

## Controller State Before T13

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
- `T13` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T13` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T13 defines the Windows compatibility enforcement gate for all retrieval and
indexing controller paths. The canonical retrieval/indexing interpreter is:

`.repo_index/.search_venv/Scripts/python.exe`

The interpreter path is mandatory and singular. No Linux interpreter path, repo
`.venv`, bare Python fallback, shell activation, bash-only wrapper, AF_UNIX
socket, `pgrep`, shell process discovery, or CUDA-only correctness path is
allowed for canonical retrieval/indexing execution.

T13 does not modify `tools/index/*`, does not modify
`tools/mcp/semantic_search_server.py`, does not create `.repo_index`, does not
install dependencies, does not download or load models, does not execute CUDA,
does not run retrieval, and does not build an index.

## T13 Execution Plan

1. Load the T13 task file and controller state artifacts.
2. Verify T03, T08, T11, and T12 are repo-visible `PASS`.
3. Verify T13 is repo-visible `NOT_STARTED`.
4. Verify T13 is the only eligible next task.
5. Confirm `.repo_index` is absent.
6. Audit current Windows-incompatible surfaces statically.
7. Define Windows runtime authority, forbidden constructs, execution model, and
   STOP conditions.
8. Materialize only the T13 execution result and controller status updates.
9. Stop after T13 with T14 as the only next eligible task.

## Windows Authority Spec

T13 owns Windows compatibility enforcement for retrieval/indexing runtime
entrypoints, controller preflight, MCP transport dispatch, build invocation,
and query invocation.

T13 does not own:

- corpus membership.
- manifest schema.
- model or embedding semantics.
- chunking.
- doc_id or hashing.
- artifact structure.
- retrieval ranking.
- MCP evidence semantics.
- rebuild approval wording.

Those remain locked by T01 through T12.

T13 establishes that any future retrieval/indexing executable path must be
valid on Windows before it can be considered controller-compliant. A path that
works only through Linux shells, `/bin` interpreters, Unix sockets, `pgrep`, or
environment activation is not a valid controller path.

## Canonical Interpreter Rule

The only permitted interpreter for retrieval/indexing controller execution is:

`.repo_index/.search_venv/Scripts/python.exe`

This path is repo-root-relative and must be resolved against the controller
repo root, not the caller's current working directory.

Rules:

- preflight must require this exact interpreter path before build or query.
- build mode must not create this interpreter during preflight.
- query mode must STOP if this interpreter is missing.
- no bare `python` or `python3` fallback is allowed.
- no `.venv` interpreter is allowed for retrieval/indexing.
- no `.repo_index/.search_venv/bin/python` path is allowed.
- no runtime environment activation may be required.
- no PATH lookup may choose an interpreter.
- no environment variable may override the interpreter unless a later
  manifest-bound policy explicitly defines a deterministic override channel.

## Forbidden Paths And Features

Forbidden interpreter and path surfaces:

- `.repo_index/.search_venv/bin/python`
- `.repo_index/.search_venv/bin/*`
- `.venv/bin/python`
- `.venv/Scripts/python.exe` for retrieval/indexing
- `/bin/*`
- `/usr/bin/*`
- `/usr/local/bin/*`
- bare `python`
- bare `python3`

Forbidden shell and activation surfaces:

- `bash`
- `sh`
- `zsh`
- shell script wrappers as required execution paths.
- `source`.
- `activate`.
- shell-specific parameter expansion.
- dependence on `BASH_SOURCE`.
- dependence on current shell environment.

Forbidden process and socket surfaces:

- AF_UNIX sockets.
- Unix socket files for query server coordination.
- `pgrep`.
- process discovery through shell text matching.
- shell-dependent subprocess invocation.
- `shell=True` for retrieval/indexing controller dispatch.

Forbidden fallback behavior:

- fallback from canonical interpreter to repo `.venv`.
- fallback from canonical interpreter to system Python.
- fallback from Windows path to Linux path.
- fallback from MCP to CLI text parsing.
- fallback from retrieval to source scan, ripgrep, or regex search.
- implicit CPU/GPU switch for correctness.

## Execution Model

All retrieval/indexing tools must be callable through direct Windows-safe
process invocation:

- command target must be `.repo_index/.search_venv/Scripts/python.exe`.
- arguments must be passed as an explicit argument vector.
- invocation must not require shell parsing.
- invocation must not require shell activation.
- invocation must not depend on the caller's current working directory.
- all repo paths must resolve from a validated repo root.
- child processes must inherit only explicitly allowed environment values.
- query mode must be read-only and must not create process coordination files.

MCP execution must call canonical retrieval through a Windows-safe wrapper path
only after T12 thin-wrapper rules are satisfied. MCP must not re-enter Linux
shell wrappers or parse CLI text output.

Build execution must use the same canonical interpreter and must pass through
T14 approval and T07 staging before any index artifact can be written.

## Runtime Detection Rules

Controller preflight must detect and STOP before execution when:

- `sys.executable` is not the resolved canonical interpreter.
- an entrypoint computes or invokes `.repo_index/.search_venv/bin/python`.
- an entrypoint computes or invokes `.venv/bin/python`.
- an entrypoint computes or invokes `.venv/Scripts/python.exe` for
  retrieval/indexing.
- an entrypoint invokes `bash`, `sh`, or `zsh`.
- an entrypoint requires `source` or activation.
- an entrypoint imports or uses AF_UNIX in the retrieval/MCP runtime path.
- an entrypoint invokes `pgrep`.
- an entrypoint requires shell process discovery.
- an entrypoint depends on CUDA for correctness.
- an entrypoint dynamically selects CPU/GPU outside manifest policy.
- a query path attempts any fallback after a Windows compatibility failure.

Static verification must run before any runtime invocation. Runtime preflight
must repeat the exact checks for the selected mode.

## GPU And CPU Boundary

T13 enforces Windows compatibility, not embedding semantics. Device policy
remains locked by T08:

- CPU is the canonical correctness baseline.
- CUDA may be preferred for local build acceleration only when manifest policy
  permits it.
- CUDA is not required for correctness.
- device choice must not alter corpus membership, normalization, chunking,
  doc_id, hashing, artifact semantics, ranking, or evidence output.
- CUDA failure must not trigger implicit CPU fallback.
- CPU failure must STOP.

Windows compatibility checks must therefore reject CUDA-only assumptions in
retrieval/indexing scripts, environment setup, or MCP wrapper behavior.

## Failure Conditions

| Condition | Classification | Required Result |
| --- | --- | --- |
| Canonical interpreter missing in query mode | STOP | Query does not run and does not build. |
| Canonical interpreter missing in build mode | STOP | Build does not start and does not create venv. |
| Linux `.search_venv/bin/python` used | STOP | Runtime path rejected. |
| Repo `.venv` used for retrieval/indexing | STOP | Runtime path rejected. |
| Bare `python` or `python3` fallback used | STOP | Runtime path rejected. |
| Bash, sh, zsh, source, or activation required | STOP | Runtime path rejected. |
| AF_UNIX required by retrieval or MCP | STOP | Runtime path rejected. |
| `pgrep` required by retrieval or MCP | STOP | Runtime path rejected. |
| Shell process discovery required | STOP | Runtime path rejected. |
| CUDA required for canonical correctness | CONTRACT_DRIFT | Runtime path rejected until policy is corrected. |
| Device auto-selection changes execution semantics | DEVICE_DRIFT | Runtime path rejected. |
| MCP bypasses canonical Windows retrieval path | CONTRACT_DRIFT | MCP path rejected. |
| Query attempts fallback search after compatibility failure | STOP | Query returns no partial results. |
| Build attempts fallback interpreter after compatibility failure | STOP | Build does not start. |

User-facing failure messages must be Swedish. Any generated prompts emitted by a
future implementation must be English, complete, and copy-paste-ready.

## Contract Drift Analysis

The current repository does not yet satisfy this T13 compatibility gate:

- `codex/AVELI_OPERATING_SYSTEM.md` still contains an older index environment
  rule requiring `.repo_index/.search_venv/bin/python`, while the controller
  path is now `.repo_index/.search_venv/Scripts/python.exe`.
- `tools/index/search_code.py` defines `REPO_PYTHON` as `.venv/bin/python`.
- `tools/index/search_code.py` defines `SEARCH_PYTHON` as
  `.repo_index/.search_venv/bin/python`.
- `tools/index/search_code.py` permits approved Python execution through repo
  `.venv` or Linux `.search_venv/bin/python`.
- `tools/index/search_code.py` resolves device from runtime availability.
- `tools/index/search_code.py` uses AF_UNIX sockets.
- `tools/index/search_code.py` invokes `pgrep`.
- `tools/index/build_vector_index.py` defines `REPO_PYTHON` as
  `.venv/bin/python`.
- `tools/index/build_vector_index.py` defines `SEARCH_PYTHON` as
  `.repo_index/.search_venv/bin/python`.
- `tools/index/build_vector_index.py` permits approved Python execution through
  repo `.venv` or Linux `.search_venv/bin/python`.
- `tools/index/build_vector_index.py` resolves device from runtime availability.
- `tools/mcp/semantic_search_server.py` defines `SEARCH_PYTHON` as
  `.repo_index/.search_venv/bin/python`.
- `tools/mcp/semantic_search_server.py` performs interpreter re-exec through
  the Linux search venv path.
- `tools/mcp/semantic_search_server.py` resolves device at runtime.
- `tools/mcp/semantic_search_server.py` invokes `tools/index/search_code.py`
  through the noncanonical interpreter path.
- `tools/index/semantic_search.sh` is bash-only and uses
  `.repo_index/.search_venv/bin/python`.
- `tools/index/build_repo_index.sh` is bash-only and depends on
  `BASH_SOURCE` and shell behavior.
- `tools/index/ENVIRONMENT_SETUP.sh` is bash-only, creates
  `.repo_index/.search_venv` through `python3`, and uses
  `source .repo_index/.search_venv/bin/activate`.
- retrieval-adjacent Python entrypoints such as `analyze_results.py`,
  `codex_query.py`, `run_codex.py`, `run_codex_auto.py`, and
  `validate_codex.py` still reference `.venv/bin/python`.

These are later correction targets. T13 does not patch them.

## Verification Result

T13 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, `T06`, `T07`, `T08`, `T09`, `T10`,
  `T11`, and `T12` were repo-visible `PASS`.
- `T13` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T13` as the next executable task.
- `.repo_index` was absent before execution.
- T13 scope was limited to Windows compatibility enforcement design.
- the canonical Windows interpreter is specified exactly.
- forbidden interpreter, shell, socket, process, fallback, and CUDA-only
  constructs are specified.
- the direct Windows-safe execution model is specified.
- detection and STOP conditions are specified.
- existing drift is identified for later controller tasks.
- no `.repo_index` directory was created.
- no retrieval query was run.
- no MCP server was run.
- no dependency was installed.
- no model was loaded or downloaded.
- CUDA was not executed.
- no index was built.
- `tools/index/*` was not modified.
- `tools/mcp/semantic_search_server.py` was not modified.
- T14 and later tasks were not executed.

## Next Transition

Only `T14` may execute next under the strict controller order.
