# E01 - Canonical Windows Interpreter Bootstrap

TASK_ID: E01
TYPE: execution
MODE: environment_bootstrap
OS_ROLE: OWNER
CONTROLLER_SCOPE: retrieval_index_environment_bootstrap
EXECUTION_STATUS: NOT_STARTED

## Purpose

E01 is the only authority surface that may materialize the canonical Windows
retrieval/indexing interpreter required by B01:

`.repo_index/.search_venv/Scripts/python.exe`

E01 owns environment bootstrap only. It does not own index build execution,
staging artifact generation, promotion, retrieval behavior, model semantics,
corpus authority, chunking rules, hashing rules, evidence generation, MCP
behavior, or T16 verification.

## Authority Boundary

E01 exists because B01 requires the canonical interpreter but B01 must not
guess how that interpreter is created. The previous B01 environment preparation
result is `BLOCKED` until an explicit bootstrap authority and executable
bootstrap approval artifact exist.

E01 is outside the T01 through T17 retrieval indexing controller DAG and outside
the B01 build execution task. It is a separate prerequisite layer for B01 when
the canonical interpreter is missing.

## Required Authority Inputs

E01 must load and obey:

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/environment_bootstrap_contract.md`
- `actual_truth/contracts/retrieval/environment_bootstrap_result_contract.md`
- `actual_truth/contracts/retrieval/build_approval_contract.md`
- `actual_truth/contracts/retrieval/build_execution_result_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_index_build_execution/B01_controller_governed_index_build.md`
- one concrete executable environment bootstrap approval artifact
- one concrete B01 build approval artifact, if bootstrap is being prepared for a
  specific build id
- one manifest-owned corpus candidate, if the B01 approval references it

## Required Bootstrap Approval

E01 requires a concrete environment bootstrap approval artifact before any
environment mutation starts.

The approval artifact must:

- contain the exact phrase `APPROVE AVELI ENVIRONMENT BOOTSTRAP`
- match `actual_truth/contracts/retrieval/environment_bootstrap_contract.md`
- be repo-visible
- be scoped to one bootstrap attempt
- bind the bootstrap source interpreter, target interpreter path, dependency
  policy, network policy, fallback policy, and forbidden target paths
- declare `target_interpreter_path` as
  `.repo_index/.search_venv/Scripts/python.exe`
- declare `network_policy.downloads_allowed` as `false`
- declare `fallback_policy.fallbacks_allowed` as `false`
- declare whether dependencies are already present or may be installed only
  from an approved offline package source

Missing, partial, example-only, expired, ambiguous, or mismatched bootstrap
approval means STOP before any environment mutation.

## Bootstrap Source Interpreter Rule

The target interpreter is the only canonical retrieval/indexing interpreter.

A bootstrap source interpreter is not canonical runtime authority. It may be
used only to create or verify the target interpreter when explicitly named by
the executable bootstrap approval artifact.

Allowed bootstrap source forms are defined by
`environment_bootstrap_contract.md`.

At minimum, E01 must reject:

- bare `python` unless the approval first binds an exact Windows executable
  path and hash as the bootstrap source
- `.venv` as canonical runtime
- `.repo_index/.search_venv/bin/python`
- `/bin/*`
- bash, sh, zsh, or shell activation
- dynamic interpreter discovery
- fallback interpreter probing

## Allowed Output

E01 may materialize only:

- `.repo_index/.search_venv/`
- `.repo_index/.search_venv/Scripts/python.exe`
- support files required by the Windows virtual environment under
  `.repo_index/.search_venv/`
- one repo-visible E01 bootstrap result artifact under
  `actual_truth/DETERMINED_TASKS/retrieval_index_environment_bootstrap/`

## Forbidden Output

E01 must not create, modify, rebuild, repair, or promote:

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

## Canonical Bootstrap Flow

E01 must execute this order when a future controlled bootstrap prompt
explicitly selects it:

1. load complete authority
2. validate the executable bootstrap approval artifact
3. validate any referenced B01 build approval artifact
4. validate any referenced manifest-owned corpus candidate without using it as
   execution input
5. validate that active index artifacts are absent or untouched
6. validate that no staging build is in progress
7. validate the approved bootstrap source interpreter exactly
8. create or reuse `.repo_index/.search_venv/` only as permitted by approval
9. materialize `.repo_index/.search_venv/Scripts/python.exe`
10. install dependencies only if the approval permits an offline, hash-pinned
    package source
11. verify the target interpreter path and dependency state
12. verify that no index artifacts were created
13. write the E01 bootstrap result artifact
14. stop

## Verification Requirements

E01 must verify:

- approval artifact is executable and not example-only
- approval phrase is exact
- target path is exactly `.repo_index/.search_venv/Scripts/python.exe`
- bootstrap source interpreter is explicitly approved and hash/version checked
- no fallback interpreter was used
- no network access was required or used
- dependencies either were not installed or came only from approved offline
  package sources with matching hashes
- target interpreter exists and reports the expected version
- target interpreter resolves inside `.repo_index/.search_venv/`
- no active index artifact was created or modified
- no staging build artifact was created
- no model was loaded or downloaded

## Failure Conditions

Any condition below requires STOP:

- bootstrap approval artifact missing
- bootstrap approval artifact is example-only
- approval phrase mismatch
- approval field missing
- approval value conflicts with this task or the bootstrap contract
- bootstrap source interpreter missing, unapproved, ambiguous, or hash-mismatched
- bootstrap attempts to use bare `python`, `python3`, `.venv`, Linux paths, bash,
  shell activation, or fallback discovery outside approved bootstrap rules
- target interpreter path differs from
  `.repo_index/.search_venv/Scripts/python.exe`
- network access would be required
- dependency source is not offline and hash-pinned
- dependency verification fails
- any active index artifact is created or modified
- any staging build artifact is created
- model loading or model download occurs
- B01 build execution is invoked
- T16 or T17 is invoked

## Output Contract

E01 must produce a bootstrap result conforming to:

`actual_truth/contracts/retrieval/environment_bootstrap_result_contract.md`

The result artifact must record whether the environment was created or reused,
the approval artifact used, interpreter verification, dependency verification,
forbidden side-effect checks, and any STOP/BLOCKED reason.

## Next Transition

After E01 completes successfully, the next allowed action is controlled B01
build execution under a valid B01 build approval artifact.

T16 remains verification-only and must not create `.search_venv`, staging, or
active index artifacts.

T17 remains blocked until T16 reaches `PASS`.
