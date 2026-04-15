# T06 Execution Result - Doc ID And Hashing Rules

TASK_ID: T06
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T06_define_doc_id_and_hashing_rules.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T05_execution_result.md`
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

## Controller State Before T06

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `PASS`.
- `T05` was repo-visible `PASS`.
- `T06` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T06` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T06 defines deterministic identity, content hash, chunk manifest hash, and
artifact hash rules for the retrieval/indexing controller. It does not compute
hashes for the live repository, does not write index artifacts, does not create
`.repo_index`, does not build an index, does not download models, does not
execute CUDA, and does not execute retrieval.

## T06 Execution Plan

T06 execution was limited to:

1. no-code audit of controller state and authority inputs.
2. verification that T04 normalization and T05 chunking are repo-visible
   `PASS`.
3. comparison of current contracts and tools against the T06 identity and
   hashing scope.
4. materialization of this T06 execution result.
5. controller status update for T06 only.

No T07 artifact structure, T09 lexical contract, or T10 vector contract was
executed.

## Identity And Hash Authority Decision

Identity and hash policy is governed only by `.repo_index/index_manifest.json`
field `identity_policy`, as defined by T02 and refined by T06.

T06 owns:

- `content_hash` formula.
- `doc_id` formula.
- canonical byte serialization for identity inputs.
- canonical JSON object serialization for hash-bound records.
- `chunk_manifest_hash` formula.
- artifact hash principles for deterministic byte representations.
- cross-artifact `doc_id` parity rules.

T06 does not own:

- corpus membership.
- T04 path or text normalization.
- T05 chunk boundaries.
- artifact directory structure and write order.
- lexical tokenization.
- vector storage format.
- embedding model or prefix behavior.
- retrieval ranking.

T04 normalized text and T05 emitted chunk boundaries are locked input
authorities for T06.

## Hash Primitive Rules

All controller-owned hashes must use SHA-256 and lowercase hexadecimal output.

Required digest shape:

- algorithm: `sha256`
- output: lowercase hex string
- length: `64` ASCII characters
- allowed characters: `0-9a-f`

Forbidden:

- MD5, SHA-1, SHA-512, BLAKE, UUID, random IDs, timestamps, object memory IDs,
  Chroma-generated IDs, database row IDs, process counters, traversal counters,
  filesystem metadata, or runtime order as identity input.
- implicit string encoding.
- locale-dependent encoding.
- JSON serialization without declared key ordering and separators.

All text inputs to hashes must be encoded as UTF-8 without BOM after T04/T05
normalization rules have already been applied.

## Content Hash Spec

`content_hash` is the SHA-256 of the exact T05 chunk payload bytes:

```text
content_hash = sha256(chunk_text_utf8_bytes)
```

Where:

- `chunk_text` is the exact T05 chunk slice.
- `chunk_text_utf8_bytes` is `chunk_text` encoded as UTF-8 without BOM.
- no prefix is added.
- no suffix is added.
- no length wrapper is added.
- no trimming, stripping, normalization, or whitespace rewrite occurs in T06.

`content_hash` must not include:

- `"passage: "`
- `"query: "`
- embedding prefixes.
- model-dependent formatting.
- tokenizer output.
- file path.
- chunk index.
- contract version.
- start or end offsets.
- device selection.
- batch size.
- runtime timestamp.

Two chunks with identical payload bytes may share the same `content_hash`. Their
`doc_id` remains distinct because `doc_id` also includes contract version,
normalized file path, and chunk index.

## Doc ID Spec

`doc_id` is the SHA-256 of a canonical length-delimited identity payload:

```text
doc_id = sha256(doc_id_payload_bytes)
```

Required identity inputs:

- `contract_version`
- normalized repo-root-relative `file` path from T04.
- integer `chunk_index` from T05.
- `content_hash` from this T06 result.

No other inputs are allowed.

Canonical payload layout:

```text
AVELI_DOC_ID_V1\n
CONTRACT_VERSION_LEN <decimal_byte_length>\n
<contract_version_utf8_bytes>\n
FILE_LEN <decimal_byte_length>\n
<file_utf8_bytes>\n
CHUNK_INDEX <decimal_integer>\n
CONTENT_HASH <64_lowercase_sha256_hex>\n
```

Payload rules:

- structural labels are ASCII.
- structural newlines are LF.
- decimal lengths have no leading zeroes except `0`.
- `contract_version` is encoded as UTF-8 without BOM.
- `file` is the exact T04 normalized file path encoded as UTF-8 without BOM.
- `chunk_index` is base-10 ASCII with no leading zeroes except `0`.
- `content_hash` must already be a valid lowercase SHA-256 hex string.

`doc_id` must not depend on:

- traversal order.
- global counters.
- object memory order.
- Chroma IDs.
- lexical index order.
- artifact write order.
- timestamps.
- source file mtime.
- embedding model.
- embedding vector values.
- CUDA/CPU device.
- batch size.
- query text.

Changing one chunk payload must change only that chunk's `content_hash` and
`doc_id`, plus aggregate hashes that necessarily include that chunk record.
Unchanged chunks in the same file or other files must retain their `doc_id`.

## Canonical JSON Serialization Rules

Any JSON object included in a controller-owned hash must serialize as canonical
JSON bytes:

- UTF-8 without BOM.
- object keys sorted by UTF-8 byte order of the key string.
- no insignificant whitespace.
- separators are exactly `,` and `:`.
- string escaping follows JSON syntax and must not introduce non-deterministic
  escaping choices.
- LF is used only where JSONL line structure requires it.
- no NaN or infinity values.
- floats are forbidden in identity and chunk-manifest hash records.
- arrays preserve their manifest-declared canonical order.

Allowed scalar values in hash-bound records:

- strings.
- integers.
- booleans.
- null only when explicitly permitted by a later task.

Forbidden in hash-bound records:

- unordered maps without canonical key sorting.
- timestamps.
- platform paths.
- absolute paths.
- filesystem metadata.
- runtime diagnostics.
- optional notes.

## Chunk Manifest Hash Spec

`chunk_manifest_hash` is:

```text
chunk_manifest_hash = sha256(canonical_chunk_manifest_jsonl_bytes)
```

Canonical chunk manifest ordering:

1. ascending T04 normalized `file` path by UTF-8 byte order.
2. ascending integer `chunk_index`.

`doc_id` must not be used to order chunk manifest records, because `doc_id` is
derived from record content and must not become an ordering authority for its
own manifest.

Each hash-bound chunk record must include at least:

- `contract_version`
- `corpus_manifest_hash`
- `file`
- `chunk_index`
- `start_char`
- `end_char`
- `source_type`
- `layer`
- `content_hash`
- `doc_id`

Each hash-bound chunk record must exclude:

- embedding text prefixes.
- embedding vectors.
- vector distances.
- lexical statistics.
- Chroma collection IDs.
- timestamps.
- tool diagnostics.
- runtime device.
- batch size.
- absolute paths.

JSONL byte rules:

- each record is serialized as canonical JSON.
- each serialized record is followed by exactly one LF.
- no blank lines are allowed.
- no trailing spaces are allowed.
- empty chunk manifests are invalid.

The hash must depend on ordered chunk records and normalized content through
`content_hash`. If chunk text is stored inside the future chunk manifest, it is
also part of the canonical JSON record. If chunk text is stored as a separate
approved artifact reference, T07 must define that reference and T16 must verify
that `content_hash` matches the referenced T05 chunk payload bytes.

## Manifest Identity Hash Rules

`manifest_id` and other manifest-level identity hashes must avoid
self-reference.

If a future controller step computes `manifest_id`, it must hash canonical
manifest JSON bytes with `manifest_id` omitted from the hashed object. Any
artifact hash fields that are not yet known during staging must be represented
by an explicit staging state, not by guessed or placeholder authority.

T06 does not compute `manifest_id`; it defines the self-reference rule for T07
and later verification.

## Artifact Hash Rules

Every artifact hash must be computed over a deterministic byte representation
defined by the task that owns that artifact:

- `corpus_manifest_hash` is owned by T04.
- `chunk_manifest_hash` is owned by T06.
- active artifact path and promotion boundaries are owned by T07.
- lexical index hash rules are finalized by T09.
- vector index hash rules are finalized by T10.
- verification execution rules are finalized by T16.

General artifact hash requirements:

- hash input must be byte-defined before hashing.
- directory artifact serialization must sort repo-index-relative paths by
  UTF-8 byte order.
- directory artifact serialization must include each file path, byte length,
  and file content bytes.
- filesystem mtimes, permissions, inode numbers, creation time, and directory
  enumeration order are forbidden hash inputs.
- implementation-specific binary stores may not become authority unless their
  deterministic export format is defined by the owning task.

## Artifact Parity Rules

For a healthy index, the canonical `doc_id` set must match exactly across:

- future `chunk_manifest.jsonl`.
- future `lexical_index/`.
- future `chroma_db/`.

Required parity checks:

- no duplicate `doc_id` in the chunk manifest.
- every lexical `doc_id` exists in the chunk manifest.
- every vector `doc_id` exists in the chunk manifest.
- lexical and vector `doc_id` sets equal the chunk manifest set.
- `contract_version` matches across all artifacts.
- `corpus_manifest_hash` matches across all artifacts.
- `chunk_manifest_hash` matches across all artifacts.

Any mismatch is `CORRUPT_INDEX` and retrieval must STOP.

## Stability Guarantees

For identical T04 normalized corpus, identical T05 chunking policy, and
identical T06 identity policy:

- `content_hash` values are identical.
- `doc_id` values are identical.
- canonical chunk record order is identical.
- canonical JSONL bytes are identical.
- `chunk_manifest_hash` is identical.
- artifact parity checks return the same result.

These guarantees are independent of:

- operating system.
- current working directory.
- filesystem traversal order.
- Python dictionary insertion order.
- CPU/GPU device.
- embedding model.
- batch size.
- Chroma internal ordering.
- lexical implementation.

## Failure Conditions

The controller must STOP before T07 if any of these occur:

- any hash algorithm is not SHA-256.
- any hash is not lowercase 64-character hex.
- `content_hash` includes an embedding prefix.
- `content_hash` is computed from text other than exact T05 chunk payload.
- `doc_id` omits `contract_version`.
- `doc_id` uses traversal order, timestamp, counter, Chroma ID, memory order, or
  embedding-derived input.
- `doc_id` payload serialization is ambiguous.
- canonical JSON serialization is not byte-defined.
- chunk manifest records are ordered by `doc_id` instead of file then
  `chunk_index`.
- any chunk record lacks required identity fields.
- any duplicate `doc_id` exists.
- changing one chunk mutates unrelated chunk `doc_id` values.
- any artifact parity check fails.
- a tool silently repairs a mismatched hash.
- query mode attempts to recompute or rebuild missing identity artifacts.

No fallback identity source is allowed.

## Contract Drift Analysis

The current repository does not yet satisfy this T06 identity and hashing
contract:

- `tools/index/build_vector_index.py` computes `content_hash` from
  `"passage: " + chunk`, which violates the T06 rule that content hash uses
  exact chunk payload bytes only.
- `tools/index/build_vector_index.py` builds `doc_id` from normalized file,
  chunk index, and content hash, but omits `contract_version`.
- `tools/index/build_vector_index.py` sorts chunk manifest records by `file`,
  `chunk_index`, and `doc_id`; T06 requires file then chunk index only.
- `tools/index/build_vector_index.py` renders chunk manifest JSON without a
  guaranteed final LF per record.
- `tools/index/build_vector_index.py` computes `corpus_manifest_hash` from raw
  `search_manifest.txt` bytes instead of T04 canonical corpus serialization.
- `tools/index/build_vector_index.py` still chunks and hashes from
  `search_manifest.txt`, not manifest-owned `corpus.files`.
- `tools/index/search_code.py` recomputes `chunk_manifest_hash` using old
  sorting that includes `doc_id`.
- `tools/index/search_code.py` still depends on flat manifest fields and
  query-time runtime state not yet governed by T06/T07.
- `tools/mcp/semantic_search_server.py` adds `"passage: "` to documents in its
  own embedding helper and is not yet a thin wrapper over canonical retrieval.
- `actual_truth/contracts/retrieval/index_structure_contract.md` still states a
  legacy flat manifest schema and must later align with nested T02/T05/T06
  policy.
- `actual_truth/contracts/retrieval/ingestion_contract.md` still names
  `search_manifest.txt` as ingestion authority.

These are later correction targets. T06 does not patch them.

## Verification Result

T06 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, and `T05` were repo-visible `PASS`.
- `T06` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T06` as the next executable task.
- T06 scope was limited to identity and hashing design.
- T04 normalization was treated as locked authority.
- T05 chunking was treated as locked authority.
- `content_hash` is defined over exact chunk payload bytes.
- `doc_id` is length-delimited and includes `contract_version`, file,
  `chunk_index`, and `content_hash`.
- canonical JSON and JSONL hash serialization are specified.
- `chunk_manifest_hash` is specified.
- artifact parity rules are specified.
- existing drift is identified for later controller tasks.
- no live repo hashes were computed.
- no index was built.
- `.repo_index` was not created.
- no model was downloaded or executed.
- CUDA was not used.
- no retrieval query was executed.
- T07 and later tasks were not executed.

## Next Transition

Only `T07` may execute next under the strict controller order.
