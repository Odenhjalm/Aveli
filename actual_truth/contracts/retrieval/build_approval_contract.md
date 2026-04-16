# BUILD APPROVAL CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_BUILD_EXECUTION_CONTRACT

This contract defines the only valid approval artifact for controller-governed
Aveli retrieval index build execution.

The approval artifact authorizes one build attempt. It does not define corpus
membership, model semantics, vector semantics, ranking policy, retrieval
behavior, or verification outcome.

## Exact Approval Phrase

The required approval phrase is:

`APPROVE AVELI INDEX REBUILD`

The phrase must match byte-for-byte after LF normalization.

Invalid phrase forms:

- translated phrase
- paraphrased phrase
- lowercased phrase
- abbreviated phrase
- phrase only present in conversation and not in the approval artifact

## Required Artifact Shape

An executable approval artifact must be JSON and must contain these top-level
fields:

- `artifact_type`
- `approval_state`
- `approval_phrase`
- `approval_scope`
- `repo_root`
- `target_path`
- `build_id`
- `manifest_input`
- `model_id`
- `model_revision`
- `tokenizer_id`
- `tokenizer_revision`
- `tokenizer_hashes`
- `device_policy`
- `batch_size`
- `interpreter_path`
- `network_policy`
- `fallback_policy`
- `staging_policy`
- `promotion_policy`

## Required Field Semantics

`artifact_type` must be `build_approval`.

`approval_state` must be `APPROVED_FOR_SINGLE_BUILD`.

`approval_phrase` must be exactly `APPROVE AVELI INDEX REBUILD`.

`approval_scope` must describe one build attempt only and must include:

- `controller_scope`
- `task_id`
- `mode`
- `expires_after_use`

Required values:

- `controller_scope`: `retrieval_index_build_execution`
- `task_id`: `B01`
- `mode`: `build`
- `expires_after_use`: `true`

`repo_root` must be the repo root being approved.

`target_path` must be `.repo_index`.

`build_id` must be a lowercase 64-character SHA-256 hex string.

`manifest_input` must identify the manifest-owned build input and must contain:

- `kind`
- `path`
- `corpus_field`
- `active_authority_before_promotion`

Required values:

- `kind`: `manifest_candidate` or `active_index_manifest`
- `corpus_field`: `corpus.files`
- `active_authority_before_promotion`: `false` for `manifest_candidate`

For an initial build without active `.repo_index/index_manifest.json`,
`manifest_input.kind` must be `manifest_candidate`. A manifest candidate is
build input only and is not query authority.

`model_id` must match the manifest-owned model policy.

`model_revision` must be an exact immutable revision, commit, or snapshot.

`tokenizer_id` must match the manifest-owned tokenizer policy.

`tokenizer_revision` must be an exact immutable revision, commit, or snapshot.

`tokenizer_hashes` must contain canonical SHA-256 hashes for tokenizer files.

`device_policy` must contain:

- `canonical_baseline`
- `allowed_devices`
- `selected_build_device`
- `preferred_local_build_device`
- `cuda_required`
- `device_changes_semantics`
- `cpu_gpu_tolerance`

Required values:

- `canonical_baseline`: `cpu`
- `allowed_devices`: array containing `cpu` and optionally `cuda`
- `selected_build_device`: `cpu` or manifest-permitted `cuda`
- `cuda_required`: `false`
- `device_changes_semantics`: `false`

`batch_size` must be an integer and must match the manifest-owned embedding
batch size.

`interpreter_path` must be:

`.repo_index/.search_venv/Scripts/python.exe`

`network_policy` must contain:

- `downloads_allowed`
- `model_download_allowed`
- `dependency_install_allowed`

Required values:

- `downloads_allowed`: `false`
- `model_download_allowed`: `false`
- `dependency_install_allowed`: `false`

`fallback_policy` must contain:

- `fallbacks_allowed`
- `fallback_interpreter_allowed`
- `fallback_model_allowed`
- `fallback_device_allowed`
- `fallback_corpus_allowed`
- `fallback_retrieval_allowed`

All values must be `false`.

`staging_policy` must contain:

- `staging_required`
- `staging_root`
- `direct_active_write_allowed`

Required values:

- `staging_required`: `true`
- `staging_root`: `.repo_index/_staging/<build_id>`
- `direct_active_write_allowed`: `false`

`promotion_policy` must contain:

- `promotion_requires_staging_verification`
- `active_manifest_state`
- `atomic_promotion_required`

Required values:

- `promotion_requires_staging_verification`: `true`
- `active_manifest_state`: `ACTIVE_VERIFIED`
- `atomic_promotion_required`: `true`

## Validation Rules

Approval validation must occur before any build mutation.

The controller must verify:

- artifact is valid JSON
- required top-level fields are present
- `artifact_type` is `build_approval`
- `approval_state` is `APPROVED_FOR_SINGLE_BUILD`
- approval phrase is exact
- `repo_root` matches the active controller repo root
- `target_path` is `.repo_index`
- `build_id` is lowercase SHA-256 hex
- `manifest_input` is manifest-owned
- corpus field is `corpus.files`
- model and tokenizer fields match manifest-owned policy
- tokenizer hashes are SHA-256 values
- device policy matches manifest-owned policy
- batch size matches manifest-owned policy
- interpreter path is the Windows canonical interpreter
- all network permissions are false
- all fallback permissions are false
- staging is required
- direct active writes are forbidden
- promotion requires staging verification

## Mismatch Stop Conditions

Any mismatch requires STOP before build mutation:

- missing approval artifact
- example-only approval artifact
- invalid JSON
- missing required field
- unknown required field semantics
- approval phrase mismatch
- approval state is not executable
- wrong task id
- wrong mode
- wrong target path
- invalid build id
- manifest input missing or not manifest-owned
- corpus field is not `corpus.files`
- model id mismatch
- model revision mismatch
- tokenizer id mismatch
- tokenizer revision mismatch
- tokenizer hash mismatch
- device policy mismatch
- batch size mismatch
- wrong interpreter path
- network download allowed
- dependency install allowed
- any fallback allowed
- staging not required
- direct active write allowed
- promotion allowed without staging verification

## Example Artifact Rule

Example approval artifacts may exist only as non-executable documentation.

An example artifact must not be accepted for runtime build execution unless all
of these are changed by a future explicit user approval:

- `artifact_type` becomes `build_approval`
- `approval_state` becomes `APPROVED_FOR_SINGLE_BUILD`
- placeholder values are replaced with manifest-matching real values
- the artifact path is selected explicitly by a controller build prompt

## Authority Boundary

This contract authorizes approval validation only. It does not authorize:

- creating `.repo_index`
- creating `.search_venv`
- building staging
- promoting artifacts
- running retrieval
- loading models
- executing CUDA

Those actions require B01 execution after approval validation succeeds.
