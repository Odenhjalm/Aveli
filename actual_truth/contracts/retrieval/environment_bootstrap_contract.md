# ENVIRONMENT BOOTSTRAP CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_ENVIRONMENT_EXECUTION_CONTRACT

This contract defines the only valid approval and validation rules for
materializing the canonical Windows retrieval/indexing interpreter:

`.repo_index/.search_venv/Scripts/python.exe`

This contract authorizes environment bootstrap only. It does not authorize
index build execution, staging artifact generation, promotion, retrieval,
model loading, CUDA execution, or T16 verification.

## Exact Approval Phrase

The required approval phrase is:

`APPROVE AVELI ENVIRONMENT BOOTSTRAP`

The phrase must match byte-for-byte after LF normalization.

Invalid phrase forms:

- translated phrase
- paraphrased phrase
- lowercased phrase
- abbreviated phrase
- phrase only present in conversation and not in the approval artifact

## Required Artifact Shape

An executable environment bootstrap approval artifact must be JSON and must
contain these top-level fields:

- `artifact_type`
- `approval_state`
- `approval_phrase`
- `approval_scope`
- `repo_root`
- `build_id`
- `bootstrap_source_interpreter`
- `target_interpreter_path`
- `dependency_policy`
- `network_policy`
- `fallback_policy`
- `forbidden_targets`
- `verification_policy`

## Required Field Semantics

`artifact_type` must be `environment_bootstrap_approval`.

`approval_state` must be `APPROVED_FOR_SINGLE_BOOTSTRAP`.

`approval_phrase` must be exactly
`APPROVE AVELI ENVIRONMENT BOOTSTRAP`.

`approval_scope` must describe one bootstrap attempt only and must include:

- `controller_scope`
- `task_id`
- `mode`
- `expires_after_use`

Required values:

- `controller_scope`: `retrieval_index_environment_bootstrap`
- `task_id`: `E01`
- `mode`: `environment_bootstrap`
- `expires_after_use`: `true`

`repo_root` must be the repo root being approved.

`build_id` must be a lowercase 64-character SHA-256 hex string when bootstrap
is bound to a B01 build attempt. If bootstrap is not build-bound, the artifact
must set `build_id` to `null` and must explain the scope in
`approval_scope.scope_note`.

`target_interpreter_path` must be exactly:

`.repo_index/.search_venv/Scripts/python.exe`

## Bootstrap Source Interpreter Policy

The bootstrap source interpreter is bootstrap-only. It must never become
canonical retrieval/indexing runtime authority.

Allowed source type:

- `windows_absolute_python_executable`

Required fields for `windows_absolute_python_executable`:

- `source_type`
- `path`
- `version`
- `sha256`
- `bootstrap_only`
- `canonical_runtime`

Required values:

- `source_type`: `windows_absolute_python_executable`
- `path`: absolute Windows path to `python.exe`
- `sha256`: lowercase SHA-256 hash of the source executable
- `bootstrap_only`: `true`
- `canonical_runtime`: `false`

The source path must:

- be absolute
- end with `python.exe`
- not point inside `.venv`
- not point inside `.repo_index/.search_venv`
- not contain `/bin/`
- not require shell activation

## System Python And Py Launcher Rule

System Python may be used only as a bootstrap-only source when the executable
bootstrap approval artifact names the exact absolute Windows `python.exe` path,
expected version, and expected SHA-256 hash.

The `py` launcher is not an interpreter source. It may not be used to create the
canonical environment directly. If a future operator wants to use `py` to
discover a Python installation, that discovery must happen before E01 and must
be materialized into the approval artifact as an exact
`windows_absolute_python_executable`. E01 must then invoke only that resolved
absolute interpreter path.

Bare `python`, `python3`, PATH lookup, registry probing, shell activation,
`.venv`, Linux `/bin` paths, and fallback discovery are forbidden.

## Dependency Policy

`dependency_policy` must contain:

- `dependency_install_allowed`
- `dependency_source`
- `offline_wheelhouse_path`
- `requirements_path`
- `package_hashes`
- `allow_unpinned_packages`

Allowed dependency modes:

- no dependency installation
- offline, hash-pinned dependency installation from an approved local package
  source

Required values when no dependency installation is allowed:

- `dependency_install_allowed`: `false`
- `dependency_source`: `none`
- `offline_wheelhouse_path`: `null`
- `requirements_path`: `null`
- `package_hashes`: {}
- `allow_unpinned_packages`: `false`

Required values when offline dependency installation is allowed:

- `dependency_install_allowed`: `true`
- `dependency_source`: `offline_wheelhouse`
- `offline_wheelhouse_path`: repo-visible or absolute local path
- `requirements_path`: repo-visible requirements file
- `package_hashes`: object mapping each package artifact to lowercase SHA-256
- `allow_unpinned_packages`: `false`

Dependency installation must not contact PyPI, Hugging Face, GitHub, package
indexes, or any network endpoint.

## Network Policy

`network_policy` must contain:

- `mode`
- `downloads_allowed`
- `dependency_download_allowed`
- `model_download_allowed`
- `telemetry_allowed`

Required values:

- `mode`: `offline`
- `downloads_allowed`: `false`
- `dependency_download_allowed`: `false`
- `model_download_allowed`: `false`
- `telemetry_allowed`: `false`

## Fallback Policy

`fallback_policy` must contain:

- `fallbacks_allowed`
- `fallback_interpreter_allowed`
- `fallback_dependency_source_allowed`
- `fallback_network_allowed`
- `fallback_canonical_runtime_allowed`

All values must be `false`.

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

The only allowed `.repo_index` mutation during E01 is materialization of the
Windows virtual environment rooted at:

`.repo_index/.search_venv/`

## Verification Policy

`verification_policy` must require:

- target interpreter path exists
- target interpreter path equals `.repo_index/.search_venv/Scripts/python.exe`
- target interpreter is executable
- target interpreter reports expected Python version
- target interpreter resolves inside `.repo_index/.search_venv/`
- dependency set matches approval policy
- no network access was required or used
- no fallback interpreter was used
- no active index artifact was created or modified
- no staging build artifact was created
- no model was loaded or downloaded

## Validation Rules

Bootstrap validation must occur before any environment mutation.

The controller must verify:

- artifact is valid JSON
- required top-level fields are present
- `artifact_type` is `environment_bootstrap_approval`
- `approval_state` is `APPROVED_FOR_SINGLE_BOOTSTRAP`
- approval phrase is exact
- `repo_root` matches the active controller repo root
- `build_id` is valid or explicitly null for non-build-bound bootstrap
- bootstrap source interpreter is an exact approved Windows executable
- bootstrap source version and SHA-256 match approval
- target path is exactly `.repo_index/.search_venv/Scripts/python.exe`
- dependency policy is either no-install or offline hash-pinned
- all network permissions are false
- all fallback permissions are false
- forbidden target list covers active and staging index artifacts

## Mismatch Stop Conditions

Any mismatch requires STOP before environment mutation:

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
- bootstrap source missing
- bootstrap source path is relative or ambiguous
- bootstrap source version mismatch
- bootstrap source SHA-256 mismatch
- bootstrap source is `.venv`, `.repo_index/.search_venv`, `/bin`, bare
  `python`, `python3`, bash, sh, zsh, or shell activation
- target path mismatch
- dependency install requested without offline hash-pinned package source
- package hash missing or mismatched
- network download allowed or required
- any fallback allowed or used
- active index artifact creation or mutation is possible
- staging build artifact creation or mutation is possible

## Authority Boundary

This contract authorizes bootstrap approval validation only. It does not
authorize:

- running B01 build execution
- creating staging index artifacts
- promoting artifacts
- running retrieval
- loading models
- executing CUDA
- executing T16 or T17

Those actions require their own controller-selected authority surfaces.
