# OFFLINE WHEELHOUSE CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_ENVIRONMENT_EXECUTION_CONTRACT

This contract defines the only valid approval and validation rules for
materializing an offline wheelhouse and full dependency lock that D01 may later
use to prepare:

`.repo_index/.search_venv/Scripts/python.exe`

This contract authorizes wheelhouse and lock approval validation only. It does
not authorize dependency installation, interpreter bootstrap, index build
execution, staging artifact generation, promotion, retrieval, model loading,
CUDA execution, T16 verification, or T17 rollback.

## Exact Approval Phrase

The required approval phrase is:

`APPROVE AVELI OFFLINE WHEELHOUSE MATERIALIZATION`

The phrase must match byte-for-byte after LF normalization.

## Required Approval Artifact Shape

An executable offline wheelhouse approval artifact must be JSON and must
contain:

- `artifact_type`
- `approval_state`
- `approval_phrase`
- `approval_scope`
- `repo_root`
- `build_id`
- `wheelhouse_root`
- `dependency_lock_artifact`
- `source_policy`
- `package_set`
- `package_versions`
- `wheel_filenames`
- `wheel_hashes`
- `closure_policy`
- `network_policy`
- `fallback_policy`
- `verification_policy`
- `forbidden_targets`

Required values:

- `artifact_type`: `offline_wheelhouse_approval`
- `approval_state`: `APPROVED_FOR_SINGLE_WHEELHOUSE_MATERIALIZATION`
- `approval_phrase`: `APPROVE AVELI OFFLINE WHEELHOUSE MATERIALIZATION`
- `approval_scope.controller_scope`: `retrieval_index_environment_wheelhouse`
- `approval_scope.task_id`: `W01`
- `approval_scope.mode`: `wheelhouse_materialization`
- `approval_scope.expires_after_use`: `true`

`repo_root` must match the active controller repo root.

`build_id` must be a lowercase 64-character SHA-256 hex string and must match
the D01, B01, E01, and manifest-candidate chain when build-bound.

`wheelhouse_root` must be repo-visible or absolute local path and must not be
inside `.repo_index`.

`dependency_lock_artifact` must point to a concrete executable dependency lock.
Example-only locks are forbidden.

## Required Wheelhouse Source Type

The only allowed source type for W01 is:

`preexisting_local_artifacts`

W01 may copy or verify already-present local package artifacts into the
approved offline wheelhouse root. W01 must not download wheels, resolve
packages from indexes, build packages from source, or install packages into any
interpreter.

## Required Directory Structure

The approved wheelhouse root must contain:

- `wheels/`
- `locks/`
- `MANIFEST.sha256`

Required placement:

- package artifacts live under `wheels/`
- the dependency lock copy lives under `locks/`
- `MANIFEST.sha256` records every package artifact filename and SHA-256

The wheelhouse root must not contain interpreter files, model files, index
artifacts, query artifacts, caches, or unapproved packages.

## Required Dependency Lock Structure

The dependency lock artifact must be JSON and must contain:

- `artifact_type`
- `approval_state`
- `repo_root`
- `build_id`
- `wheelhouse_root`
- `package_set`
- `package_versions`
- `wheel_filenames`
- `wheel_hashes`
- `wheels`
- `closure`
- `network_policy`
- `fallback_policy`
- `forbidden_targets`
- `execution_policy`

Required values:

- `artifact_type`: `offline_dependency_lock`
- `approval_state`: `LOCKED_FOR_SINGLE_WHEELHOUSE_MATERIALIZATION`
- `execution_policy.example_not_executable`: `false`
- `execution_policy.must_stop_if_used`: `false`

For every wheel, `wheels` must contain one object with:

- `package_name`
- `version`
- `filename`
- `sha256`
- `direct_or_transitive`
- `required_by`
- `source_path`
- `wheelhouse_relative_path`

`sha256` must be a lowercase 64-character SHA-256 hex string. Placeholder
hashes, all-zero hashes, uppercase hashes, shortened hashes, missing hashes,
and hash values copied from examples are forbidden in executable locks.

`direct_or_transitive` must be either `direct` or `transitive`.

`required_by` must be non-empty. Direct packages must list `D01` or the direct
package surface that requires them.

## Required Package Set

The dependency lock must include the direct D01 package set at minimum:

- `chromadb`
- `numpy`
- `sentence-transformers`
- `tqdm`

The dependency lock must include the full transitive closure required by the
approved direct packages and B01 build surface. If a package is needed at D01
execution time, B01 build time, or import-readiness verification time, it must
be represented in the lock before W01 can pass.

## Completeness Rules

The closure is complete only if all are true:

- every direct required package is present as a wheel entry
- every transitive dependency needed by the direct packages is present as a
  wheel entry
- every wheel entry has exact version, exact filename, and lowercase SHA-256
- every wheel entry has an existing source path before materialization
- every wheel entry has exactly one target relative path under `wheels/`
- no wheel exists in the wheelhouse unless it is present in the lock
- `closure.complete` is `true`
- `closure.full_transitive_closure_declared` is `true`
- `closure.resolution_performed_before_w01` is `true`
- `closure.runtime_resolution_allowed` is `false`

Runtime dependency resolution is forbidden. W01 must validate an already
resolved closure; it must not solve dependencies.

## Package Hash And Filename Lock

`wheel_hashes` must map every approved wheel filename to a lowercase SHA-256
hash.

`wheel_filenames` must map each approved package name to one or more concrete
filenames. Filename-only approval is not sufficient unless the matching hash
exists in `wheel_hashes`.

Every artifact materialized by W01 must:

- be present in `wheel_hashes`
- have a matching SHA-256 hash before materialization
- have an exact package name and version matching `package_versions`
- be listed in `wheels`

## Network Policy

`network_policy` must contain:

- `mode`
- `downloads_allowed`
- `dependency_download_allowed`
- `package_index_allowed`
- `model_download_allowed`
- `telemetry_allowed`

Required values:

- `mode`: `offline`
- `downloads_allowed`: `false`
- `dependency_download_allowed`: `false`
- `package_index_allowed`: `false`
- `model_download_allowed`: `false`
- `telemetry_allowed`: `false`

## Fallback Policy

`fallback_policy` must contain:

- `fallbacks_allowed`
- `fallback_package_source_allowed`
- `fallback_network_allowed`
- `fallback_version_allowed`
- `fallback_hash_allowed`
- `fallback_resolution_allowed`
- `system_site_packages_allowed`

All values must be `false`.

## Verification Policy

`verification_policy` must require:

- approval artifact is executable and not example-only
- dependency lock artifact is executable and not example-only
- wheelhouse root is outside `.repo_index`
- wheelhouse root contains only approved files
- all source artifacts exist before materialization
- all source artifact hashes match the dependency lock
- all wheelhouse artifact hashes match after materialization
- `MANIFEST.sha256` matches the lock
- closure is declared complete
- no network or package index access was required or used
- no fallback package source was used
- no dependency installation occurred
- no active index artifact was created or modified
- no staging artifact was created
- no model was loaded or downloaded

## Forbidden Targets

The approval artifact must explicitly forbid creation or mutation of:

- `.repo_index/index_manifest.json`
- `.repo_index/chunk_manifest.jsonl`
- `.repo_index/lexical_index/`
- `.repo_index/chroma_db/`
- `.repo_index/_staging/`
- `.repo_index/models/`
- `.repo_index/model_cache/`
- `.repo_index/.search_venv/Lib/site-packages/`
- `.repo_index/.search_venv/Scripts/`

W01 must not mutate `.repo_index` for any reason.

## Mismatch Stop Conditions

Any mismatch requires STOP before wheelhouse mutation:

- missing approval artifact
- example-only approval artifact
- invalid JSON
- missing required field
- approval phrase mismatch
- approval state is not executable
- wrong task id or mode
- invalid build id
- wheelhouse root missing or inside `.repo_index`
- dependency lock missing or example-only
- dependency lock contains placeholder hashes
- package version missing or floating
- package filename missing
- package artifact hash missing, malformed, or mismatched
- source artifact missing
- package index access would be required
- dependency solver would need network
- partial dependency closure
- unapproved wheel would be materialized
- fallback package source would be used
- source build or editable install would be required
- dependency installation would occur
- model download or model loading would occur
- any `.repo_index` path would be created or modified

## Authority Boundary

This contract authorizes wheelhouse approval validation only. It does not
authorize E01, D01, B01, T16, T17, staging, promotion, retrieval, model loading,
or CUDA execution.
