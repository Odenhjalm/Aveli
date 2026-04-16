# ENVIRONMENT BOOTSTRAP RESULT CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_ENVIRONMENT_EXECUTION_CONTRACT

This contract defines the repo-visible result schema for materializing the
canonical Windows retrieval/indexing interpreter:

`.repo_index/.search_venv/Scripts/python.exe`

It records environment bootstrap execution, interpreter verification,
dependency verification, forbidden side-effect checks, and STOP/BLOCKED
conditions. It does not authorize index build execution, staging, promotion,
retrieval, model loading, CUDA execution, or T16 verification.

## Required Result File

A future E01 bootstrap execution must materialize one repo-visible result file:

`actual_truth/DETERMINED_TASKS/retrieval_index_environment_bootstrap/E01_environment_bootstrap_result_<build_id>.json`

If the bootstrap is not build-bound, `<build_id>` must be replaced with a
deterministic approval identifier declared in the executable approval artifact.

The result file is not query authority and is not an index artifact.

## Result Schema

The bootstrap result must be JSON and must contain:

- `artifact_type`
- `controller_scope`
- `task_id`
- `mode`
- `status`
- `build_id`
- `approval_artifact`
- `repo_root`
- `bootstrap_source_interpreter`
- `target_interpreter_path`
- `started_at_utc`
- `completed_at_utc`
- `environment_created`
- `environment_reused`
- `interpreter_verification`
- `dependency_verification`
- `network_verification`
- `fallback_verification`
- `forbidden_side_effect_check`
- `failure`

Required values:

- `artifact_type`: `environment_bootstrap_result`
- `controller_scope`: `retrieval_index_environment_bootstrap`
- `task_id`: `E01`
- `mode`: `environment_bootstrap`
- `target_interpreter_path`: `.repo_index/.search_venv/Scripts/python.exe`

Allowed `status` values:

- `PASS`
- `BLOCKED`
- `CONTRACT_DRIFT`
- `STOP`

## Interpreter Verification Fields

`interpreter_verification` must contain:

- `status`
- `expected_path`
- `actual_path`
- `path_matches`
- `exists`
- `is_executable`
- `reported_version`
- `expected_version`
- `resolved_inside_target_root`
- `source_interpreter_verified`
- `source_interpreter_sha256_matches`
- `failure_class`

Required values when status is `PASS`:

- `expected_path`: `.repo_index/.search_venv/Scripts/python.exe`
- `actual_path`: `.repo_index/.search_venv/Scripts/python.exe`
- `path_matches`: `true`
- `exists`: `true`
- `is_executable`: `true`
- `resolved_inside_target_root`: `true`
- `source_interpreter_verified`: `true`
- `source_interpreter_sha256_matches`: `true`

## Dependency Verification Fields

`dependency_verification` must contain:

- `status`
- `dependency_install_allowed`
- `dependency_source`
- `offline_wheelhouse_path`
- `requirements_path`
- `package_hashes_checked`
- `installed_packages_match_approval`
- `unapproved_packages_present`
- `failure_class`

Required values when no dependency installation is approved:

- `dependency_install_allowed`: `false`
- `dependency_source`: `none`
- `package_hashes_checked`: `false`
- `installed_packages_match_approval`: `true`
- `unapproved_packages_present`: `false`

Required values when offline dependency installation is approved:

- `dependency_install_allowed`: `true`
- `dependency_source`: `offline_wheelhouse`
- `package_hashes_checked`: `true`
- `installed_packages_match_approval`: `true`
- `unapproved_packages_present`: `false`

## Network And Fallback Verification

`network_verification` must contain:

- `status`
- `network_policy`
- `downloads_attempted`
- `dependency_download_attempted`
- `model_download_attempted`
- `telemetry_attempted`
- `failure_class`

All attempted fields must be `false` for `PASS`.

`fallback_verification` must contain:

- `status`
- `fallbacks_allowed`
- `fallback_interpreter_used`
- `fallback_dependency_source_used`
- `fallback_network_used`
- `path_lookup_used`
- `shell_activation_used`
- `failure_class`

All fallback usage fields must be `false` for `PASS`.

## Forbidden Side-Effect Check

`forbidden_side_effect_check` must contain:

- `active_index_root_created_for_artifacts`
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

All values must be `false` for `PASS`, except the target environment root
`.repo_index/.search_venv/` may exist because it is the purpose of E01.

## Failure Object

Every non-`PASS` result must contain a failure object:

- `failure_class`
- `stop_reason`
- `authority_file`
- `affected_path`
- `environment_created`
- `active_index_touched`
- `staging_artifacts_created`
- `next_allowed_action`

Allowed `failure_class` values:

- `STOP`
- `BLOCKED`
- `CONTRACT_DRIFT`

`active_index_touched` must be `false` for every E01 result.

`staging_artifacts_created` must be `false` for every E01 result.

## Forbidden Success Conditions

An environment bootstrap result must not be `PASS` if:

- bootstrap approval is missing or invalid
- bootstrap approval is example-only
- approval phrase is not exact
- source interpreter is missing, ambiguous, unapproved, or hash-mismatched
- target interpreter path is not
  `.repo_index/.search_venv/Scripts/python.exe`
- bare `python`, `python3`, `.venv`, Linux paths, bash, shell activation, or
  fallback discovery was used outside approved bootstrap rules
- network access was required or used
- dependency installation occurred without offline hash-pinned approval
- active index artifacts were created or modified
- staging build artifacts were created
- model loading or model download occurred
- CUDA execution occurred
- B01 build execution was invoked
- T16 or T17 was invoked

## B01 And T16 Boundary

B01 may consume a `PASS` E01 result as proof that the canonical interpreter is
ready. B01 must still validate build approval, manifest input, staging, and
promotion independently.

T16 may consume E01 and B01 result files as verification inputs. T16 must not:

- create `.search_venv`
- create staging artifacts
- promote artifacts
- run build execution
- repair E01 output

If E01 result files are absent or non-`PASS` and the canonical interpreter is
missing, B01 must remain `BLOCKED` and T16 must remain verification-only.
