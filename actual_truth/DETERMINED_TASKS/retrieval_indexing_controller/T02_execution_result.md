# T02 Execution Result - Index Manifest Schema And Authority Contract

TASK_ID: T02
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T00_execution_controller.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_define_index_manifest_schema_and_authority_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `tools/index/*`
- `tools/mcp/semantic_search_server.py`

## Controller State Before T02

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `NOT_STARTED`.
- DAG state allowed only `T02` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T02 resolves the schema and authority contract for `.repo_index/index_manifest.json`.
No runtime manifest was written, no index was built, no model was downloaded, no
CUDA path was executed, and no retrieval query was executed.

## Schema Authority Decision

`.repo_index/index_manifest.json` owns every canonical retrieval/indexing
configuration and corpus authority:

- corpus membership
- corpus hash identity
- normalization policy
- chunking policy
- chunk manifest binding
- identity and hash policy
- model and tokenizer locks
- embedding policy
- device policy
- batch policy
- lexical and vector candidate limits
- ranking and rerank policy
- classification policy
- artifact paths and integrity bindings
- Windows interpreter policy
- rebuild approval policy
- deprecated surface classification

No derived artifact may redefine these values. `chunk_manifest.jsonl`,
`lexical_index/`, `chroma_db/`, caches, MCP wrappers, runtime scans,
`search_manifest.txt`, `searchable_files.txt`, and `rg --files` are not
configuration or corpus authorities.

## Index Manifest Top-Level Schema

Required top-level fields:

- `schema_version`
- `contract_version`
- `manifest_state`
- `manifest_id`
- `controller_version`
- `repo`
- `corpus`
- `corpus_manifest_hash`
- `normalization_policy`
- `chunking_policy`
- `chunk_manifest_hash`
- `identity_policy`
- `model_policy`
- `embedding_policy`
- `device_policy`
- `batch_policy`
- `retrieval_policy`
- `ranking_policy`
- `classification_policy`
- `artifact_policy`
- `artifact_hashes`
- `verification_policy`
- `windows_runtime_policy`
- `rebuild_policy`
- `language_policy`
- `deprecated_surfaces`

Optional top-level fields:

- `diagnostics`
- `build_audit`
- `export_policy`
- `notes`

Optional fields are non-authoritative unless the field is explicitly promoted by
a later controller task. Optional fields must never override a required policy
field.

## Field-By-Field Authority Spec

| Field | Type | Required | Meaning | Authority Status | Allowed Source | Forbidden Derivations |
| --- | --- | --- | --- | --- | --- | --- |
| `schema_version` | string | required | Schema generation for the manifest shape. | Authority for manifest parser compatibility. | Controller contract. | Tool defaults, Chroma metadata, cache. |
| `contract_version` | string | required | Retrieval/indexing contract generation. | Authority for artifact compatibility. | Retrieval contracts under `actual_truth/contracts/retrieval/`. | Runtime code constants, legacy files. |
| `manifest_state` | enum string | required | `STAGING_INCOMPLETE` or `ACTIVE_VERIFIED`. | Authority for whether the manifest may serve query mode. | Controller build/promotion state. | Directory presence, partial artifact existence. |
| `manifest_id` | sha256 string | required | Deterministic identity of the manifest content under canonical serialization. | Authority for manifest identity. | Canonical manifest bytes defined by controller hashing rules. | Timestamp, random UUID, filesystem metadata. |
| `controller_version` | string | required | Controller contract generation that produced the manifest. | Authority for controller compatibility. | Retrieval indexing controller. | Tool version guessing. |
| `repo` | object | required | Repo root and path policy. | Authority for repo-relative path interpretation. | Controller input and repo-root validation. | Current working directory, absolute paths. |
| `corpus` | object | required | Canonical corpus membership. | Sole corpus authority. | Explicit sorted manifest file list inside `index_manifest.json`. | `search_manifest.txt`, `searchable_files.txt`, `rg --files`, Chroma metadata, lexical metadata. |
| `corpus_manifest_hash` | sha256 string | required | Hash of canonical corpus serialization. | Authority for corpus identity. | T04 canonical corpus serialization. | Separate file-list bytes, runtime scans. |
| `normalization_policy` | object | required | Text/path normalization rules. | Authority for normalized build input. | T04. | Tool-local normalization variants. |
| `chunking_policy` | object | required | Chunk size, overlap, and boundary rules. | Authority for chunk boundaries. | T05. | Tokenizer/model behavior, adaptive heuristics. |
| `chunk_manifest_hash` | sha256 string | required for active manifest | Hash of canonical chunk manifest JSONL bytes. | Authority for chunk artifact binding. | T06/T07 canonical chunk manifest serialization. | Chroma metadata, lexical metadata. |
| `identity_policy` | object | required | `doc_id`, content hash, and artifact hash formulas. | Authority for stable identity. | T06. | Runtime counters, timestamps, traversal order, embeddings. |
| `model_policy` | object | required | Model and tokenizer locks. | Authority for embedding/rerank model identity. | Explicit locked local model metadata. | `latest`, `main`, implicit cache, MCP hardcoding. |
| `embedding_policy` | object | required | Embedding dimension, dtype, prefixes, pooling, normalization. | Authority for vector generation semantics. | Manifest only. | SentenceTransformer defaults, device-specific defaults. |
| `device_policy` | object | required | CPU baseline and CUDA permission rules. | Authority for allowed execution device. | Manifest only. | Auto-detected CUDA, env override, tool default. |
| `batch_policy` | object | required | Fixed embedding and rerank batch sizes. | Authority for build/query batch behavior. | Manifest only. | Device-specific constants, dynamic memory probing. |
| `retrieval_policy` | object | required | Query normalization, candidate limits, output limits. | Authority for retrieval bounds. | Manifest only. | MCP input defaults, CLI defaults. |
| `ranking_policy` | object | required | Final score formula, rerank state, tie-break policy. | Authority for ranking. | Manifest only. | Lexical index, vector index, MCP, hidden boosts. |
| `classification_policy` | object | required | Path to evidence `layer` mapping. | Authority for canonical layer assignment. | Manifest only. | Analysis tools, MCP wrapper, downstream prompt code. |
| `artifact_policy` | object | required | Artifact paths, staging model, promotion boundaries. | Authority for artifact location and lifecycle. | T07. | Existing directory layout, Chroma collection creation. |
| `artifact_hashes` | object | required for active manifest | Hash bindings for required artifacts. | Authority for artifact integrity checks. | T07/T16 verification output. | Filesystem mtimes, raw Chroma internal file ordering. |
| `verification_policy` | object | required | Required integrity and determinism checks. | Authority for pass/fail validation. | T16. | Tool-specific partial validation. |
| `windows_runtime_policy` | object | required | Windows interpreter and forbidden runtime constructs. | Authority for runtime path enforcement. | T13. | `/bin/python`, shell activation, bare `python`. |
| `rebuild_policy` | object | required | Explicit approval gate and build-mode constraints. | Authority for build/rebuild permission. | T14. | Missing index, query path, MCP wrapper. |
| `language_policy` | object | required | Swedish user text and English prompt text requirements. | Authority for tool language surfaces. | Determinism contract. | Tool-local strings outside policy. |
| `deprecated_surfaces` | object | required | Declares legacy file lists and caches non-authoritative. | Authority for deprecation status. | T01. | Legacy compatibility assumptions. |
| `diagnostics` | object | optional | Non-authoritative inspection data. | Non-authoritative only. | Controller diagnostics. | Runtime decisions. |
| `build_audit` | object | optional | Non-authoritative build log summary. | Non-authoritative only. | Build controller. | Artifact validity decisions. |
| `export_policy` | object | optional | Optional debug/export behavior. | Non-authoritative only. | Controller task approval. | Corpus membership. |
| `notes` | string or object | optional | Human-readable context. | Non-authoritative only. | Controller documentation. | Any execution decision. |

## Required Nested Schema Decisions

`corpus` must contain:

- `files`: sorted array of normalized repo-root-relative paths.
- `path_sort`: fixed value `utf8_byte_ascending`.
- `path_separator`: fixed value `/`.
- `case_collision_policy`: fixed value `fail_closed`.
- `include_policy_ref`: pointer to manifest-owned inclusion policy.
- `exclude_policy_ref`: pointer to manifest-owned exclusion policy.

`model_policy` must contain:

- `embedding.model_id`
- `embedding.model_revision`
- `embedding.model_snapshot_hash`
- `embedding.tokenizer_id`
- `embedding.tokenizer_revision`
- `embedding.tokenizer_files_hash`
- `embedding.local_files_only`
- `rerank.enabled`
- `rerank.model_id` when rerank is enabled
- `rerank.model_revision` when rerank is enabled
- `rerank.model_snapshot_hash` when rerank is enabled

`embedding_policy` must contain:

- `embedding_dimension`
- `dtype` with canonical value `float32`
- `normalize_embeddings`
- `query_prefix`
- `passage_prefix`
- `pooling`
- `embedding_value_tolerance`

`device_policy` must contain:

- `canonical_baseline`: `cpu`
- `allowed_devices`: `["cpu", "cuda"]`
- `preferred_local_build_device`: `cuda`
- `cuda_required`: `false`
- `device_changes_semantics`: `false`
- `device_selection_source`: `manifest`

`batch_policy` must contain:

- `embedding_batch_size`
- `embedding_batch_size_min`: `32`
- `embedding_batch_size_max`: `64`
- `rerank_batch_size`
- `dynamic_batch_sizing_allowed`: `false`

`retrieval_policy` must contain:

- `top_k`
- `lexical_candidate_k`
- `vector_candidate_k`
- `candidate_union_limit`
- `query_normalization_policy_ref`
- `read_only`: `true`
- `query_time_rebuild_allowed`: `false`
- `query_time_repo_scan_allowed`: `false`

`ranking_policy` must contain:

- `formula`
- `score_components`
- `rerank_enabled`
- `boost_policy`
- `final_sort`
- `tie_breakers`
- `hidden_boosts_allowed`: `false`

`artifact_policy` must contain:

- `index_root`: `.repo_index`
- `active_manifest`: `.repo_index/index_manifest.json`
- `chunk_manifest`: `.repo_index/chunk_manifest.jsonl`
- `lexical_index`: `.repo_index/lexical_index/`
- `chroma_db`: `.repo_index/chroma_db/`
- `staging_root`: `.repo_index/_staging/<build_id>/`
- `direct_active_writes_allowed`: `false`

`windows_runtime_policy` must contain:

- `interpreter`: `.repo_index/.search_venv/Scripts/python.exe`
- `bare_python_allowed`: `false`
- `shell_activation_allowed`: `false`
- `bash_required`: `false`
- `af_unix_allowed`: `false`
- `pgrep_allowed`: `false`

`rebuild_policy` must contain:

- `approval_required`: `true`
- `approval_string`: `APPROVE AVELI INDEX REBUILD`
- `query_may_build`: `false`
- `mcp_may_build`: `false`
- `runtime_overrides_allowed`: `false`

## GPU-Aware Execution Policy

Canonical correctness remains CPU-compatible. CPU is the canonical baseline and
must be able to build and verify the same corpus, chunk identities, hashes,
artifact bindings, and evidence shape.

Local build execution may prefer CUDA only when all of these are true:

- manifest `device_policy.allowed_devices` includes `cuda`
- manifest `device_policy.preferred_local_build_device` is `cuda`
- CUDA is available in the approved Windows interpreter environment
- model and tokenizer locks are locally present
- `device_changes_semantics` is `false`
- verification can prove no semantic drift from the device choice

Device choice may affect only performance. It must not change corpus
membership, normalization, chunk boundaries, chunk order, content hashes,
`doc_id`, artifact semantics, evidence shape, ranking policy, or retrieval
limits.

Batch size is canonical manifest state. `embedding_batch_size` must be an
explicit integer, fixed for the build, and inside the manifest-declared range.
The default local GPU-oriented policy range is 32 through 64, but the selected
value is the only executable value. No dynamic memory-based batch sizing is
allowed.

GPU output is acceptable only if later T08/T16 verification proves it is
equivalent to the CPU baseline under the locked embedding tolerance. If
equivalence is not proven, execution must STOP rather than silently switching
device or accepting drift.

## Derived Artifact Boundaries

`chunk_manifest.jsonl` may contain:

- `doc_id`
- `file`
- `chunk_index`
- `layer`
- `source_type`
- `content_hash`
- normalized chunk text or a manifest-approved content reference
- manifest binding fields required for parity verification

It may not define corpus membership, chunking parameters, model policy,
ranking policy, device policy, or rebuild policy.

`lexical_index/` may contain:

- persistent tokenized representation
- term statistics
- doc_id lookup tables
- lexical manifest binding to `contract_version`, `corpus_manifest_hash`, and
  `chunk_manifest_hash`

It may not scan the repo at query time, rank final evidence, define corpus
membership, or override candidate limits.

`chroma_db/` may contain:

- one vector entry per `doc_id`
- embedding vector
- metadata required for parity checks
- model snapshot binding required for verification

It may not define corpus membership, model policy, ranking policy, candidate
limits, or collection creation policy.

The MCP semantic-search wrapper may consume canonical retrieval output. It may
not own embedding, rerank, candidate limits, ranking, corpus membership,
rebuild, cache, or evidence rewriting behavior.

## Contract Drift Analysis

The current repository does not yet satisfy this T02 schema contract.

- `ingestion_contract.md` still names `.repo_index/search_manifest.txt` as the
  canonical ingestion manifest.
- `index_structure_contract.md` still lists `.repo_index/searchable_files.txt`
  as an authoritative artifact and defines a flat minimum manifest schema.
- `build_repo_index.sh` creates `search_manifest.txt` and
  `searchable_files.txt`, uses bash-only execution, and relies on `rg --files`
  as a corpus-producing surface.
- `build_vector_index.py` still reads `search_manifest.txt`, computes
  `corpus_manifest_hash` from that separate file, hardcodes canonical chunk,
  model, ranking, and candidate constants, writes manifest content from tool
  code, selects batch size from device, and uses Chroma collection creation.
- `device_utils.py` still permits automatic CPU/CUDA selection from environment
  and runtime CUDA availability rather than manifest-only selection.
- `ENVIRONMENT_SETUP.sh` assumes bash activation and CUDA PyTorch installation.
- `semantic_search.sh` and `semantic_search_server.py` still use
  `.repo_index/.search_venv/bin/python` rather than the canonical Windows
  interpreter path.
- `semantic_search_server.py` still hardcodes `intfloat/e5-large-v2`, owns
  embedding and rerank behavior, and calls the base search flow instead of
  wrapping canonical retrieval.
- `search_code.py` still requires `search_manifest.txt`, uses AF_UNIX and
  `pgrep`, writes cache/query-memory state during query, and loads models in a
  way not yet governed by the full manifest schema.
- `requirements.txt` pins CUDA wheels, which conflicts with CPU-compatible
  canonical baseline policy.

These are implementation and contract corrections for later tasks. T02 does
not patch them.

## Verification Result

T02 passed because:

- T01 authority was loaded and respected.
- T02 was the only eligible task.
- A single manifest-owned schema authority is declared.
- Required top-level fields are defined.
- Required model, tokenizer, device, batch, retrieval, ranking, artifact,
  Windows, rebuild, and language policy fields are defined.
- Derived artifact boundaries are explicit.
- GPU acceleration is allowed only as performance behavior and cannot change
  canonical semantics.
- Existing contract/tool drift is identified for later tasks.
- No index was built.
- `.repo_index` was not created.
- No model was downloaded or executed.
- CUDA was not used.
- No retrieval query was executed.
- T03 was not executed.

## Next Transition

Only `T03` may execute next, under controller governance.
