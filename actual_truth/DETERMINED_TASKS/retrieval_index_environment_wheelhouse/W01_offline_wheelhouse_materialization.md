# W01 - Offline Wheelhouse Materialization

TASK_ID: W01
TYPE: execution
MODE: wheelhouse_materialization
OS_ROLE: OWNER
CONTROLLER_SCOPE: retrieval_index_environment_wheelhouse
EXECUTION_STATUS: NOT_STARTED

## Purpose

W01 is the only authority surface that may materialize an approved offline
wheelhouse and a full hash-locked dependency closure for D01.

W01 exists because D01 cannot legally prepare the canonical retrieval/indexing
interpreter until an offline package source and dependency lock exist as
repo-visible authority. W01 does not install dependencies into the canonical
interpreter and does not execute B01, T16, or T17.

## Authority Boundary

W01 owns only:

- approved offline wheelhouse materialization
- dependency lock materialization
- package filename and SHA-256 lock evidence
- wheelhouse completeness verification
- repo-visible W01 result materialization

W01 does not own interpreter bootstrap, dependency installation, index build
execution, staging, promotion, retrieval, model loading, CUDA execution, D01
execution, B01 execution, T16 verification, or T17 rollback.

## Required Authority Inputs

W01 must load and obey:

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/offline_wheelhouse_contract.md`
- `actual_truth/contracts/retrieval/offline_wheelhouse_result_contract.md`
- `actual_truth/contracts/retrieval/environment_dependency_contract.md`
- `actual_truth/contracts/retrieval/environment_dependency_result_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_index_environment_dependencies/D01_offline_dependency_preparation.md`
- `actual_truth/DETERMINED_TASKS/retrieval_index_build_execution/B01_execution_result_<build_id>.json`
- one concrete executable wheelhouse approval artifact
- one concrete dependency lock artifact
- one approved local package source if wheelhouse materialization requires a
  source separate from the target wheelhouse

## Required Wheelhouse Approval

W01 requires a concrete executable wheelhouse approval artifact before any
wheelhouse materialization starts.

The approval artifact must:

- contain the exact phrase `APPROVE AVELI OFFLINE WHEELHOUSE MATERIALIZATION`
- match `actual_truth/contracts/retrieval/offline_wheelhouse_contract.md`
- be repo-visible
- be scoped to one wheelhouse materialization attempt
- bind the build id, wheelhouse root, dependency lock artifact, package set,
  exact versions, wheel filenames, wheel hashes, source policy, network policy,
  fallback policy, and forbidden target paths
- require full transitive dependency closure
- declare all network, package-index, fallback, unpinned package, source build,
  editable install, and dependency-install permissions as false

Missing, partial, example-only, ambiguous, expired, or mismatched wheelhouse
approval means STOP before any wheelhouse mutation.

## Required Dependency Lock

W01 requires a dependency lock artifact that declares every package artifact
allowed in the wheelhouse.

For every approved wheel, the lock must declare:

- package name
- exact version
- filename
- lowercase SHA-256
- direct or transitive classification
- required by
- source path
- target wheelhouse relative path

The lock must include a full dependency closure declaration. Partial closures,
placeholder hashes, floating versions, package-name-only locks, and runtime
dependency resolution are forbidden.

## Allowed Output

W01 may materialize only:

- an approved offline wheelhouse directory declared by the executable approval
  artifact
- the concrete dependency lock artifact declared by the executable approval
  artifact
- one repo-visible W01 result artifact under
  `actual_truth/DETERMINED_TASKS/retrieval_index_environment_wheelhouse/`

The wheelhouse root must not be inside `.repo_index`.

## Forbidden Output

W01 must not create, modify, rebuild, repair, or promote:

- `.repo_index/index_manifest.json`
- `.repo_index/chunk_manifest.jsonl`
- `.repo_index/lexical_index/`
- `.repo_index/chroma_db/`
- `.repo_index/_staging/`
- `.repo_index/models/`
- `.repo_index/model_cache/`
- `.repo_index/.search_venv/Lib/site-packages/`
- `.repo_index/.search_venv/Scripts/`
- D01 result files
- B01 result files
- T16 or T17 execution result files

W01 must not install any wheel into any interpreter.

## Canonical Wheelhouse Materialization Flow

W01 must execute this order when a future controlled prompt explicitly selects
it:

1. load complete authority
2. validate executable wheelhouse approval artifact
3. validate dependency lock artifact is concrete and not example-only
4. validate build id linkage to D01 and B01
5. validate wheelhouse root is allowed and outside `.repo_index`
6. validate package set contains the direct D01 packages and full transitive
   closure
7. validate every package has exact version, filename, and lowercase SHA-256
8. validate every source package artifact exists before any copy or move
9. verify source artifact hash before materialization
10. materialize only approved package artifacts into the wheelhouse root
11. verify target wheelhouse contains exactly the approved artifacts
12. verify target artifact hashes match the dependency lock
13. verify no network, package index, fallback, dependency installation, model
    loading, build, staging, promotion, T16, or T17 execution occurred
14. write the W01 result artifact
15. stop

## Required Package Coverage

The dependency lock must include the D01 direct package set at minimum:

- `chromadb`
- `numpy`
- `sentence-transformers`
- `tqdm`

The dependency lock must also include the full transitive closure required for
those packages and for the B01 build surface. Runtime package dependencies such
as `torch`, `transformers`, `scikit-learn`, and `scipy` must be included when
required by the approved direct packages.

## Verification Requirements

W01 must verify:

- approval artifact is executable and not example-only
- approval phrase is exact
- dependency lock is concrete and not example-only
- wheelhouse root exists after materialization
- wheelhouse root is outside `.repo_index`
- every approved wheel exists in the wheelhouse
- every wheel filename matches the lock
- every wheel SHA-256 matches the lock
- every package has exact version
- package closure is declared complete
- no package appears in wheelhouse unless approved
- no package index or network access was required or used
- no fallback package source was used
- no dependency installation occurred
- no `.repo_index` artifact was created or modified
- no model was loaded or downloaded
- B01, D01, T16, and T17 were not invoked

## Failure Conditions

Any condition below requires STOP:

- wheelhouse approval artifact missing
- wheelhouse approval artifact is example-only
- approval phrase mismatch
- dependency lock missing
- dependency lock is example-only
- package set is incomplete
- transitive closure is incomplete or ambiguous
- package version is missing, floating, or mismatched
- package filename is missing
- package SHA-256 is missing, placeholder, uppercase, malformed, or mismatched
- source artifact is missing
- source artifact requires network acquisition
- package index access would be required
- fallback package source would be used
- source build or editable install would be required
- wheelhouse root is inside `.repo_index`
- unapproved artifact is present in the wheelhouse
- dependency installation occurs
- any `.repo_index` artifact is created or modified
- model loading or model download occurs
- D01, B01, T16, or T17 is invoked

## Output Contract

W01 must produce a wheelhouse result conforming to:

`actual_truth/contracts/retrieval/offline_wheelhouse_result_contract.md`

The result artifact must record the wheelhouse approval artifact used,
dependency lock artifact used, wheelhouse root, package source, package
filenames, package hashes, closure verification, forbidden side-effect checks,
and any STOP/BLOCKED reason.

## Next Transition

After W01 completes successfully, the next allowed action is to create a real
executable D01 dependency approval artifact that references the W01-approved
wheelhouse and dependency lock.

D01 remains dependency-installation authority only. B01 remains build authority.
T16 remains verification-only.
