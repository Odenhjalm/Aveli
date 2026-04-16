# ENVIRONMENT DEPENDENCY CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_ENVIRONMENT_EXECUTION_CONTRACT

This contract defines the only valid approval and validation rules for
preparing the canonical Windows retrieval/indexing interpreter with offline
dependencies required for B01:

`.repo_index/.search_venv/Scripts/python.exe`

This contract authorizes dependency preparation only. It does not authorize
interpreter bootstrap, index build execution, staging artifact generation,
promotion, retrieval, model loading, CUDA execution, T16 verification, or T17
rollback.

## Exact Approval Phrase

The required approval phrase is:

`APPROVE AVELI OFFLINE DEPENDENCY PREPARATION`

The phrase must match byte-for-byte after LF normalization.

Invalid phrase forms:

- translated phrase
- paraphrased phrase
- lowercased phrase
- abbreviated phrase
- phrase only present in conversation and not in the approval artifact

## Required Artifact Shape

An executable environment dependency approval artifact must be JSON and must
contain these top-level fields:

- `artifact_type`
- `approval_state`
- `approval_phrase`
- `approval_scope`
- `repo_root`
- `build_id`
- `target_interpreter_path`
- `e01_result`
- `b01_blocked_result`
- `package_set`
- `package_versions`
- `package_hashes`
- `package_source_policy`
- `network_policy`
- `fallback_policy`
- `verification_policy`
- `forbidden_targets`

## Required Field Semantics

`artifact_type` must be `environment_dependency_approval`.

`approval_state` must be `APPROVED_FOR_SINGLE_DEPENDENCY_PREPARATION`.

`approval_phrase` must be exactly
`APPROVE AVELI OFFLINE DEPENDENCY PREPARATION`.

`approval_scope` must describe one dependency preparation attempt only and must
include:

- `controller_scope`
- `task_id`
- `mode`
- `expires_after_use`

Required values:

- `controller_scope`: `retrieval_index_environment_dependencies`
- `task_id`: `D01`
- `mode`: `environment_dependencies`
- `expires_after_use`: `true`

`repo_root` must be the repo root being approved.

`build_id` must be a lowercase 64-character SHA-256 hex string and must match
the linked E01 result, B01 blocked result, B01 build approval, and manifest
candidate when those artifacts are build-bound.

`target_interpreter_path` must be exactly:

`.repo_index/.search_venv/Scripts/python.exe`

## Required Packages

The minimum direct B01 build imports are:

- `chromadb`
- `numpy`
- `sentence-transformers`
- `tqdm`

An executable dependency approval artifact must include these direct packages
in `package_set.direct_required`.

Because direct packages may require runtime transitive dependencies, the
approval artifact must also include the full allowed transitive package
closure in `package_set.transitive_allowed`. The transitive set must include
every wheel or source distribution that may be installed, including model
runtime packages such as `torch`, `transformers`, `scikit-learn`, and `scipy`
when required by the approved direct packages.

Packages present in `tools/index/requirements.txt` are build-surface
candidates and may be approved only when fixed by exact version and hash.

## Version Lock Rule

Every package in `package_set.direct_required` and
`package_set.transitive_allowed` must have an exact version in
`package_versions`.

Forbidden version forms:

- ranges
- wildcards
- floating tags
- latest
- unpinned local directory installs
- editable installs

Version strings may include local build suffixes, such as CUDA build suffixes,
only when the exact artifact hash is also listed.

## Package Source Policy

`package_source_policy` must contain:

- `source_type`
- `offline_wheelhouse_path`
- `requirements_lock_path`
- `index_urls_allowed`
- `find_links_only`
- `require_hashes`
- `allow_source_builds`
- `allow_editable_installs`

Required values:

- `source_type`: `offline_wheelhouse`
- `offline_wheelhouse_path`: repo-visible or absolute local path
- `requirements_lock_path`: repo-visible lock file or `null`
- `index_urls_allowed`: `false`
- `find_links_only`: `true`
- `require_hashes`: `true`
- `allow_source_builds`: `false`
- `allow_editable_installs`: `false`

The offline wheelhouse is required. Runtime resolution from PyPI, package
indexes, GitHub, Hugging Face, local uncontrolled caches, system site packages,
or dynamic discovery is forbidden.

## Package Hash Requirement

`package_hashes` must map each approved package artifact filename to a
lowercase SHA-256 hash.

Every artifact installed or inspected by D01 must:

- be present in `package_hashes`
- have a matching SHA-256 hash before installation
- have an exact package name and version matching `package_versions`

Hash-pinning the top-level packages is not enough. The full transitive closure
must be hash-pinned.

## Network Policy

`network_policy` must contain:

- `mode`
- `downloads_allowed`
- `dependency_download_allowed`
- `model_download_allowed`
- `telemetry_allowed`
- `package_index_allowed`

Required values:

- `mode`: `offline`
- `downloads_allowed`: `false`
- `dependency_download_allowed`: `false`
- `model_download_allowed`: `false`
- `telemetry_allowed`: `false`
- `package_index_allowed`: `false`

## Fallback Policy

`fallback_policy` must contain:

- `fallbacks_allowed`
- `fallback_package_source_allowed`
- `fallback_interpreter_allowed`
- `fallback_network_allowed`
- `fallback_version_allowed`
- `fallback_hash_allowed`
- `system_site_packages_allowed`

All values must be `false`.

## Verification Policy

`verification_policy` must require:

- target interpreter path exists
- target interpreter path equals `.repo_index/.search_venv/Scripts/python.exe`
- E01 result is `PASS`
- B01 blocked result failure class is `BLOCKED`
- B01 blocked result reason is dependency readiness
- every package artifact hash matches approval before installation
- installed package versions match approval after installation
- direct imports succeed for `chromadb`, `numpy`, `sentence_transformers`, and
  `tqdm`
- no package exists in the canonical interpreter unless it is approved or part
  of Python's standard library / bootstrap metadata
- no network access was required or used
- no fallback package source was used
- no active index artifact was created or modified
- no staging build artifact was created
- no model was loaded or downloaded

## Forbidden Targets

The approval artifact must explicitly forbid creation or mutation of:

- `.repo_index/index_manifest.json`
- `.repo_index/chunk_manifest.jsonl`
- `.repo_index/lexical_index/`
- `.repo_index/chroma_db/`
- `.repo_index/_staging/<build_id>/index_manifest.json`
- `.repo_index/_staging/<build_id>/chunk_manifest.jsonl`
- `.repo_index/_staging/<build_id>/lexical_index/`
- `.repo_index/_staging/<build_id>/chroma_db/`
- `.repo_index/models/`
- `.repo_index/model_cache/`

The only allowed `.repo_index` mutation during D01 is dependency installation
inside the existing canonical virtual environment:

`.repo_index/.search_venv/`

## Validation Rules

Dependency approval validation must occur before any dependency mutation.

The controller must verify:

- artifact is valid JSON
- required top-level fields are present
- `artifact_type` is `environment_dependency_approval`
- `approval_state` is `APPROVED_FOR_SINGLE_DEPENDENCY_PREPARATION`
- approval phrase is exact
- `repo_root` matches the active controller repo root
- `build_id` is valid and matches linked artifacts
- target path is exactly `.repo_index/.search_venv/Scripts/python.exe`
- E01 result is `PASS`
- B01 blocked result is dependency-readiness BLOCKED
- package source is an approved offline wheelhouse
- exact versions are present for every approved package
- SHA-256 hash is present for every approved artifact
- network permissions are false
- fallback permissions are false
- forbidden target list covers active index, staging index, and model artifact
  paths

## Mismatch Stop Conditions

Any mismatch requires STOP before dependency mutation:

- missing approval artifact
- example-only approval artifact
- invalid JSON
- missing required field
- unknown required field semantics
- approval phrase mismatch
- approval state is not executable
- wrong task id
- wrong mode
- invalid build id
- target interpreter missing or path mismatch
- E01 result missing or not `PASS`
- B01 result missing or not dependency-readiness `BLOCKED`
- offline wheelhouse missing
- package version missing or floating
- package artifact hash missing
- package artifact hash mismatch
- package index access would be required
- dependency solver would need network
- unapproved dependency would be installed
- fallback package source would be used
- source build or editable install would be required
- model download or model loading would occur
- any active index artifact would be created or modified
- any staging build artifact would be created

## Authority Boundary

This contract authorizes dependency approval validation only. It does not
authorize:

- running E01 interpreter bootstrap
- running B01 build execution
- creating staging index artifacts
- promoting artifacts
- running retrieval
- loading models
- executing CUDA
- executing T16 or T17

Those actions require their own controller-selected authority surfaces.
