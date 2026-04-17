# BUILD EXECUTION RESULT CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_BUILD_EXECUTION_CONTRACT

This contract defines the repo-visible result schema for a controller-governed
Aveli retrieval index build.

It records build execution, staging verification, promotion, artifact hashes,
and STOP conditions. It does not authorize query behavior and does not replace
T16 final verification.

## Required Result Files

A future B01 build must materialize:

- staging build result:
  `.repo_index/_staging/<build_id>/build_execution_result.json`
- staging verification result:
  `.repo_index/_staging/<build_id>/staging_verification_result.json`
- promotion result, if promotion is attempted:
  `.repo_index/promotion_result.json`

The staging result and staging verification result are not query authority.

The active index is queryable only after promotion succeeds and
`.repo_index/index_manifest.json` declares `manifest_state` as
`ACTIVE_VERIFIED`.

## Build Execution Result Schema

The build execution result must be JSON and must contain:

- `artifact_type`
- `controller_scope`
- `task_id`
- `mode`
- `status`
- `build_id`
- `approval_artifact`
- `manifest_input`
- `repo_root`
- `target_path`
- `staging_root`
- `canonical_interpreter`
- `started_at_utc`
- `completed_at_utc`
- `write_phase`
- `artifact_paths`
- `artifact_hashes`
- `verification_checkpoints`
- `failure`

Required values:

- `artifact_type`: `build_execution_result`
- `controller_scope`: `retrieval_index_build_execution`
- `task_id`: `B01`
- `mode`: `build`
- `target_path`: `.repo_index`
- `canonical_interpreter`: `.repo_index/.search_venv/Scripts/python.exe`

Allowed `status` values:

- `PASS`
- `BLOCKED`
- `CONTRACT_DRIFT`
- `CORRUPT_INDEX`
- `DEVICE_DRIFT`
- `STOP`

## Staging Result Schema

The staging verification result must be JSON and must contain:

- `artifact_type`
- `build_id`
- `staging_root`
- `status`
- `manifest_state`
- `checks`
- `doc_id_sets`
- `artifact_hashes`
- `device_check`
- `model_check`
- `tokenizer_check`
- `ordering_check`
- `forbidden_behavior_check`
- `failure`

Required values:

- `artifact_type`: `staging_verification_result`
- `manifest_state`: `STAGING_VERIFIED` when status is `PASS`

Required `checks` entries:

- `approval_valid`
- `manifest_schema_valid`
- `manifest_owned_corpus_valid`
- `corpus_manifest_hash_valid`
- `chunk_manifest_hash_valid`
- `chunk_order_valid`
- `content_hash_valid`
- `doc_id_formula_valid`
- `doc_id_unique`
- `lexical_doc_id_parity`
- `vector_doc_id_parity`
- `vector_metadata_parity`
- `embedding_dimension_valid`
- `model_lock_valid`
- `tokenizer_lock_valid`
- `artifact_hashes_valid`
- `no_active_write_before_promotion`
- `no_fallback_used`

Each check must contain:

- `status`
- `expected`
- `actual`
- `failure_class`

Allowed check status values:

- `PASS`
- `FAIL`
- `NOT_APPLICABLE`

## Promotion Result Schema

The promotion result must be JSON and must contain:

- `artifact_type`
- `build_id`
- `status`
- `source_staging_root`
- `target_path`
- `promotion_started_at_utc`
- `promotion_completed_at_utc`
- `atomic_promotion`
- `active_manifest_state`
- `active_artifact_paths`
- `active_artifact_hashes`
- `post_promotion_checks`
- `failure`

Required values when status is `PASS`:

- `artifact_type`: `promotion_result`
- `target_path`: `.repo_index`
- `atomic_promotion`: `true`
- `active_manifest_state`: `ACTIVE_VERIFIED`

Promotion must not produce a `PASS` result unless active artifacts exactly
match the verified staging artifacts.

## Artifact Hashes

All authoritative artifact hashes must be SHA-256 lowercase hex.

Required artifact hash fields:

- `index_manifest_hash`
- `corpus_manifest_hash`
- `chunk_manifest_hash`
- `lexical_index_hash`
- `chroma_db_hash`
- `vector_export_hash`
- `build_execution_result_hash`
- `staging_verification_result_hash`

Hash serialization must be canonical and deterministic:

- UTF-8 bytes
- LF line endings
- sorted object keys where JSON is serialized for hashing
- no runtime timestamps in artifact hash payloads unless the timestamp is the
  object being hashed as non-authoritative log content
- no device-dependent values in identity hashes

## Verification Checkpoints

B01 must record these checkpoint groups:

- `approval_validation`
- `windows_runtime_validation`
- `manifest_input_validation`
- `staging_write_validation`
- `chunk_manifest_validation`
- `lexical_index_validation`
- `vector_index_validation`
- `cpu_gpu_equivalence_validation`
- `artifact_hash_validation`
- `pre_promotion_validation`
- `promotion_validation`
- `post_promotion_validation`

Each checkpoint must include:

- `status`
- `authority`
- `expected`
- `actual`
- `failure_class`

## Failure Object

Every non-`PASS` result must contain a failure object:

- `failure_class`
- `stop_reason`
- `authority_file`
- `affected_path`
- `active_index_touched`
- `staging_invalidated`
- `next_allowed_action`

Allowed `failure_class` values:

- `STOP`
- `BLOCKED`
- `CONTRACT_DRIFT`
- `CORRUPT_INDEX`
- `DEVICE_DRIFT`

`active_index_touched` must be `false` for any failure before promotion.

`staging_invalidated` must be `true` for any failed build after staging was
created.

## Forbidden Success Conditions

A build result must not be `PASS` if:

- approval is missing or invalid
- approval is example-only
- active artifacts were written before promotion
- staging verification did not pass
- promotion was not atomic
- model or tokenizer lock mismatch occurred
- CPU/GPU equivalence failed
- network download was required
- dependency installation was required without explicit authority
- fallback behavior occurred
- query-time behavior was invoked
- T16 was used as build authority

CPU/GPU equivalence may be full-corpus or bounded, but the result surface must
make the approved mode explicit. A GPU-first build may report PASS without a
full-corpus CPU baseline only when the executable build approval explicitly
sets `cpu_baseline_required=false`, requires bounded equivalence verification,
and records the bounded sample size used before full-corpus GPU encoding.

## T16 Boundary

T16 may consume B01 result files and active `.repo_index` artifacts as
verification inputs.

T16 must not:

- create build result files
- create staging
- promote staging
- create `.search_venv`
- load models
- execute CUDA
- repair B01 output

If B01 result files are absent or non-`PASS`, T16 must remain `BLOCKED`.
