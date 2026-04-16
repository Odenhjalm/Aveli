# D01 - Offline Dependency Preparation

TASK_ID: D01
TYPE: execution
MODE: environment_dependencies
OS_ROLE: OWNER
CONTROLLER_SCOPE: retrieval_index_environment_dependencies
EXECUTION_STATUS: NOT_STARTED

## Purpose

D01 is the only authority surface that may prepare the canonical
retrieval/indexing interpreter with the exact offline build dependencies
required by B01:

`.repo_index/.search_venv/Scripts/python.exe`

D01 owns dependency preparation only. It does not own interpreter bootstrap,
index build execution, staging artifact generation, promotion, retrieval
behavior, model loading, CUDA execution, corpus authority, vector semantics,
MCP behavior, T16 verification, or T17 rollback.

## Authority Boundary

D01 exists because B01 is currently `BLOCKED` before staging: the canonical
interpreter exists from E01, but it lacks required build dependencies and the
current B01 approval forbids dependency install, download, network, and
fallback.

D01 may only make the already-bootstrapped canonical interpreter dependency
ready under an explicit offline dependency approval artifact. D01 must not
create or modify active index artifacts and must not create staging build
artifacts.

## Required Authority Inputs

D01 must load and obey:

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/environment_dependency_contract.md`
- `actual_truth/contracts/retrieval/environment_dependency_result_contract.md`
- `actual_truth/contracts/retrieval/environment_bootstrap_contract.md`
- `actual_truth/contracts/retrieval/environment_bootstrap_result_contract.md`
- `actual_truth/contracts/retrieval/build_approval_contract.md`
- `actual_truth/contracts/retrieval/build_execution_result_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_index_environment_bootstrap/E01_environment_bootstrap_result_<build_id>.json`
- `actual_truth/DETERMINED_TASKS/retrieval_index_build_execution/B01_execution_result_<build_id>.json`
- one concrete executable environment dependency approval artifact
- one concrete B01 build approval artifact
- one manifest-owned corpus candidate if the B01 approval references one

## Required Dependency Approval

D01 requires a concrete environment dependency approval artifact before any
dependency mutation starts.

The approval artifact must:

- contain the exact phrase `APPROVE AVELI OFFLINE DEPENDENCY PREPARATION`
- match `actual_truth/contracts/retrieval/environment_dependency_contract.md`
- be repo-visible
- be scoped to one dependency preparation attempt
- bind the build id, canonical interpreter path, package set, exact package
  versions, offline package source, package artifact hashes, network policy,
  fallback policy, and forbidden target paths
- declare `target_interpreter_path` as
  `.repo_index/.search_venv/Scripts/python.exe`
- declare package source as an approved offline wheelhouse or equivalent
  hash-pinned local package store
- declare all network, download, fallback, and unpinned install permissions as
  false

Missing, partial, example-only, ambiguous, expired, or mismatched dependency
approval means STOP before any dependency mutation.

## Required Package Set

D01 must prepare the direct B01 build imports at minimum:

- `chromadb`
- `numpy`
- `sentence-transformers`
- `tqdm`

D01 must also install or verify the full transitive closure required for those
packages and for the locked `tools/index/requirements.txt` retrieval build
surface, including model runtime dependencies such as `torch`, `transformers`,
`scikit-learn`, and `scipy` when required by the approved package set.

The executable dependency approval artifact must list every package artifact
that may be installed and must provide a SHA-256 hash for each wheel or source
distribution. D01 must not resolve dependencies from package indexes at runtime.

## Allowed Output

D01 may materialize only dependency files inside the existing canonical
interpreter environment:

- `.repo_index/.search_venv/Lib/site-packages/**`
- `.repo_index/.search_venv/Scripts/pip.exe` only if an approved offline
  dependency preparation flow explicitly requires pip from the canonical venv
- package metadata files under `.repo_index/.search_venv/Lib/site-packages/**`
- one repo-visible D01 dependency result artifact under
  `actual_truth/DETERMINED_TASKS/retrieval_index_environment_dependencies/`

## Forbidden Output

D01 must not create, modify, rebuild, repair, or promote:

- `.repo_index/index_manifest.json`
- `.repo_index/chunk_manifest.jsonl`
- `.repo_index/lexical_index/`
- `.repo_index/chroma_db/`
- `.repo_index/_staging/<build_id>/index_manifest.json`
- `.repo_index/_staging/<build_id>/chunk_manifest.jsonl`
- `.repo_index/_staging/<build_id>/lexical_index/`
- `.repo_index/_staging/<build_id>/chroma_db/`
- model weights
- query caches
- query memory
- B01 build result files
- T16 or T17 execution result files

## Canonical Dependency Preparation Flow

D01 must execute this order when a future controlled dependency prompt
explicitly selects it:

1. load complete authority
2. validate E01 result is `PASS`
3. validate B01 result is `BLOCKED` specifically on missing dependencies
4. validate executable dependency approval artifact
5. validate B01 build approval artifact and manifest candidate linkage
6. validate canonical interpreter exists and is invokable
7. validate offline package source exists before dependency mutation
8. validate every approved package artifact hash before installation
9. install only approved package artifacts into the canonical interpreter
10. verify import readiness for the direct B01 build imports
11. verify installed package versions and package metadata match approval
12. verify no network, download, fallback, model loading, build, staging, or
    promotion occurred
13. write the D01 dependency result artifact
14. stop

## Verification Requirements

D01 must verify:

- approval artifact is executable and not example-only
- approval phrase is exact
- target interpreter path is exactly `.repo_index/.search_venv/Scripts/python.exe`
- E01 result is `PASS`
- B01 is blocked on dependency readiness, not on unrelated drift
- package source is offline and hash-pinned
- all package artifact hashes match approval before install
- all required package versions match approval after install
- direct build imports succeed for `chromadb`, `numpy`, `sentence_transformers`,
  and `tqdm`
- no unapproved packages were installed
- no network access was required or used
- no fallback package source was used
- no active index artifact was created or modified
- no staging build artifact was created
- no model was loaded or downloaded

## Failure Conditions

Any condition below requires STOP:

- dependency approval artifact missing
- dependency approval artifact is example-only
- approval phrase mismatch
- approval field missing
- target interpreter missing or path mismatch
- E01 result missing or not `PASS`
- B01 blocker is not dependency readiness
- offline package source missing
- package version missing or not fixed
- package artifact hash missing
- package artifact hash mismatch
- dependency resolution requires network
- dependency installation would use package index, fallback source, or unpinned
  package
- import readiness fails after preparation
- any active index artifact is created or modified
- any staging build artifact is created
- model loading or model download occurs
- B01, T16, or T17 is invoked

## Output Contract

D01 must produce a dependency result conforming to:

`actual_truth/contracts/retrieval/environment_dependency_result_contract.md`

The result artifact must record the approval artifact used, E01 result used,
B01 blocked result used, package source, package hashes, installed versions,
import readiness, forbidden side-effect checks, and any STOP/BLOCKED reason.

## Next Transition

After D01 completes successfully, the next allowed action is a controlled B01
build execution rerun.

T16 remains verification-only and must not install dependencies, build staging,
promote artifacts, load models, or repair D01 output.

T17 remains blocked until T16 reaches `PASS`.
