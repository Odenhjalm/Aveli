# T08 Execution Result - Model And Embedding Reproducibility Policy

TASK_ID: T08
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T08_define_model_and_embedding_reproducibility_policy.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T05_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T06_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T07_execution_result.md`
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

## Controller State Before T08

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `PASS`.
- `T05` was repo-visible `PASS`.
- `T06` was repo-visible `PASS`.
- `T07` was repo-visible `PASS`.
- `T08` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T08` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T08 defines the canonical model, tokenizer, embedding, device, batch, and local
availability policy for deterministic retrieval/indexing. It does not load a
model, does not download a model, does not install dependencies, does not test
CUDA, does not create `.repo_index`, does not build an index, and does not
execute retrieval.

## T08 Execution Plan

T08 execution was limited to:

1. no-code audit of controller state and authority inputs.
2. verification that T02 and T03 were repo-visible `PASS`.
3. verification that T04 normalization, T05 chunking, T06 identity/hashing, and
   T07 artifact lifecycle were already locked by prior controller results.
4. comparison of current contracts and tools against the T08 model and
   embedding reproducibility scope.
5. materialization of this T08 execution result.
6. controller status update for T08 only.

No T09 lexical contract, T10 vector contract, T11 retrieval contract, T13
Windows gate, or later task was executed.

## Model Authority Spec

Model and tokenizer authority is owned only by `.repo_index/index_manifest.json`
through the T02 `model_policy` fields. No script constant, MCP wrapper,
environment variable, package cache, Chroma metadata, lexical metadata, or
derived artifact may define a missing model value.

Required `model_policy.embedding` fields:

- `model_id`: required string. The embedding model identifier. No default is
  allowed.
- `model_revision`: required string. Must be an immutable commit, snapshot, or
  equivalent exact revision. Branch names such as `main`, `master`, `latest`,
  or empty revision strings are forbidden.
- `model_snapshot_hash`: required lowercase SHA-256 hex string. It binds the
  exact local model file set used for the build.
- `tokenizer_id`: required string. The tokenizer identifier used with the
  embedding model.
- `tokenizer_revision`: required string. Must be immutable and exact.
- `tokenizer_files_hash`: required lowercase SHA-256 hex string. It binds the
  exact tokenizer files and tokenizer configuration.
- `local_files_only`: required boolean, canonical value `true`.
- `trust_remote_code`: required boolean, canonical value `false` unless a
  future explicit controller task creates a stronger reviewed code-lock policy.
- `model_source`: required string identifying the local approved model cache or
  snapshot root without making that path authority for corpus or ranking.

Required `model_policy.rerank` fields when rerank is enabled:

- `enabled`: required boolean.
- `model_id`: required if enabled.
- `model_revision`: required immutable revision if enabled.
- `model_snapshot_hash`: required lowercase SHA-256 hex if enabled.
- `tokenizer_id`: required if the rerank implementation has tokenizer behavior.
- `tokenizer_revision`: required immutable revision if applicable.
- `tokenizer_files_hash`: required lowercase SHA-256 hex if applicable.
- `local_files_only`: required boolean, canonical value `true`.
- `trust_remote_code`: required boolean, canonical value `false` unless a
  future explicit controller task creates a stronger reviewed code-lock policy.

If rerank is disabled, the manifest must still declare `model_policy.rerank`
with `enabled = false` and all unused model-lock fields omitted or null by
schema. Runtime must not infer a rerank model.

## Embedding Policy Spec

Embedding semantics are owned only by `index_manifest.json` through
`embedding_policy`.

Required fields:

- `embedding_dimension`: required integer greater than `0`.
- `dtype`: required string, canonical baseline `float32`.
- `normalize_embeddings`: required boolean.
- `query_prefix`: required string. Empty string is allowed only if explicitly
  declared.
- `passage_prefix`: required string. Empty string is allowed only if explicitly
  declared.
- `pooling`: required string. The pooling mode must be explicit and model
  compatible.
- `max_sequence_length`: required integer greater than `0`.
- `truncate_policy`: required string. Allowed values must be schema-declared;
  silent tokenizer truncation is forbidden.
- `embedding_value_tolerance`: required object for CPU/GPU equivalence checks,
  with `absolute` and `relative` float tolerances declared by manifest.
- `query_normalization_policy`: required reference to the canonical query
  normalization policy.
- `passage_text_authority`: required string, canonical value
  `T05.chunk_text`.

Embedding inputs:

- passage embeddings use exact T05 chunk text plus the manifest-declared
  `passage_prefix`.
- query embeddings use the normalized query plus the manifest-declared
  `query_prefix`.
- `content_hash` and `doc_id` from T06 must never include query or passage
  prefixes.
- tokenizer output may influence embedding vectors only. It must not influence
  corpus membership, chunk boundaries, `content_hash`, `doc_id`, artifact
  ordering, or evidence shape.

Forbidden:

- implicit `"query: "` or `"passage: "` prefixes.
- hardcoded `normalize_embeddings`.
- hardcoded embedding dimension.
- implicit tokenizer truncation.
- dtype other than manifest-declared `float32` for canonical baseline.
- model-specific behavior outside manifest policy.

## Device Policy Spec

Device policy is owned only by `index_manifest.json` through `device_policy`.

Required fields:

- `canonical_baseline`: required string, canonical value `cpu`.
- `allowed_devices`: required ordered list, canonical values may include
  `cpu` and `cuda`.
- `preferred_local_build_device`: required string, default local preference may
  be `cuda` only when `allowed_devices` includes `cuda`.
- `cuda_required`: required boolean, canonical value `false`.
- `device_changes_semantics`: required boolean, canonical value `false`.
- `device_selection_source`: required string, canonical value `manifest`.
- `implicit_device_auto_selection_allowed`: required boolean, canonical value
  `false`.
- `environment_device_override_allowed`: required boolean, canonical value
  `false` unless a future explicit gate defines an approved override channel.

Rules:

- CPU is the canonical correctness baseline.
- CUDA may accelerate local build execution only when the manifest permits it
  and the explicit rebuild approval selects it.
- device choice must not change corpus membership, text normalization, chunk
  boundaries, chunk order, `content_hash`, `doc_id`, artifact semantics,
  ranking policy, evidence shape, or output limits.
- CUDA numerical output must match CPU reference output within
  `embedding_policy.embedding_value_tolerance`.
- if CUDA is selected and unavailable, STOP. The controller must not silently
  switch to CPU.
- if CPU is selected and unavailable or dependencies fail, STOP.
- query mode must never choose a different device because of runtime
  availability.

## Batch Policy Spec

Batch policy is owned only by `index_manifest.json` through `batch_policy`.

Required fields:

- `embedding_batch_size`: required integer.
- `embedding_batch_size_min`: required integer, canonical default range lower
  bound `32` unless the manifest explicitly locks a different reviewed range.
- `embedding_batch_size_max`: required integer, canonical default range upper
  bound `64` unless the manifest explicitly locks a different reviewed range.
- `dynamic_batch_sizing_allowed`: required boolean, canonical value `false`.
- `batch_size_changes_semantics`: required boolean, canonical value `false`.
- `rerank_batch_size`: required integer if rerank is enabled.

Rules:

- the selected embedding batch size must be explicit before build starts.
- the selected embedding batch size must be inside the manifest-declared range.
- build execution may not pick batch size from device, memory, environment, or
  runtime heuristics.
- changing batch size must not change embedding vectors outside the manifest
  tolerance.
- any batch-size-dependent output drift is `DEVICE_DRIFT` or
  `CONTRACT_DRIFT` and must STOP.

## Reproducibility Guarantees

For identical T04 normalized corpus, identical T05 chunks, identical T06
identity policy, identical T07 artifact policy, and identical T08 model,
embedding, device, and batch policy:

- model and tokenizer file locks are identical.
- passage and query embedding input strings are identical.
- embedding dimensions are identical.
- embedding dtype is `float32` for canonical baseline.
- CPU output is the reference output.
- CUDA output must match CPU reference output within manifest tolerance.
- chunk identity, artifact binding hashes, and evidence shape are device
  independent.
- selected batch size does not alter embedding semantics.
- no network, fallback model, implicit cache resolution, or device auto-switch
  can affect output.

T08 does not require bit-identical raw floating point output across all CPU and
CUDA kernels. It requires a manifest-declared equivalence tolerance and later
T16 verification. Any tolerance breach is a hard failure.

## Model Availability Rules

Before build execution:

- model files must already exist locally.
- tokenizer files must already exist locally.
- model and tokenizer revisions must match manifest locks exactly.
- local file hashes must match `model_snapshot_hash` and
  `tokenizer_files_hash`.
- dependency locks must be present and compatible with CPU baseline.
- no network access is allowed.
- no auto-download is allowed.
- no implicit package, model, tokenizer, or cache fallback is allowed.
- no model may be loaded until preflight has validated the local lock set and
  rebuild approval has been accepted.

Query mode:

- must use only the active verified manifest policy.
- must never download, switch, upgrade, or repair models.
- must never choose model or tokenizer behavior from MCP or script constants.

## Dependency Lock Rules

The canonical dependency set must support CPU correctness without CUDA-only
packages.

Required future lock data:

- Python interpreter path from T03/T13:
  `.repo_index/.search_venv/Scripts/python.exe`
- exact package names and versions.
- wheel or source hashes for retrieval/indexing dependencies.
- explicit CPU-compatible torch dependency or equivalent backend.
- optional CUDA acceleration dependency group, separate from CPU baseline.
- no install-time network behavior during preflight, query, or unapproved build.

CUDA wheels may be present only as optional local acceleration dependencies.
They must not be required for canonical correctness.

## Failure Conditions

The controller must STOP if any of these occur:

- `model_policy.embedding.model_id` is missing.
- `model_revision` is missing, mutable, branch-like, or ambiguous.
- `model_snapshot_hash` is missing or mismatched.
- tokenizer identity, revision, or files hash is missing or mismatched.
- `local_files_only` is not `true`.
- model or tokenizer download would be required.
- a fallback model or tokenizer is attempted.
- MCP or any script hardcodes a model that differs from the manifest.
- embedding dimension is missing or mismatched.
- dtype is not manifest-declared `float32` for canonical baseline.
- query or passage prefix behavior is implicit.
- tokenizer truncation or pooling behavior is implicit.
- CUDA is required for canonical correctness.
- device selection is automatic or environment-derived without manifest
  authority.
- selected device differs from manifest or rebuild approval.
- selected CUDA device is unavailable and runtime tries CPU fallback.
- embedding batch size is missing, out of range, or runtime-derived.
- batch size changes output outside tolerance.
- CPU/GPU embedding comparison exceeds manifest tolerance.
- dependency set requires CUDA-only packages for canonical correctness.

No repair, fallback, or downgrade is allowed.

## Contract Drift Analysis

The current repository does not yet satisfy this T08 model and embedding
policy:

- `tools/index/build_vector_index.py` defines hardcoded
  `CANONICAL_EMBEDDING_MODEL` and `CANONICAL_RERANK_MODEL` instead of nested
  manifest model locks.
- `tools/index/build_vector_index.py` validates legacy flat fields
  `embedding_model` and `rerank_model`, not `model_policy` and
  `embedding_policy`.
- `tools/index/build_vector_index.py` loads `SentenceTransformer` without
  exact revision/hash checks and without a local-only manifest lock.
- `tools/index/build_vector_index.py` chooses batch size from device-specific
  constants `BATCH_SIZE_GPU` and `BATCH_SIZE_CPU`.
- `tools/index/build_vector_index.py` hardcodes `normalize_embeddings=True`.
- `tools/index/build_vector_index.py` selects device through
  `resolve_index_device()` instead of manifest-only device policy.
- `tools/index/search_code.py` reads flat `embedding_model` and `rerank_model`
  fields and loads `SentenceTransformer` and `CrossEncoder` in the runtime
  query state.
- `tools/index/search_code.py` hardcodes `"query: "` prefix and
  `normalize_embeddings=True`.
- `tools/index/search_code.py` chooses rerank batch size from device-specific
  constants.
- `tools/index/device_utils.py` auto-selects CUDA when available and permits
  environment override through `AVELI_INDEX_DEVICE`.
- `tools/index/requirements.txt` pins CUDA-specific torch packages as part of
  the base dependency set.
- `tools/index/ENVIRONMENT_SETUP.sh` is bash-based, creates the search venv
  through Linux activation, installs CUDA PyTorch, and fails when CUDA is not
  available.
- `tools/mcp/semantic_search_server.py` hardcodes
  `intfloat/e5-large-v2`, owns embedding helpers, hardcodes E5 prefixes, selects
  device at runtime, and reranks independently of canonical retrieval.
- `actual_truth/contracts/retrieval/index_structure_contract.md` still defines
  legacy flat manifest model fields.
- `actual_truth/contracts/retrieval/retrieval_contract.md` still describes
  model loading constraints at retrieval level but does not yet delegate all
  model and device authority to the T02/T08 nested manifest policy.

These are later correction targets. T08 does not patch them.

## Verification Result

T08 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, `T06`, and `T07` were repo-visible
  `PASS`.
- `T08` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T08` as the next executable task.
- T08 scope was limited to model and embedding reproducibility design.
- T02 manifest authority was treated as locked.
- T03 preflight contract was treated as locked.
- T04 normalization was treated as locked.
- T05 chunking was treated as locked.
- T06 identity and hashing were treated as locked.
- T07 artifact structure and write order were treated as locked.
- CPU is defined as the canonical correctness baseline.
- CUDA is defined as optional local build acceleration only.
- model and tokenizer lock fields are fully specified.
- embedding semantics, prefixes, dtype, dimension, and tolerance are specified.
- batch policy is explicit and manifest-owned.
- existing drift is identified for later controller tasks.
- no `.repo_index` directory was created.
- no model was loaded or downloaded.
- no dependencies were installed.
- CUDA was not executed.
- no index was built.
- no retrieval query was executed.
- T09 and later tasks were not executed.

## Next Transition

Only `T09` may execute next under the strict controller order.
