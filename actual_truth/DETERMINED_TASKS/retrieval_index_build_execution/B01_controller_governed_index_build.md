# B01 - Controller-Governed Index Build

TASK_ID: B01
TYPE: execution
MODE: build
OS_ROLE: OWNER
CONTROLLER_SCOPE: retrieval_index_build_execution
EXECUTION_STATUS: NOT_STARTED

## Purpose

B01 is the only authority surface that may perform a future Aveli retrieval
index build before T16 is re-run as a verification gate.

B01 owns build execution only. It does not own retrieval semantics, query
behavior, model policy, corpus authority, chunking rules, hashing rules,
lexical semantics, vector semantics, MCP behavior, or final verification.

## Dependency Boundary

B01 depends on the retrieval indexing controller design layer being complete
through T15 and on the rebuild approval gate from T14.

Required prior controller state:

- T01 through T15 must be repo-visible `PASS`.
- T16 may be `BLOCKED`.
- T17 must remain `NOT_STARTED`.
- no task after T16 may be executed by B01.

B01 is outside the T01 through T17 design/verification DAG. It is a separate
controller-governed build execution layer that produces runtime artifacts for a
later T16 verification-only rerun.

## Required Authority Inputs

B01 must load and obey:

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `actual_truth/contracts/retrieval/build_approval_contract.md`
- `actual_truth/contracts/retrieval/build_execution_result_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T07_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T08_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T09_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T10_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T11_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T12_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T13_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T14_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T15_execution_result.md`
- one concrete build approval artifact matching `build_approval_contract.md`
- one manifest-owned corpus input for the build attempt

## Required Build Approval

B01 requires a concrete approval artifact before any build action starts.

The approval artifact must:

- contain the exact phrase `APPROVE AVELI INDEX REBUILD`
- match `actual_truth/contracts/retrieval/build_approval_contract.md`
- be repo-visible
- be scoped to one build attempt
- bind repo root, target path, build id, model lock, tokenizer lock, device
  policy, batch size, interpreter path, and network policy
- declare `target_path` as `.repo_index`
- declare `interpreter_path` as `.repo_index/.search_venv/Scripts/python.exe`
- declare `network_policy.downloads_allowed` as `false`
- declare `fallbacks_allowed` as `false`

Missing, partial, example-only, expired, ambiguous, or mismatched approval means
STOP before any filesystem mutation.

## Required Manifest-Owned Corpus Input

B01 may not derive corpus membership from filesystem traversal, Chroma
metadata, lexical metadata, cache, MCP output, `search_manifest.txt`, or
`searchable_files.txt`.

The build must consume a manifest-owned corpus input only.

For an initial build where active `.repo_index/index_manifest.json` does not
yet exist, the input must be a repo-visible build manifest candidate declared
by the approval artifact. The candidate is not active retrieval authority. It
is promoted to active `.repo_index/index_manifest.json` only after staging
verification passes and promotion succeeds.

The manifest-owned corpus input must contain:

- `contract_version`
- `corpus.files`
- `corpus_manifest_hash`
- chunking policy
- hashing policy
- model policy
- tokenizer policy
- embedding policy
- lexical policy
- vector policy
- retrieval policy
- Windows runtime policy
- artifact policy

## Windows Runtime Requirement

B01 requires the canonical Windows retrieval interpreter:

`.repo_index/.search_venv/Scripts/python.exe`

The interpreter path is a runtime environment prerequisite, not an active index
artifact and not corpus authority.

If the interpreter does not exist, B01 may only create or validate it when the
approval artifact and this task explicitly authorize environment preparation.
Environment preparation must not create active index artifacts and must not
install or download dependencies unless a later approved environment contract
explicitly allows it.

Forbidden interpreter behavior:

- bare `python`
- `python3`
- `.venv`
- `.repo_index/.search_venv/bin/python`
- `/bin/*`
- bash, sh, zsh, or shell activation
- dynamic interpreter discovery

## Staging-Only Write Rule

All build writes must target:

`.repo_index/_staging/<build_id>/`

Required staging artifact paths:

- `.repo_index/_staging/<build_id>/index_manifest.json`
- `.repo_index/_staging/<build_id>/chunk_manifest.jsonl`
- `.repo_index/_staging/<build_id>/lexical_index/`
- `.repo_index/_staging/<build_id>/chroma_db/`
- `.repo_index/_staging/<build_id>/build_execution_result.json`
- `.repo_index/_staging/<build_id>/staging_verification_result.json`

Direct active writes are forbidden until verified promotion.

Forbidden active writes before promotion:

- `.repo_index/index_manifest.json`
- `.repo_index/chunk_manifest.jsonl`
- `.repo_index/lexical_index/`
- `.repo_index/chroma_db/`

## Canonical Build Flow

B01 must execute this order when a future controlled build prompt explicitly
selects it:

1. load complete authority
2. validate T01 through T15 are `PASS`
3. validate T16 is not being used as build authority
4. validate T17 is not executing
5. validate build approval artifact
6. validate manifest-owned corpus input
7. validate Windows canonical interpreter
8. compute or verify deterministic `build_id`
9. create staging root `.repo_index/_staging/<build_id>/`
10. write staging `index_manifest.json` with staging status
11. resolve corpus from manifest-owned input only
12. normalize corpus under T04
13. generate chunks under T05
14. compute `content_hash`, `doc_id`, and chunk manifest hash under T06
15. write staging `chunk_manifest.jsonl`
16. build staging lexical index under T09
17. build staging Chroma index under T10
18. compute artifact hashes
19. write staging build execution result
20. verify full staging integrity
21. promote only after staging verification passes
22. write active manifest only as part of promotion
23. write promotion result
24. stop

## Verification Before Promotion

Promotion is forbidden unless all checks pass:

- approval artifact valid
- manifest schema valid
- manifest-owned corpus hash valid
- chunk manifest hash valid
- no duplicate `doc_id`
- lexical `doc_id` set equals chunk manifest `doc_id` set
- vector `doc_id` set equals chunk manifest `doc_id` set
- vector metadata matches chunk manifest
- model and tokenizer locks match manifest
- embedding dimension matches manifest
- device policy matches approval and manifest
- batch size matches approval and manifest
- artifact hashes match staged bytes
- canonical ordering is preserved
- no forbidden active write occurred
- no fallback behavior occurred

## Promotion Boundary

Promotion may replace active `.repo_index` only after staging verification
passes.

Promotion must be atomic from the perspective of query mode:

- previous active index remains untouched until promotion
- incomplete staging is never queryable
- active `index_manifest.json` is written only with `ACTIVE_VERIFIED`
- active artifacts must be internally parity-checked before query use

If promotion cannot be made atomic, B01 must STOP and leave active index
unchanged.

## Forbidden Behavior

B01 must not:

- execute without approval
- execute from query mode
- execute T16 or T17
- use T16 as build authority
- build from filesystem traversal
- use legacy corpus files as authority
- write active `.repo_index` before promotion
- mix staging and active artifacts
- auto-download models
- install dependencies ad hoc
- switch devices implicitly
- fallback to another interpreter
- fallback to another model
- fallback to another index
- repair missing artifacts silently
- return query results

## Failure Conditions

Any condition below requires STOP:

- approval artifact missing
- approval artifact is example-only
- approval phrase mismatch
- approval field missing
- approval value conflicts with manifest-owned input
- selected mode is not `build`
- build id is missing or invalid
- canonical interpreter missing and environment preparation is not explicitly
  authorized
- manifest-owned corpus input missing or invalid
- corpus file list is empty, unsorted, duplicated, absolute, or contains `..`
- model or tokenizer lock mismatch
- model would need network download
- dependency installation would be required without explicit environment
  authority
- device policy mismatch
- batch size mismatch
- any write targets active `.repo_index` before promotion
- staging verification fails
- promotion verification fails
- active artifact parity fails after promotion

## Output Contract

B01 must produce a build execution result conforming to:

`actual_truth/contracts/retrieval/build_execution_result_contract.md`

B01 must not update T16. T16 may be re-run only after B01 has produced a
successful build execution result and active artifacts exist.

## Next Transition

After B01 completes successfully, the next allowed controller action is a
separate T16 verification-only rerun.

T17 remains blocked until T16 reaches `PASS`.
