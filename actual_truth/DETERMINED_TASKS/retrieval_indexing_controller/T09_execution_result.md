# T09 Execution Result - Lexical Index Contract

TASK_ID: T09
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T09_define_lexical_index_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T05_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T06_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T07_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T08_execution_result.md`
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

## Controller State Before T09

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `PASS`.
- `T05` was repo-visible `PASS`.
- `T06` was repo-visible `PASS`.
- `T07` was repo-visible `PASS`.
- `T08` was repo-visible `PASS`.
- `T09` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T09` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T09 defines the deterministic, persistent lexical index contract for
controller-governed hybrid retrieval. It does not build lexical artifacts, does
not scan the repository, does not create `.repo_index`, does not install
dependencies, does not download models, does not execute CUDA, and does not
execute retrieval.

## T09 Execution Plan

T09 execution was limited to:

1. no-code audit of controller state and authority inputs.
2. verification that T06 and T07 were repo-visible `PASS`.
3. verification that T04 normalization, T05 chunking, T06 identity/hashing,
   T07 artifact lifecycle, and T08 model/embedding policy were already locked.
4. comparison of current contracts and tools against the T09 lexical index
   scope.
5. materialization of this T09 execution result.
6. controller status update for T09 only.

No T10 vector contract, T11 retrieval contract, T12 MCP wrapper contract, or
later task was executed.

## Lexical Authority Spec

The lexical index is a derived artifact under:

```text
.repo_index/lexical_index/
```

It is governed only by `.repo_index/index_manifest.json` and built only from
the active or staged `chunk_manifest.jsonl` defined by T07.

T09 owns:

- lexical artifact internal structure.
- lexical tokenization policy requirements.
- persistent term-statistic requirements.
- lexical query candidate-generation contract.
- lexical artifact hash export requirements.
- lexical `doc_id` parity requirements.

T09 does not own:

- corpus membership.
- T04 normalization.
- T05 chunk boundaries.
- T06 `doc_id` and hash formulas.
- model or embedding policy.
- vector index structure.
- final retrieval ranking.
- evidence object shape.
- rebuild approval.
- MCP behavior.

The lexical index must never define corpus membership. It may repeat
`contract_version`, `corpus_manifest_hash`, `chunk_manifest_hash`, and `doc_id`
values only as verification metadata bound back to `index_manifest.json` and
`chunk_manifest.jsonl`.

## Lexical Index Structure

The canonical lexical directory must contain deterministic derived files whose
bytes can be hashed and verified. T09 defines this minimum structure:

```text
.repo_index/lexical_index/manifest.json
.repo_index/lexical_index/documents.jsonl
.repo_index/lexical_index/postings.jsonl
.repo_index/lexical_index/doc_ids.jsonl
```

`manifest.json` must contain:

- `artifact_type`: `lexical_index`.
- `lexical_contract_version`.
- `algorithm`.
- `tokenization_policy`.
- `contract_version`.
- `corpus_manifest_hash`.
- `chunk_manifest_hash`.
- `chunk_count`.
- `doc_count`.
- `doc_id_set_hash`.
- `documents_hash`.
- `postings_hash`.
- `source_artifact`: `.repo_index/chunk_manifest.jsonl`.

`documents.jsonl` must contain one canonical record per chunk:

- `doc_id`.
- `file`.
- `chunk_index`.
- `content_hash`.
- `source_type`.
- `layer`.
- `token_count`.
- `term_freqs`.

`postings.jsonl` must contain one canonical record per token:

- `token`.
- `document_frequency`.
- `collection_frequency`.
- `postings`, sorted by canonical document order.

Each posting entry must contain:

- `doc_id`.
- `term_frequency`.
- `token_positions` only if manifest policy explicitly enables positions.

`doc_ids.jsonl` must contain one canonical JSON record per `doc_id`, ordered by
T06/T07 chunk manifest order:

- `doc_id`.
- `file`.
- `chunk_index`.
- `content_hash`.

No lexical internal file may contain timestamps, absolute paths, runtime
diagnostics, process IDs, environment state, or implementation-specific object
identifiers.

## Lexical Build Contract

Lexical build input:

- only canonical `chunk_manifest.jsonl`.
- only chunk records already validated by T06 and T07.
- only manifest-owned `lexical_policy` and `retrieval_policy` values.

Required build order inside the future T07 staging flow:

1. read staging `index_manifest.json`.
2. read staging `chunk_manifest.jsonl`.
3. verify `chunk_manifest_hash` against T06 rules.
4. verify no duplicate `doc_id`.
5. tokenize each canonical chunk text or manifest-approved chunk content
   reference using manifest-owned lexical tokenization policy.
6. write lexical records in canonical order.
7. compute term statistics and postings deterministically.
8. compute lexical artifact hashes.
9. verify lexical `doc_id` set equals chunk manifest `doc_id` set.
10. bind lexical manifest to `contract_version`, `corpus_manifest_hash`, and
    `chunk_manifest_hash`.

The lexical index must not be built from:

- source files.
- `search_manifest.txt`.
- `searchable_files.txt`.
- `rg --files`.
- Chroma metadata.
- MCP output.
- query-time snippets.
- cache state.

## Tokenization Policy

Lexical tokenization must be manifest-owned and deterministic.

Required `lexical_policy` fields in `index_manifest.json`:

- `algorithm`: `persistent_lexical_bm25_v1` or another explicitly declared
  controller-approved algorithm.
- `tokenizer`: required string.
- `unicode_version`: required string when Unicode categories or casefolding are
  used.
- `tokenizer_table_hash`: required SHA-256 when tokenizer behavior depends on
  generated tables.
- `case_policy`: required string.
- `normalization_input`: required value `T05.chunk_text`.
- `stopwords_allowed`: required boolean.
- `stopwords_hash`: required when stopwords are enabled.
- `stemming_allowed`: required boolean, canonical value `false` unless a later
  task defines a deterministic stemmer lock.
- `min_token_chars`: required integer.
- `max_token_chars`: required integer.
- `token_sort`: required value `utf8_byte_ascending`.
- `bm25_k1`: required numeric value serialized deterministically.
- `bm25_b`: required numeric value serialized deterministically.

Tokenization must not depend on locale, OS, Python runtime defaults, model
tokenizers, embedding tokenizers, filesystem order, or query source.

## Lexical Query Contract

Query-time lexical retrieval is read-only and bounded.

Lexical query flow:

1. query-mode preflight validates active manifest and artifact health.
2. active `lexical_index/manifest.json` is loaded.
3. lexical manifest binding is compared to active `index_manifest.json`.
4. query text is normalized by the canonical query normalization policy.
5. query tokens are produced by the same manifest-owned lexical tokenization
   policy used at build time.
6. postings are read from the persistent lexical index only.
7. lexical candidate scores are computed only from stored lexical statistics.
8. candidate list is truncated to manifest-owned `lexical_candidate_k`.
9. lexical stage returns candidate `doc_id` values and non-authoritative
   lexical diagnostic scores only if the manifest permits diagnostics.

Lexical query must not:

- read source files.
- read `search_manifest.txt`.
- read `searchable_files.txt`.
- call `rg --files`.
- scan the repository.
- rebuild BM25 or term statistics.
- iterate every document in the corpus when an inverted postings index can
  bound work by query terms and postings.
- write caches.
- write query memory.
- rebuild artifacts.
- repair lexical artifacts.
- return unbounded results.
- define final ranking.

## Bounding Rules

Candidate bounds are owned by `.repo_index/index_manifest.json`.

Required rules:

- `retrieval_policy.lexical_candidate_k` is required.
- `lexical_candidate_k` must be an integer greater than `0`.
- lexical stage must return no more than `lexical_candidate_k` candidates.
- query input may not override this value.
- MCP may not override this value.
- CLI arguments may not override this value.
- if the candidate set exceeds the limit, truncation must be deterministic.

Lexical candidate truncation order:

1. descending lexical candidate score.
2. ascending normalized `file` path by UTF-8 byte order.
3. ascending integer `chunk_index`.

`doc_id` must not be used as a lexical tie-breaker.

Lexical candidate score is a selection mechanism only. It is not final evidence
ranking authority. Final ranking remains owned by the future T11 retrieval
contract and manifest `ranking_policy`.

## Lexical Artifact Hash Rules

T09 defines `artifact_hashes.lexical_index`.

Required hash model:

- `documents_hash = sha256(canonical documents.jsonl bytes)`.
- `postings_hash = sha256(canonical postings.jsonl bytes)`.
- `doc_id_set_hash = sha256(canonical doc_ids.jsonl bytes)`.
- `lexical_index_hash = sha256(canonical lexical artifact serialization)`.

Canonical lexical artifact serialization:

```text
AVELI_LEXICAL_INDEX_V1\n
FILE_COUNT <decimal_count>\n
PATH_LEN <decimal_path_byte_length>\n
<repo_index_relative_path_utf8_bytes>\n
CONTENT_LEN <decimal_file_byte_length>\n
<file_bytes>
...
```

Path order is UTF-8 byte ascending over repo-index-relative lexical artifact
paths. File bytes must already be canonical JSON or JSONL bytes. Filesystem
timestamps, permissions, creation time, inode numbers, and directory
enumeration order are forbidden hash inputs.

JSON and JSONL inside lexical artifacts must use the T06 canonical JSON rules:
sorted keys, UTF-8 without BOM, no insignificant whitespace, one LF per JSONL
record, no blank lines, and deterministic scalar serialization.

## Parity Rules

A healthy lexical index must satisfy:

- lexical `doc_id` set equals chunk manifest `doc_id` set.
- lexical `doc_id` values are unique.
- every lexical record has a matching chunk manifest record.
- every chunk manifest record has a matching lexical record.
- `contract_version` matches active `index_manifest.json`.
- `corpus_manifest_hash` matches active `index_manifest.json`.
- `chunk_manifest_hash` matches active `index_manifest.json`.
- `doc_id_set_hash` matches the canonical lexical `doc_ids.jsonl` bytes.
- lexical artifact hash matches `artifact_hashes.lexical_index`.

Any mismatch is `CORRUPT_INDEX` and retrieval must STOP.

## Failure Conditions

The controller must STOP if any of these occur:

- `lexical_index/` is missing in query mode.
- `lexical_index/manifest.json` is missing or invalid.
- `documents.jsonl`, `postings.jsonl`, or `doc_ids.jsonl` is missing.
- lexical artifact hash mismatches the active manifest.
- lexical `contract_version` mismatches the active manifest.
- lexical `corpus_manifest_hash` mismatches the active manifest.
- lexical `chunk_manifest_hash` mismatches the active manifest.
- lexical `doc_id` set differs from chunk manifest `doc_id` set.
- duplicate lexical `doc_id` values exist.
- lexical records are built from any source other than `chunk_manifest.jsonl`.
- tokenization policy is missing, implicit, or runtime-dependent.
- BM25 constants or scoring parameters are hardcoded outside the manifest.
- query mode rebuilds lexical records, term statistics, or BM25 state.
- query mode scans source files or the repository.
- query mode iterates the entire corpus to produce lexical candidates.
- query mode returns more than `lexical_candidate_k`.
- lexical diagnostic scores become final ranking authority.
- cache or query memory changes lexical output.

No fallback lexical search, regex search, repo scan, silent repair, or
query-time rebuild is allowed.

## Contract Drift Analysis

The current repository does not yet satisfy this T09 lexical index contract:

- `actual_truth/contracts/retrieval/ingestion_contract.md` still names
  `search_manifest.txt` as ingestion authority.
- `actual_truth/contracts/retrieval/index_structure_contract.md` still lists
  `.repo_index/searchable_files.txt` as authoritative, although its minimal
  lexical definition is directionally aligned with T09.
- `tools/index/build_vector_index.py` writes lexical artifacts directly under
  active `.repo_index/lexical_index/` rather than through T07 staging.
- `tools/index/build_vector_index.py` builds lexical records from in-memory
  `documents` and `ids` produced from `search_manifest.txt`, not by reading the
  canonical `chunk_manifest.jsonl` as the sole lexical source artifact.
- `tools/index/build_vector_index.py` tokenizes with
  `normalize_document_text(text).lower().split()` instead of a manifest-owned
  lexical tokenization policy.
- `tools/index/build_vector_index.py` strips text through
  `normalize_document_text`, which can alter canonical chunk text.
- `tools/index/build_vector_index.py` stores `avg_doc_length` as a float
  without a T09 canonical serialization policy.
- `tools/index/build_vector_index.py` does not define `postings.jsonl`,
  `doc_ids.jsonl`, `doc_id_set_hash`, or `lexical_index_hash`.
- `tools/index/search_code.py` loads all lexical records and iterates every
  record in `lexical_search`, which violates bounded query-time lexical work.
- `tools/index/search_code.py` hardcodes `BM25_K1` and `BM25_B` instead of
  manifest-owned lexical policy.
- `tools/index/search_code.py` tokenizes queries with
  `normalize_document_text(text).lower().split()` instead of the same
  manifest-owned lexical tokenization policy.
- `tools/index/search_code.py` validates lexical `contract_version` and
  `chunk_manifest_hash`, but does not fully validate lexical
  `corpus_manifest_hash`, doc-id parity, or lexical artifact hash.
- `tools/index/search_code.py` writes query cache and query memory during
  query execution, which violates read-only retrieval requirements.
- `tools/mcp/semantic_search_server.py` wraps a base search subprocess and
  independent semantic rerank instead of deferring to canonical lexical/vector
  retrieval.

These are later correction targets. T09 does not patch them.

## Verification Result

T09 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, `T06`, `T07`, and `T08` were
  repo-visible `PASS`.
- `T09` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T09` as the next executable task.
- T09 scope was limited to lexical index contract design.
- T04 normalization was treated as locked authority.
- T05 chunking was treated as locked authority.
- T06 identity and hashing were treated as locked authority.
- T07 artifact structure and write order were treated as locked authority.
- T08 model and embedding policy was treated as locked authority.
- lexical index authority is derived only from `chunk_manifest.jsonl`.
- lexical internal artifact structure is specified.
- lexical query behavior is bounded and read-only.
- lexical doc-id parity rules are specified.
- lexical artifact hash rules are specified.
- existing drift is identified for later controller tasks.
- no `.repo_index` directory was created.
- no lexical artifact was built.
- no dependency was installed.
- no model was loaded or downloaded.
- CUDA was not executed.
- no retrieval query was executed.
- T10 and later tasks were not executed.

## Next Transition

Only `T10` may execute next under the strict controller order.
