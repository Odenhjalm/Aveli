# T12 Execution Result - MCP Semantic Search Wrapper Contract

TASK_ID: T12
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T12_define_mcp_semantic_search_wrapper_contract.md`
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

## Controller State Before T12

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
- `T12` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T12` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T12 defines the MCP semantic-search wrapper contract. The MCP server is a
transport wrapper over canonical T11 retrieval only. It does not own retrieval
behavior, model loading, embedding, rerank, ranking, corpus membership, cache,
artifact health, rebuild behavior, or evidence semantics.

T12 does not modify `tools/mcp/semantic_search_server.py`, does not run MCP,
does not run retrieval, does not create `.repo_index`, does not install
dependencies, does not download or load models, does not execute CUDA, and does
not build an index.

## T12 Execution Plan

T12 execution was limited to:

1. no-code audit of controller state and authority inputs.
2. verification that T11 was repo-visible `PASS`.
3. verification that T04 through T11 retrieval/indexing policies were already
   locked.
4. comparison of current MCP implementation against the T12 wrapper scope.
5. materialization of this T12 execution result.
6. controller status update for T12 only.

No T13 Windows compatibility enforcement, T14 rebuild gate, T15 controller
loop, or later task was executed.

## MCP Wrapper Authority Spec

The semantic-search MCP owns only protocol transport responsibilities:

- JSON-RPC message parsing.
- `initialize` response envelope.
- `tools/list` response envelope.
- `tools/call` dispatch for the declared `semantic_search` tool.
- syntactic input validation.
- canonical retrieval invocation.
- JSON-RPC response framing.
- JSON-RPC error envelope formatting.
- request `id` preservation.

The semantic-search MCP must call canonical T11 retrieval and return its
canonical output inside the protocol envelope. Removing the JSON-RPC and MCP
transport envelope must leave canonical retrieval output unchanged.

The MCP must never own:

- corpus membership.
- manifest schema.
- artifact health rules.
- lexical candidate behavior.
- vector candidate behavior.
- query embedding behavior.
- model or tokenizer selection.
- device policy.
- batch policy.
- rerank behavior.
- ranking formula.
- candidate limits.
- evidence shape.
- cache behavior.
- rebuild behavior.
- fallback search behavior.
- prompt construction.

MCP output is not authority. Chroma metadata is not authority. Lexical metadata
is not authority. Cache state is not authority. `index_manifest.json` remains
the only manifest and retrieval configuration authority.

## Input Contract

The MCP tool name is:

```text
semantic_search
```

The only declared tool argument is:

```json
{
  "query": "string"
}
```

Input rules:

- `arguments` must be a JSON object.
- `query` must be present.
- `query` must be a string.
- MCP may reject missing or non-string query values as invalid params.
- semantic query normalization must be performed only by canonical retrieval.
- empty or whitespace-only semantic validity must be resolved by canonical
  retrieval under T11 query normalization policy, unless a later controller
  task explicitly promotes empty-query rejection into MCP syntactic validation.
- MCP must pass the query string to canonical retrieval without lowercasing,
  trimming, prefixing, tokenizing, embedding, reranking, or rewriting it.

Forbidden input fields:

- `top_k`.
- `lexical_candidate_k`.
- `vector_candidate_k`.
- `candidate_union_limit`.
- `model`.
- `embedding_model`.
- `rerank_model`.
- `device`.
- `batch_size`.
- `rebuild`.
- `index_path`.
- `corpus`.
- `files`.
- `filters`.
- `ranking_policy`.
- `cache`.

If any forbidden field appears, MCP must STOP with invalid params rather than
ignore it silently, because silent ignores can hide attempted authority
overrides.

## Canonical Retrieval Invocation Contract

MCP may invoke only the canonical retrieval entrypoint defined by the
controller-governed implementation that satisfies T11 and later T13.

Invocation rules:

- call canonical retrieval in query mode only.
- pass only the declared query input.
- do not pass runtime overrides.
- do not call build mode.
- do not call index scripts.
- do not call `rg --files`.
- do not parse CLI text output as retrieval evidence.
- do not call a non-canonical fallback search script.
- do not create or repair artifacts before invocation.
- do not perform MCP-local preflight beyond protocol/input checks.

Canonical retrieval owns:

- manifest validation.
- artifact health checks.
- query normalization.
- lexical retrieval.
- vector retrieval.
- query embedding.
- rerank.
- ranking.
- evidence projection.
- read-only enforcement.
- STOP classification.

MCP must surface canonical retrieval results and failures without changing
their semantics.

## Output Contract

The canonical payload is the T11 retrieval output:

- an ordered list of canonical evidence objects, or
- a canonical retrieval result object explicitly defined by the retrieval
  implementation that contains only the canonical evidence list and
  non-authoritative transport-safe metadata allowed by manifest policy.

Every canonical evidence object must contain exactly:

```json
{
  "file": "string",
  "layer": "LAW | ROUTE | SERVICE | DB | POLICY | SCHEMA | MODEL | OTHER",
  "snippet": "string",
  "source_type": "chunk | ast | context",
  "score": 0.0
}
```

Output rules:

- MCP may wrap canonical retrieval output in the JSON-RPC response envelope.
- MCP may include MCP protocol fields required by the protocol.
- MCP must not add fields to individual evidence objects.
- MCP must not remove fields from evidence objects.
- MCP must not rename fields.
- MCP must not reorder evidence.
- MCP must not recompute scores.
- MCP must not truncate results with MCP-local `TOP_K`.
- MCP must not replace an error with an empty result set.
- MCP must not summarize snippets.
- MCP must not parse rendered text into pseudo-evidence.
- MCP must not expose model, device, cache, Chroma, lexical, or internal
  diagnostic fields as canonical evidence.

If an MCP protocol shape requires both `structuredContent` and text `content`,
both must be lossless projections of the same canonical retrieval payload. They
must not define an alternate evidence shape or alternate ranking.

## Error Contract

MCP errors must preserve controller semantics.

Canonical retrieval failure classes that must be preserved:

- `STOP`.
- `BLOCKED`.
- `CONTRACT_DRIFT`.
- `CORRUPT_INDEX`.
- `DEVICE_DRIFT`.

Error rules:

- JSON parse errors may use JSON-RPC `-32700`.
- unknown method may use JSON-RPC `-32601`.
- invalid tool name or invalid params may use JSON-RPC `-32602`.
- canonical retrieval failures should use a transport-safe application error
  while preserving `classification`, `message`, and failed prerequisite in
  `error.data`.
- user-facing error messages must be Swedish.
- generated prompts, if any later consumer creates them, must remain English
  and must not be generated by MCP.
- MCP must not replace `CORRUPT_INDEX` or missing index STOP with empty
  results.
- MCP must not mask a rebuild attempt as a runtime error.
- MCP must not guess causes.

The error envelope may adapt to JSON-RPC protocol, but the controller
classification and failed prerequisite must remain visible.

## Read-Only Rules

The MCP query path must not create, modify, delete, repair, or rebuild:

- `.repo_index/index_manifest.json`.
- `.repo_index/chunk_manifest.jsonl`.
- `.repo_index/lexical_index/`.
- `.repo_index/chroma_db/`.
- `.repo_index/_staging/`.
- cache files.
- query memory files.
- Chroma collections.
- lexical artifacts.
- model cache files.
- source files.

The MCP query path must not:

- create `.repo_index`.
- trigger index build.
- trigger rebuild approval.
- download models.
- install dependencies.
- select devices.
- load embedding models independently.
- embed query text independently.
- embed documents independently.
- rerank independently.
- scan source files.
- run ripgrep.
- call `search_manifest.txt` or `searchable_files.txt` as authority.
- use cache as authority.
- return partial results after retrieval failure.

## Windows Compatibility Awareness

T12 does not execute T13, but the MCP wrapper contract must be compatible with
the Windows runtime policy already defined by T03 and T08.

Future MCP implementation must use:

```text
.repo_index/.search_venv/Scripts/python.exe
```

Forbidden MCP runtime constructs:

- `.repo_index/.search_venv/bin/python`.
- `/bin/*`.
- bare `python`.
- `python3`.
- `.venv` fallback.
- bash or shell activation.
- AF_UNIX.
- `pgrep`.
- shell-based process discovery.
- environment-derived interpreter resolution.

If the canonical Windows retrieval interpreter is missing, MCP must STOP and
surface the exact missing prerequisite. It must not fall back to system Python,
repo `.venv`, Linux paths, or text-search-only behavior.

## Failure Conditions

The controller must STOP if MCP:

- hardcodes a model.
- imports embedding libraries for MCP-local semantic behavior.
- embeds queries or documents independently.
- reranks independently.
- owns `TOP_K` or candidate limits.
- owns device selection.
- owns query prefix behavior.
- parses CLI text output instead of consuming canonical retrieval objects.
- scans corpus files.
- writes cache or memory artifacts.
- creates or repairs index artifacts.
- calls build or rebuild paths.
- accepts runtime overrides for manifest-owned policy.
- uses `/bin` interpreter paths.
- uses `.venv` fallback.
- masks STOP, `CORRUPT_INDEX`, `CONTRACT_DRIFT`, or `DEVICE_DRIFT`.
- returns non-canonical evidence shape.
- reorders or truncates canonical evidence.
- rewrites snippets or scores.

No fallback MCP search, MCP-local semantic rerank, MCP-local embedding,
MCP-local ranking, or query-triggered build is allowed.

## Contract Drift Analysis

The current repository does not yet satisfy this T12 MCP wrapper contract:

- `tools/mcp/semantic_search_server.py` uses the Linux interpreter path
  `.repo_index/.search_venv/bin/python`.
- `tools/mcp/semantic_search_server.py` imports `SentenceTransformer`, `torch`,
  and `numpy` for MCP-local semantic behavior.
- `tools/mcp/semantic_search_server.py` imports and calls
  `resolve_index_device`, so MCP owns runtime device selection.
- `tools/mcp/semantic_search_server.py` hardcodes `TOP_K = 10`.
- `tools/mcp/semantic_search_server.py` hardcodes the model
  `intfloat/e5-large-v2`.
- `tools/mcp/semantic_search_server.py` defines `embed_query` and
  `embed_documents`, adds E5 prefixes, and normalizes embeddings independently.
- `tools/mcp/semantic_search_server.py` runs `tools/index/search_code.py` as a
  subprocess and parses rendered CLI text output rather than consuming
  canonical retrieval objects.
- `tools/mcp/semantic_search_server.py` defines `semantic_rerank` with
  MCP-local vector math and sorting.
- `tools/mcp/semantic_search_server.py` trims query input before canonical
  retrieval can apply T11 query normalization.
- `tools/mcp/semantic_search_server.py` returns `results` objects derived from
  parsed file/snippet pairs, not canonical evidence objects with exactly
  `file`, `layer`, `snippet`, `source_type`, and `score`.
- `tools/mcp/semantic_search_server.py` returns English error text such as
  `Parse error`, `Execution failed`, and `query must not be empty`.
- `tools/mcp/semantic_search_server.py` can return an empty result set for no
  base search results before canonical retrieval has authority over the final
  output.
- `tools/mcp/semantic_search_server.py` does not preserve controller failure
  classifications such as STOP, `CORRUPT_INDEX`, `CONTRACT_DRIFT`, or
  `DEVICE_DRIFT`.

These are later correction targets. T12 does not patch them.

## Verification Result

T12 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, `T06`, `T07`, `T08`, `T09`, `T10`, and
  `T11` were repo-visible `PASS`.
- `T12` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T12` as the next executable task.
- T12 scope was limited to MCP wrapper contract design.
- T11 read-only retrieval was treated as locked authority.
- MCP ownership is limited to JSON-RPC transport and syntactic input checks.
- MCP is forbidden from owning model, embedding, rerank, ranking, candidate
  limits, corpus, cache, artifact, rebuild, or evidence semantics.
- MCP input and output contracts are specified.
- MCP error propagation rules are specified.
- MCP read-only rules are specified.
- Windows compatibility awareness is specified without executing T13.
- existing drift is identified for later controller tasks.
- no `.repo_index` directory was created.
- no MCP server was run.
- no retrieval query was run.
- no cache or memory artifact was created.
- no dependency was installed.
- no model was loaded or downloaded.
- CUDA was not executed.
- no index was built.
- `tools/mcp/semantic_search_server.py` was not modified.
- `tools/index/*` was not modified.
- T13 and later tasks were not executed.

## Next Transition

Only `T13` may execute next under the strict controller order.
