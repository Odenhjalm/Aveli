# OFFLINE WHEELHOUSE RESULT CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_ENVIRONMENT_EXECUTION_CONTRACT

This contract defines the repo-visible result schema for W01 offline wheelhouse
materialization and dependency lock verification.

It records wheelhouse materialization, dependency closure verification, package
hash verification, forbidden side-effect checks, and STOP/BLOCKED conditions.
It does not authorize dependency installation, interpreter bootstrap, index
build execution, staging, promotion, retrieval, model loading, CUDA execution,
T16 verification, or T17 rollback.

## Required Result File

A future W01 wheelhouse materialization execution must materialize one
repo-visible result file:

`actual_truth/DETERMINED_TASKS/retrieval_index_environment_wheelhouse/W01_offline_wheelhouse_result_<build_id>.json`

The result file is not query authority and is not an index artifact.

## Result Schema

The wheelhouse result must be JSON and must contain:

- `artifact_type`
- `controller_scope`
- `task_id`
- `mode`
- `status`
- `build_id`
- `approval_artifact`
- `dependency_lock_artifact`
- `repo_root`
- `wheelhouse_root`
- `started_at_utc`
- `completed_at_utc`
- `wheelhouse_materialization_attempted`
- `approval_validation`
- `dependency_lock_verification`
- `package_source_verification`
- `wheelhouse_hash_verification`
- `closure_verification`
- `network_verification`
- `fallback_verification`
- `forbidden_side_effect_check`
- `failure`

Required values:

- `artifact_type`: `offline_wheelhouse_result`
- `controller_scope`: `retrieval_index_environment_wheelhouse`
- `task_id`: `W01`
- `mode`: `wheelhouse_materialization`

Allowed `status` values:

- `PASS`
- `BLOCKED`
- `CONTRACT_DRIFT`
- `STOP`

## Approval Validation Fields

`approval_validation` must contain:

- `status`
- `approval_artifact_valid_json`
- `approval_artifact_executable`
- `approval_phrase_exact`
- `build_id_matches`
- `wheelhouse_root_allowed`
- `dependency_lock_artifact_matches`
- `failure_class`

Required values when status is `PASS`:

- `approval_artifact_valid_json`: `true`
- `approval_artifact_executable`: `true`
- `approval_phrase_exact`: `true`
- `build_id_matches`: `true`
- `wheelhouse_root_allowed`: `true`
- `dependency_lock_artifact_matches`: `true`

## Dependency Lock Verification Fields

`dependency_lock_verification` must contain:

- `status`
- `lock_artifact_valid_json`
- `lock_artifact_executable`
- `example_only`
- `package_count`
- `direct_package_count`
- `transitive_package_count`
- `missing_direct_packages`
- `missing_required_fields`
- `placeholder_hashes`
- `floating_versions`
- `failure_class`

Required values when status is `PASS`:

- `lock_artifact_valid_json`: `true`
- `lock_artifact_executable`: `true`
- `example_only`: `false`
- `missing_direct_packages`: []
- `missing_required_fields`: []
- `placeholder_hashes`: []
- `floating_versions`: []

## Package Source Verification Fields

`package_source_verification` must contain:

- `status`
- `source_type`
- `source_artifact_count`
- `source_artifacts_exist`
- `missing_source_artifacts`
- `source_hashes_match_lock`
- `mismatched_source_hashes`
- `source_requires_network`
- `failure_class`

Required values when status is `PASS`:

- `source_type`: `preexisting_local_artifacts`
- `source_artifacts_exist`: `true`
- `missing_source_artifacts`: []
- `source_hashes_match_lock`: `true`
- `mismatched_source_hashes`: []
- `source_requires_network`: `false`

## Wheelhouse Hash Verification Fields

`wheelhouse_hash_verification` must contain:

- `status`
- `wheelhouse_root`
- `approved_wheel_count`
- `materialized_wheel_count`
- `missing_wheels`
- `unapproved_wheels`
- `mismatched_wheel_hashes`
- `manifest_sha256_written`
- `manifest_sha256_matches_lock`
- `all_hashes_lowercase_sha256`
- `failure_class`

Required values when status is `PASS`:

- `approved_wheel_count` equals `materialized_wheel_count`
- `missing_wheels`: []
- `unapproved_wheels`: []
- `mismatched_wheel_hashes`: []
- `manifest_sha256_written`: `true`
- `manifest_sha256_matches_lock`: `true`
- `all_hashes_lowercase_sha256`: `true`

## Closure Verification Fields

`closure_verification` must contain:

- `status`
- `direct_required`
- `transitive_allowed`
- `full_transitive_closure_declared`
- `closure_complete`
- `runtime_resolution_allowed`
- `missing_transitive_dependencies`
- `unapproved_dependency_edges`
- `failure_class`

Required values when status is `PASS`:

- `full_transitive_closure_declared`: `true`
- `closure_complete`: `true`
- `runtime_resolution_allowed`: `false`
- `missing_transitive_dependencies`: []
- `unapproved_dependency_edges`: []

## Network And Fallback Verification

`network_verification` must contain:

- `status`
- `network_policy`
- `downloads_attempted`
- `dependency_download_attempted`
- `package_index_attempted`
- `model_download_attempted`
- `telemetry_attempted`
- `failure_class`

All attempted fields must be `false` for `PASS`.

`fallback_verification` must contain:

- `status`
- `fallbacks_allowed`
- `fallback_package_source_used`
- `fallback_network_used`
- `fallback_version_used`
- `fallback_hash_used`
- `fallback_resolution_used`
- `system_site_packages_used`
- `failure_class`

All fallback usage fields must be `false` for `PASS`.

## Forbidden Side-Effect Check

`forbidden_side_effect_check` must contain:

- `repo_index_mutated`
- `active_index_manifest_created`
- `active_chunk_manifest_created`
- `active_lexical_index_created`
- `active_chroma_db_created`
- `staging_root_created`
- `staging_index_manifest_created`
- `staging_chunk_manifest_created`
- `staging_lexical_index_created`
- `staging_chroma_db_created`
- `canonical_interpreter_modified`
- `dependency_install_executed`
- `index_build_executed`
- `retrieval_query_executed`
- `model_loaded`
- `cuda_executed`
- `promotion_executed`
- `d01_executed`
- `b01_executed`
- `t16_executed`
- `t17_executed`

All values must be `false` for `PASS`.

## Failure Object

Every non-`PASS` result must contain a failure object:

- `failure_class`
- `stop_reason`
- `authority_file`
- `affected_path`
- `wheelhouse_touched`
- `repo_index_touched`
- `dependency_environment_touched`
- `next_allowed_action`

Allowed `failure_class` values:

- `STOP`
- `BLOCKED`
- `CONTRACT_DRIFT`

`repo_index_touched` must be `false` for every W01 result.

`dependency_environment_touched` must be `false` for every W01 result.

## Forbidden Success Conditions

A wheelhouse result must not be `PASS` if:

- wheelhouse approval is missing or invalid
- wheelhouse approval is example-only
- approval phrase is not exact
- dependency lock is missing or invalid
- dependency lock is example-only
- closure is incomplete
- any package artifact hash is missing, placeholder, or mismatched
- any package version is floating or mismatched
- any source artifact is missing
- package index access was required or used
- network access was required or used
- fallback package source was used
- unapproved wheels were materialized
- dependency installation occurred
- `.repo_index` was mutated
- active index artifacts were created or modified
- staging build artifacts were created
- model loading or model download occurred
- CUDA execution occurred
- D01 dependency preparation was invoked
- B01 build execution was invoked
- T16 or T17 was invoked

## D01, B01, And T16 Boundary

D01 may consume a `PASS` W01 result as proof that the offline wheelhouse and
dependency lock are ready. D01 must still validate its own dependency approval,
target interpreter, package installation, import readiness, and forbidden
side-effects independently.

B01 may consume D01 result files only after D01 reaches `PASS`. B01 must not
consume W01 directly as proof that the interpreter is dependency-ready.

T16 may consume W01, D01, and B01 result files as verification inputs. T16 must
not create wheelhouses, install dependencies, create staging artifacts, promote
artifacts, run build execution, or repair W01 output.

If W01 result files are absent or non-`PASS`, a real executable D01 dependency
approval must remain blocked unless a different approved offline wheelhouse and
dependency lock exist under this contract.
