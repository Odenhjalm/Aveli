# T10 Execution Result - Vector Index Chroma Contract

TASK_ID: T10
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T10_define_vector_index_chroma_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T05_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T06_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T07_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T08_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T09_execution_result.md`
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

## Controller State Before T10

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `PASS`.
- `T05` was repo-visible `PASS`.
- `T06` was repo-visible `PASS`.
- `T07` was repo-visible `PASS`.
- `T08` was repo-visible `PASS`.
- `T09` was repo-visible `PASS`.
- `T10` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T10` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T10 defines the deterministic Chroma vector index contract for
controller-governed hybrid retrieval. It does not create a Chroma database, does
not create a collection, does not compute embeddings, does not create
`.repo_index`, does not install dependencies, does not download models, does
not execute CUDA, and does not execute retrieval.

## T10 Execution Plan

T10 execution was limited to:

1. no-code audit of controller state and authority inputs.
2. verification that T06, T07, and T08 were repo-visible `PASS`.
3. verification that T09 lexical parity is available as prior locked authority.
4. comparison of current contracts and tools against the T10 vector index
   scope.
5. materialization of this T10 execution result.
6. controller status update for T10 only.

No T11 retrieval contract, T12 MCP wrapper contract, T13 Windows gate, or later
task was executed.

## Vector Authority Spec

The Chroma vector index is a derived artifact under:

```text
.repo_index/chroma_db/
```

It is governed only by `.repo_index/index_manifest.json` and derived only from
`chunk_manifest.jsonl` plus the T08 model and embedding policy.

T10 owns:

- Chroma artifact binding requirements.
- Chroma collection identity requirements.
- vector entry identity and metadata requirements.
- vector artifact deterministic export hash requirements.
- vector query read-only behavior.
- vector `doc_id` parity requirements.
- vector corruption detection rules.

T10 does not own:

- corpus membership.
- T04 normalization.
- T05 chunk boundaries.
- T06 `doc_id` or hash formulas.
- T07 staging and promotion lifecycle.
- T08 model or tokenizer policy.
- T09 lexical structure.
- final retrieval ranking.
- canonical evidence shape.
- MCP behavior.

Chroma metadata may repeat manifest and chunk bindings only for verification.
It must never define missing corpus, model, ranking, device, batch, or retrieval
policy values.

## Chroma Structure

The active vector artifact path is:

```text
.repo_index/chroma_db/
```

Future builds must create it only inside the T07 staging tree first:

```text
.repo_index/_staging/<build_id>/chroma_db/
```

The active collection name must be manifest-owned. A hardcoded collection name
is not authority. Query mode must load the manifest-declared collection and
must STOP if the collection is missing, mismatched, corrupt, or not previously
verified.

The Chroma collection must contain exactly one vector entry per canonical
`doc_id` from `chunk_manifest.jsonl`.

Each Chroma entry must use:

- `id`: canonical `doc_id` from T06.
- `document`: exact canonical T05 chunk text, or a T07/T10 approved exact
  content reference if a later implementation chooses content references.
- `embedding`: manifest-governed passage embedding produced from T05 chunk text
  and T08 `passage_prefix`.
- `metadata`: verification metadata derived from `chunk_manifest.jsonl` and
  `index_manifest.json` only.

Chroma internal row order, insertion order, collection UUIDs, and storage file
layout are not canonical authority.

## Metadata Spec

Collection metadata must include:

- `artifact_type`: `chroma_vector_index`.
- `vector_contract_version`.
- `collection_name`.
- `contract_version`.
- `corpus_manifest_hash`.
- `chunk_manifest_hash`.
- `embedding_model_snapshot_hash`.
- `tokenizer_files_hash`.
- `embedding_dimension`.
- `embedding_dtype`.
- `normalize_embeddings`.
- `query_prefix`.
- `passage_prefix`.
- `doc_count`.
- `doc_id_set_hash`.
- `vector_export_hash`.
- `source_artifact`: `.repo_index/chunk_manifest.jsonl`.

Each vector entry metadata object must include:

- `doc_id`.
- `file`.
- `chunk_index`.
- `content_hash`.
- `source_type`.
- `layer`.
- `contract_version`.
- `corpus_manifest_hash`.
- `chunk_manifest_hash`.
- `embedding_model_snapshot_hash`.
- `tokenizer_files_hash`.
- `embedding_dimension`.
- `embedding_dtype`.
- `embedding_normalized`.

Metadata derived from `chunk_manifest.jsonl`:

- `doc_id`
- `file`
- `chunk_index`
- `content_hash`
- `source_type`
- `layer`

Metadata derived from `index_manifest.json`:

- `contract_version`
- `corpus_manifest_hash`
- `chunk_manifest_hash`
- `embedding_model_snapshot_hash`
- `tokenizer_files_hash`
- `embedding_dimension`
- `embedding_dtype`
- `normalize_embeddings`
- `query_prefix`
- `passage_prefix`

No metadata field may be derived from source file scanning, `search_manifest.txt`,
`searchable_files.txt`, MCP input, cache state, Chroma-internal IDs, runtime
device probing, or script constants.

## Vector Build Contract

Vector build input:

- only staging `index_manifest.json`.
- only staging `chunk_manifest.jsonl`.
- only T08 model, tokenizer, embedding, device, and batch policy.
- only T07 staging path.

Required vector build order inside the future T07 staging flow:

1. read staging `index_manifest.json`.
2. read staging `chunk_manifest.jsonl`.
3. verify `chunk_manifest_hash` using T06 rules.
4. verify no duplicate `doc_id`.
5. verify model and tokenizer locks using T08 rules.
6. compute passage embedding inputs from exact T05 chunk text plus manifest
   `passage_prefix`.
7. compute embeddings with manifest-owned dtype, dimension, normalization, and
   batch policy.
8. create or replace the staged Chroma collection only inside the staging
   `chroma_db/`.
9. add exactly one vector entry per chunk manifest record.
10. compute vector deterministic export hash.
11. verify vector `doc_id` set equals chunk manifest `doc_id` set.
12. bind vector metadata to `contract_version`, `corpus_manifest_hash`,
    `chunk_manifest_hash`, and model/tokenizer locks.

The vector index must not be built from:

- source files.
- `search_manifest.txt`.
- `searchable_files.txt`.
- `rg --files`.
- lexical index records.
- MCP output.
- query-time snippets.
- cache state.
- Chroma metadata from a previous index.

## Vector Query Contract

Query-time vector retrieval is read-only and bounded.

Vector query flow:

1. query-mode preflight validates active manifest and artifact health.
2. active Chroma collection metadata is loaded.
3. collection metadata is compared to active `index_manifest.json`.
4. vector `doc_id` set parity is verified or loaded from a previously verified
   parity export.
5. canonical retrieval supplies a query embedding under T08/T11 governance.
6. Chroma receives the query vector and manifest-owned `vector_candidate_k`.
7. vector stage returns bounded candidate `doc_id` values plus
   non-authoritative vector distance or similarity diagnostics when permitted
   by the manifest.

The vector layer must not:

- generate query embeddings by itself.
- select or load an embedding model by itself.
- define corpus membership.
- define final ranking.
- define candidate limits.
- create collections during query.
- repair collections during query.
- rebuild embeddings during query.
- write caches.
- write query memory.
- mutate Chroma state.
- read source files.
- scan the repository.
- return unbounded results.

Vector distances are candidate diagnostics only. Final ranking remains owned by
the future T11 retrieval contract and manifest `ranking_policy`.

## Vector Artifact Hash Rules

Raw Chroma directory bytes and internal SQLite or HNSW ordering must not become
the only vector artifact hash authority unless proven deterministic by T16.
T10 therefore defines a deterministic vector export hash for
`artifact_hashes.chroma_db`.

Required export records:

- one canonical record per `doc_id`.
- records ordered by T06/T07 chunk manifest order.
- each record includes `doc_id`, manifest binding metadata, chunk-derived
  metadata, and `embedding_vector_hash`.

`embedding_vector_hash` is:

```text
sha256(float32_little_endian_embedding_bytes)
```

Canonical vector export JSONL rules:

- serialize each export record using T06 canonical JSON rules.
- write one LF after each JSON record.
- no blank lines.
- no timestamps.
- no Chroma-internal IDs.
- no filesystem metadata.
- no device diagnostics.
- no insertion-order fields.

`vector_export_hash` is:

```text
sha256(canonical_vector_export_jsonl_bytes)
```

`artifact_hashes.chroma_db` must bind to `vector_export_hash` or to a later
T16-verified deterministic directory serialization that includes equivalent
semantic content. If Chroma internal bytes are not deterministic, the export
hash remains the canonical vector artifact integrity hash.

## Parity Rules

A healthy vector index must satisfy:

- Chroma `doc_id` set equals chunk manifest `doc_id` set.
- Chroma `doc_id` set equals lexical index `doc_id` set from T09.
- no duplicate Chroma IDs exist.
- every Chroma vector has exactly one chunk manifest record.
- every chunk manifest record has exactly one Chroma vector.
- `contract_version` matches active `index_manifest.json`.
- `corpus_manifest_hash` matches active `index_manifest.json`.
- `chunk_manifest_hash` matches active `index_manifest.json`.
- `embedding_model_snapshot_hash` matches active `index_manifest.json`.
- `tokenizer_files_hash` matches active `index_manifest.json`.
- embedding dimension equals manifest `embedding_policy.embedding_dimension`.
- embedding dtype equals manifest `embedding_policy.dtype`.
- vector artifact hash equals `artifact_hashes.chroma_db`.

Any mismatch is `CORRUPT_INDEX` and retrieval must STOP.

## Failure Conditions

The controller must STOP if any of these occur:

- `chroma_db/` is missing in query mode.
- the manifest-declared Chroma collection is missing.
- a collection is created during query mode.
- Chroma metadata is missing required binding fields.
- Chroma metadata mismatches `index_manifest.json`.
- Chroma `doc_id` set differs from chunk manifest `doc_id` set.
- Chroma `doc_id` set differs from lexical index `doc_id` set.
- duplicate Chroma IDs exist.
- vector IDs differ from canonical T06 `doc_id`.
- vector documents are not exact T05 chunk text or approved exact content
  references.
- vector metadata is derived from source scanning, cache, MCP, or legacy file
  lists.
- embedding dimension mismatches manifest policy.
- embedding model snapshot hash mismatches manifest policy.
- tokenizer files hash mismatches manifest policy.
- vector artifact hash mismatches the active manifest.
- query mode mutates, repairs, rebuilds, or deletes Chroma state.
- query mode generates embeddings inside the vector layer.
- query mode downloads or switches models.
- vector distance becomes final ranking authority.
- Chroma internal ordering becomes canonical output ordering.

No fallback vector search, regex search, source scan, silent repair, collection
auto-creation, or query-time rebuild is allowed.

## Contract Drift Analysis

The current repository does not yet satisfy this T10 vector index contract:

- `actual_truth/contracts/retrieval/ingestion_contract.md` still names
  `search_manifest.txt` as ingestion authority.
- `actual_truth/contracts/retrieval/index_structure_contract.md` still lists
  `.repo_index/searchable_files.txt` as authoritative and defines legacy flat
  model fields.
- `tools/index/build_vector_index.py` permits `.venv/bin/python` and
  `.repo_index/.search_venv/bin/python` instead of the Windows interpreter
  required by T03/T13.
- `tools/index/build_vector_index.py` reads `search_manifest.txt`, computes
  `corpus_manifest_hash` from it, and writes active `.repo_index` artifacts
  directly.
- `tools/index/build_vector_index.py` hardcodes collection name, chunk/model
  values, candidate limits, and batch constants outside the manifest authority.
- `tools/index/build_vector_index.py` computes vector metadata without
  `content_hash`, `contract_version`, `corpus_manifest_hash`,
  `chunk_manifest_hash`, model snapshot hash, tokenizer hash, embedding
  dimension, or dtype on each vector entry.
- `tools/index/build_vector_index.py` uses `get_or_create_collection`, modifies
  collection metadata in place, and writes Chroma directly under the active
  `.repo_index/chroma_db/` path.
- `tools/index/build_vector_index.py` removes active `chroma_db/` during
  rebuild and does not use T07 staging or promotion.
- `tools/index/build_vector_index.py` selects batch size from runtime device
  and hardcodes `normalize_embeddings=True`.
- `tools/index/search_code.py` validates only collection `contract_version` and
  `chunk_manifest_hash`, not full corpus hash, model/tokenizer lock, embedding
  dimension, vector doc-id parity, or vector artifact hash.
- `tools/index/search_code.py` loads embedding and rerank models in runtime
  query state and hardcodes query prefix behavior.
- `tools/index/search_code.py` writes query cache and query memory during query
  execution, which violates read-only retrieval requirements.
- `tools/mcp/semantic_search_server.py` uses a Linux search interpreter path,
  owns independent E5 embedding/rerank behavior, hardcodes
  `intfloat/e5-large-v2`, and runs a base search subprocess rather than
  delegating to canonical retrieval.

These are later correction targets. T10 does not patch them.

## Verification Result

T10 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, `T06`, `T07`, `T08`, and `T09` were
  repo-visible `PASS`.
- `T10` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T10` as the next executable task.
- T10 scope was limited to vector index contract design.
- T06 identity and hashing rules were treated as locked authority.
- T07 artifact structure and write order were treated as locked authority.
- T08 model and embedding policy was treated as locked authority.
- T09 lexical parity was treated as prior locked authority.
- Chroma is defined as a derived artifact only.
- vector IDs are canonical T06 `doc_id` values.
- vector documents are canonical T05 chunk text.
- vector metadata is bound to manifest and chunk-manifest authority.
- deterministic vector export hash rules are specified.
- vector query behavior is bounded and read-only.
- vector doc-id parity rules are specified.
- existing drift is identified for later controller tasks.
- no `.repo_index` directory was created.
- no Chroma database or collection was created.
- no dependency was installed.
- no model was loaded or downloaded.
- CUDA was not executed.
- no index was built.
- no retrieval query was executed.
- T11 and later tasks were not executed.

## Next Transition

Only `T11` may execute next under the strict controller order.
