# T05 Execution Result - Deterministic Chunking Specification

TASK_ID: T05
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T05_define_deterministic_chunking_specification.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_execution_result.md`
- `codex/AVELI_OPERATING_SYSTEM.md`
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

## Controller State Before T05

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `PASS`.
- `T05` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T05` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T05 defines deterministic fixed-window chunking over the T04 normalized corpus.
It does not chunk the repository, does not write `chunk_manifest.jsonl`, does
not create `.repo_index`, does not build an index, does not download models,
does not execute CUDA, and does not execute retrieval.

## T05 Execution Plan

T05 execution was limited to:

1. no-code audit of controller state and authority inputs.
2. verification that T04 normalization is repo-visible `PASS`.
3. comparison of current contracts and tools against the T05 chunking scope.
4. materialization of this T05 execution result.
5. controller status update for T05 only.

No T06 identity or hashing rules were executed.

## Chunking Authority Decision

Chunking is governed only by `.repo_index/index_manifest.json` field
`chunking_policy` as defined by T02 and refined by T05.

T05 owns:

- chunk unit definition
- chunk size and overlap validation rules
- fixed boundary algorithm
- per-file chunk index rules
- canonical chunk ordering
- empty-chunk rejection
- runtime-independent chunk determinism checks

T05 does not own:

- corpus membership
- path or text normalization
- content hash formula
- `doc_id` formula
- chunk manifest serialization hash
- embedding prefixes
- lexical indexing
- vector indexing
- retrieval ranking

T04 normalized text is the only valid chunking input. Raw files,
`search_manifest.txt`, `searchable_files.txt`, `rg --files`, Chroma metadata,
lexical metadata, query-time snippets, tokenizer output, and embedding-model
state are not valid chunking inputs.

## Chunking Policy Manifest Fields

`index_manifest.json` must provide these required `chunking_policy` fields:

| Field | Type | Required | Canonical Value Or Rule |
| --- | --- | --- | --- |
| `algorithm` | string | required | `fixed_window_char_v1` |
| `input_text_authority` | string | required | `T04.normalized_text` |
| `unit` | string | required | `unicode_code_point` |
| `chunk_size_chars` | integer | required | greater than `0` |
| `chunk_overlap_chars` | integer | required | greater than or equal to `0` and less than `chunk_size_chars` |
| `step_chars` | integer | required or derived | `chunk_size_chars - chunk_overlap_chars` |
| `first_chunk_index` | integer | required | `0` |
| `chunk_index_increment` | integer | required | `1` |
| `cross_file_chunks_allowed` | boolean | required | `false` |
| `tokenizer_dependent_boundaries` | boolean | required | `false` |
| `model_dependent_boundaries` | boolean | required | `false` |
| `adaptive_chunking_allowed` | boolean | required | `false` |
| `parallel_reorder_allowed` | boolean | required | `false` |
| `empty_chunks_allowed` | boolean | required | `false` |
| `ordering` | string | required | `file_utf8_byte_ascending_then_chunk_index` |

Legacy flat fields `chunk_size` and `chunk_overlap` are not canonical authority
under this T05 result. If retained for compatibility, they must be derived
exports of `chunking_policy.chunk_size_chars` and
`chunking_policy.chunk_overlap_chars`, never independent authority.

## Chunk Size And Overlap Spec

`chunk_size_chars` is the maximum number of Unicode code points from T04
normalized text that may appear in a chunk.

`chunk_overlap_chars` is the number of Unicode code points intentionally shared
between adjacent chunks in the same file.

The chunking step is:

```text
step_chars = chunk_size_chars - chunk_overlap_chars
```

Validation rules:

- `chunk_size_chars` must be an integer.
- `chunk_size_chars` must be greater than `0`.
- `chunk_overlap_chars` must be an integer.
- `chunk_overlap_chars` must be greater than or equal to `0`.
- `chunk_overlap_chars` must be less than `chunk_size_chars`.
- `step_chars` must be greater than `0`.
- missing, non-integer, negative, zero-step, or ambiguous values mean STOP.

The manifest must contain the executable values. Tool constants, CLI options,
environment variables, model defaults, tokenizer defaults, and MCP inputs may
not supply missing chunk size or overlap values.

## Chunk Boundary Algorithm

For each normalized file record from T04:

1. Let `text` be the T04 normalized text.
2. Let `N` be the number of Unicode code points in `text`.
3. If `N == 0`, STOP because T04 should have rejected the file.
4. Set `start = 0`.
5. Set `chunk_index = 0`.
6. While `start < N`:
   - `end = min(start + chunk_size_chars, N)`
   - `chunk_text = text[start:end]`
   - if `len(chunk_text) == 0`, STOP
   - emit the chunk boundary:
     - `file`
     - `chunk_index`
     - `start_char = start`
     - `end_char = end`
     - `chunk_text`
   - if `end == N`, stop chunking this file
   - `start = start + step_chars`
   - `chunk_index = chunk_index + 1`

Boundary rules:

- boundaries are computed over the T04 normalized Unicode code point sequence.
- boundaries are not token boundaries.
- boundaries are not byte-count boundaries.
- boundaries are not line-aware, AST-aware, markdown-aware, semantic, or
  model-aware.
- boundaries must not be adapted to file type.
- boundaries must not be adapted to embedding model context length.
- the final chunk may be shorter than `chunk_size_chars`.
- the terminal LF from T04 remains part of the final chunk when it falls within
  the final slice.
- chunks never cross file boundaries.
- chunking state resets for every file.

## Chunk Ordering Rules

Canonical chunk order is:

1. ascending T04 normalized `file` path by UTF-8 byte order.
2. ascending integer `chunk_index` within that file.

Per-file chunk index rules:

- first chunk index is `0`.
- each following chunk increments by exactly `1`.
- no gaps are allowed.
- no duplicate `(file, chunk_index)` pair is allowed.
- no global counter may define chunk identity or ordering.

Parallel execution may be used only if the emitted result is reassembled and
verified in canonical order before any artifact write, hash, embedding,
lexical indexing, vector indexing, or retrieval use.

## Chunk Record Boundary Requirements

T05 requires each future canonical chunk record to preserve enough information
to verify chunk boundaries before T06 identity and hashing are applied:

- `file`
- `chunk_index`
- `start_char`
- `end_char`
- `chunk_text` or a manifest-approved exact content reference
- `source_type` with canonical value `chunk`
- `chunking_policy.algorithm`
- `chunking_policy.chunk_size_chars`
- `chunking_policy.chunk_overlap_chars`

T06 will define `content_hash` and `doc_id`. T07 will define final artifact
write order and `chunk_manifest.jsonl` structure. T05 does not compute hashes
or identifiers.

## Edge Case Handling

Short files:

- if `N <= chunk_size_chars`, emit exactly one chunk:
  - `chunk_index = 0`
  - `start_char = 0`
  - `end_char = N`

Exact boundary files:

- if `N` is exactly divisible by `step_chars` but the previous chunk reaches
  `N`, no extra trailing chunk is emitted.
- a zero-length final slice is forbidden.

Overlap:

- overlap is allowed only within the same file.
- adjacent chunks must overlap by exactly `chunk_overlap_chars` except where
  the previous chunk is the final chunk.
- overlap must never cause `start` to remain unchanged.

Whitespace:

- chunking must not trim, strip, collapse, or otherwise rewrite chunk text.
- every non-zero slice emitted by the algorithm is preserved exactly.
- tools must not skip chunks because `chunk_text.strip()` is empty.

Newlines:

- LF characters from T04 normalized text are ordinary code points for chunking.
- no line-ending conversion occurs during T05.

## Determinism Guarantees

For identical T04 normalized corpus bytes and identical
`index_manifest.json.chunking_policy`, T05 guarantees:

- identical chunk count.
- identical `(file, chunk_index)` sequence.
- identical `start_char` and `end_char` boundaries.
- identical `chunk_text` bytes after UTF-8 encoding.
- identical canonical chunk ordering.
- no device dependence.
- no model dependence.
- no tokenizer dependence.
- no filesystem traversal dependence.
- no parallel scheduling dependence.

The same normalized corpus with a different manifest chunking policy is a
different canonical build input and must produce a different downstream artifact
binding.

## Failure Conditions

The controller must STOP before T06 if any of these occur:

- `chunking_policy` is missing.
- `algorithm` is not `fixed_window_char_v1`.
- `input_text_authority` is not `T04.normalized_text`.
- `unit` is not `unicode_code_point`.
- `chunk_size_chars` is missing, non-integer, or less than `1`.
- `chunk_overlap_chars` is missing, non-integer, or negative.
- `chunk_overlap_chars >= chunk_size_chars`.
- `step_chars <= 0`.
- any raw file text is chunked instead of T04 normalized text.
- any chunk boundary uses tokenizer output.
- any chunk boundary uses model behavior.
- any chunk boundary uses runtime heuristics or file type adaptation.
- any emitted chunk has zero code points.
- any chunk crosses a file boundary.
- any file's first `chunk_index` is not `0`.
- any file has chunk index gaps or duplicates.
- global chunk order differs from file then chunk index ordering.
- parallel execution changes emitted order.
- any tool skips chunks based on whitespace stripping.

No fallback chunker, model-aware chunker, token-based chunker, or runtime
repair is allowed.

## Contract Drift Analysis

The current repository does not yet satisfy this T05 chunking contract:

- `actual_truth/contracts/retrieval/ingestion_contract.md` still binds
  ingestion to `search_manifest.txt`, although its chunk determinism rules are
  directionally aligned with T05.
- `actual_truth/contracts/retrieval/index_structure_contract.md` still lists
  legacy flat `chunk_size` and `chunk_overlap` fields instead of the nested
  `chunking_policy` authority from T02/T05.
- `tools/index/build_vector_index.py` uses tool constants
  `CANONICAL_CHUNK_SIZE = 2000` and `CANONICAL_CHUNK_OVERLAP = 200` as private
  authority instead of manifest-owned `chunking_policy`.
- `tools/index/build_vector_index.py` validates flat manifest fields
  `chunk_size` and `chunk_overlap`, not the T05 nested policy.
- `tools/index/build_vector_index.py` chunks files from `search_manifest.txt`
  rather than manifest-owned `corpus.files`.
- `tools/index/build_vector_index.py` skips files and chunks using
  whitespace stripping, which can remove deterministic slices and create hidden
  drift.
- `tools/index/build_vector_index.py` can enter a non-progressing chunk loop if
  overlap is not fail-closed below chunk size.
- `tools/index/build_vector_index.py` does not preserve explicit
  `start_char` and `end_char` boundary data for verification.
- `tools/index/build_vector_index.py` currently includes the embedding passage
  prefix in the content hash path; T06 must correct identity and hashing.
- `tools/index/search_code.py` still validates old flat chunk manifest fields
  and reads query-time source snippets outside the future T05 chunk boundary
  contract.

These are later correction targets. T05 does not patch them.

## Verification Result

T05 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, and `T04` were repo-visible `PASS`.
- `T05` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T05` as the next executable task.
- T05 scope was limited to deterministic chunking design.
- T04 normalization was treated as locked chunking input authority.
- chunk size and overlap are manifest-owned and validated fail-closed.
- chunk boundaries are fixed-window character boundaries over normalized text.
- chunk ordering is deterministic by file then chunk index.
- edge cases and STOP conditions are specified.
- existing drift is identified for later controller tasks.
- no index was built.
- `.repo_index` was not created.
- no model was downloaded or executed.
- CUDA was not used.
- no retrieval query was executed.
- T06 and later tasks were not executed.

## Next Transition

Only `T06` may execute next under the strict controller order.
