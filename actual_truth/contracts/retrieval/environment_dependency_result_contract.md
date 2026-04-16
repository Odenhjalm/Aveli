# ENVIRONMENT DEPENDENCY RESULT CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_ENVIRONMENT_EXECUTION_CONTRACT

This contract defines the repo-visible result schema for preparing the
canonical Windows retrieval/indexing interpreter with offline dependencies:

`.repo_index/.search_venv/Scripts/python.exe`

It records dependency preparation, package hash verification, installed package
verification, import readiness, forbidden side-effect checks, and STOP/BLOCKED
conditions. It does not authorize interpreter bootstrap, index build execution,
staging, promotion, retrieval, model loading, CUDA execution, T16 verification,
or T17 rollback.

## Required Result File

A future D01 dependency preparation execution must materialize one repo-visible
result file:

`actual_truth/DETERMINED_TASKS/retrieval_index_environment_dependencies/D01_environment_dependency_result_<build_id>.json`

The result file is not query authority and is not an index artifact.

## Result Schema

The dependency result must be JSON and must contain:

- `artifact_type`
- `controller_scope`
- `task_id`
- `mode`
- `status`
- `build_id`
- `approval_artifact`
- `repo_root`
- `target_interpreter_path`
- `e01_result`
- `b01_blocked_result`
- `started_at_utc`
- `completed_at_utc`
- `dependency_preparation_attempted`
- `package_source_verification`
- `package_hash_verification`
- `installed_package_verification`
- `import_readiness_verification`
- `network_verification`
- `fallback_verification`
- `forbidden_side_effect_check`
- `failure`

Required values:

- `artifact_type`: `environment_dependency_result`
- `controller_scope`: `retrieval_index_environment_dependencies`
- `task_id`: `D01`
- `mode`: `environment_dependencies`
- `target_interpreter_path`: `.repo_index/.search_venv/Scripts/python.exe`

Allowed `status` values:

- `PASS`
- `BLOCKED`
- `CONTRACT_DRIFT`
- `STOP`

## Package Source Verification Fields

`package_source_verification` must contain:

- `status`
- `source_type`
- `offline_wheelhouse_path`
- `requirements_lock_path`
- `wheelhouse_exists`
- `index_urls_allowed`
- `find_links_only`
- `require_hashes`
- `allow_source_builds`
- `allow_editable_installs`
- `failure_class`

Required values when status is `PASS`:

- `source_type`: `offline_wheelhouse`
- `wheelhouse_exists`: `true`
- `index_urls_allowed`: `false`
- `find_links_only`: `true`
- `require_hashes`: `true`
- `allow_source_builds`: `false`
- `allow_editable_installs`: `false`

## Package Hash Verification Fields

`package_hash_verification` must contain:

- `status`
- `approved_artifact_count`
- `checked_artifact_count`
- `missing_artifact_hashes`
- `mismatched_artifact_hashes`
- `unapproved_artifacts`
- `all_hashes_lowercase_sha256`
- `failure_class`

Required values when status is `PASS`:

- `approved_artifact_count` equals `checked_artifact_count`
- `missing_artifact_hashes`: []
- `mismatched_artifact_hashes`: []
- `unapproved_artifacts`: []
- `all_hashes_lowercase_sha256`: `true`

## Installed Package Verification Fields

`installed_package_verification` must contain:

- `status`
- `package_versions_expected`
- `package_versions_actual`
- `missing_packages`
- `version_mismatches`
- `unapproved_packages_present`
- `system_site_packages_used`
- `failure_class`

Required values when status is `PASS`:

- every direct required package is present
- every installed package version listed in approval matches exactly
- `missing_packages`: []
- `version_mismatches`: []
- `unapproved_packages_present`: `false`
- `system_site_packages_used`: `false`

## Import Readiness Verification Fields

`import_readiness_verification` must contain:

- `status`
- `direct_imports`
- `failed_imports`
- `target_interpreter_invoked`
- `model_loaded`
- `cuda_executed`
- `failure_class`

Required direct import keys:

- `chromadb`
- `numpy`
- `sentence_transformers`
- `tqdm`

Required values when status is `PASS`:

- all direct import values are `true`
- `failed_imports`: []
- `target_interpreter_invoked`: `true`
- `model_loaded`: `false`
- `cuda_executed`: `false`

Import readiness may import Python packages to prove dependency availability,
but it must not instantiate models, load model weights, run CUDA, build an
index, or query retrieval.

## Network And Fallback Verification

`network_verification` must contain:

- `status`
- `network_policy`
- `downloads_attempted`
- `dependency_download_attempted`
- `model_download_attempted`
- `telemetry_attempted`
- `package_index_attempted`
- `failure_class`

All attempted fields must be `false` for `PASS`.

`fallback_verification` must contain:

- `status`
- `fallbacks_allowed`
- `fallback_package_source_used`
- `fallback_interpreter_used`
- `fallback_network_used`
- `fallback_version_used`
- `fallback_hash_used`
- `system_site_packages_used`
- `failure_class`

All fallback usage fields must be `false` for `PASS`.

## Forbidden Side-Effect Check

`forbidden_side_effect_check` must contain:

- `active_index_manifest_created`
- `active_chunk_manifest_created`
- `active_lexical_index_created`
- `active_chroma_db_created`
- `staging_index_manifest_created`
- `staging_chunk_manifest_created`
- `staging_lexical_index_created`
- `staging_chroma_db_created`
- `model_artifacts_created`
- `index_build_executed`
- `retrieval_query_executed`
- `model_loaded`
- `cuda_executed`
- `promotion_executed`

All values must be `false` for `PASS`.

The existing `.repo_index/.search_venv/` may be modified only for dependency
preparation when approved by `environment_dependency_contract.md`.

## Failure Object

Every non-`PASS` result must contain a failure object:

- `failure_class`
- `stop_reason`
- `authority_file`
- `affected_path`
- `dependency_environment_touched`
- `active_index_touched`
- `staging_artifacts_created`
- `next_allowed_action`

Allowed `failure_class` values:

- `STOP`
- `BLOCKED`
- `CONTRACT_DRIFT`

`active_index_touched` must be `false` for every D01 result.

`staging_artifacts_created` must be `false` for every D01 result.

## Forbidden Success Conditions

A dependency preparation result must not be `PASS` if:

- dependency approval is missing or invalid
- dependency approval is example-only
- approval phrase is not exact
- E01 result is absent or not `PASS`
- B01 blocked result is absent or not dependency-readiness `BLOCKED`
- target interpreter path is not
  `.repo_index/.search_venv/Scripts/python.exe`
- offline wheelhouse is missing
- any package artifact hash is missing or mismatched
- any package version is floating or mismatched
- package index access was required or used
- network access was required or used
- fallback package source was used
- unapproved packages were installed
- direct import readiness failed
- active index artifacts were created or modified
- staging build artifacts were created
- model loading or model download occurred
- CUDA execution occurred
- B01 build execution was invoked
- T16 or T17 was invoked

## B01 And T16 Boundary

B01 may consume a `PASS` D01 result as proof that the canonical interpreter is
dependency-ready. B01 must still validate build approval, manifest input,
staging, verification, and promotion independently.

T16 may consume D01 and B01 result files as verification inputs. T16 must not:

- install dependencies
- create staging artifacts
- promote artifacts
- run build execution
- repair D01 output

If D01 result files are absent or non-`PASS` and the canonical interpreter
lacks required build dependencies, B01 must remain `BLOCKED` and T16 must
remain verification-only.
