# T07 Execution Result - Artifact Structure And Write Order

TASK_ID: T07
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T07_define_artifact_structure_and_write_order.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T05_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T06_execution_result.md`
- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `tools/index/ENVIRONMENT_SETUP.sh`
- `tools/index/analyze_results.py`
- `tools/index/ast_extract.py`
- `tools/index/build_repo_index.sh`
- `tools/index/build_vector_index.py`
- `tools/index/codex_query.py`
- `tools/index/device_utils.py`
- `tools/index/requirements.txt`
- `tools/index/run_codex.py`
- `tools/index/run_codex_auto.py`
- `tools/index/search_code.py`
- `tools/index/semantic_search.sh`
- `tools/index/test_build_vector_index_manifest_bootstrap.py`
- `tools/index/validate_codex.py`
- `tools/mcp/semantic_search_server.py`

## Controller State Before T07

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `PASS`.
- `T05` was repo-visible `PASS`.
- `T06` was repo-visible `PASS`.
- `T07` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T07` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T07 defines the authoritative artifact set, staging model, write order,
integrity gates, active promotion boundary, and failure behavior for future
controller-governed retrieval/index builds. It does not create `.repo_index`,
does not stage artifacts, does not write an index, does not download models,
does not execute CUDA, and does not execute retrieval.

## T07 Execution Plan

T07 execution was limited to:

1. no-code audit of controller state and authority inputs.
2. verification that T02 and T06 were repo-visible `PASS`.
3. verification that T04 normalization, T05 chunking, and T06 identity/hashing
   are locked inputs.
4. comparison of current contracts and tools against the T07 artifact scope.
5. materialization of this T07 execution result.
6. controller status update for T07 only.

No T08 model policy, T09 lexical contract, T10 vector contract, T11 retrieval
contract, or later gate was executed.

## Artifact Authority Decision

Artifact structure and lifecycle are governed only by
`.repo_index/index_manifest.json` field `artifact_policy`, as defined by T02
and refined by T07.

T07 owns:

- active artifact path set.
- staging artifact path set.
- safe write order.
- integrity checks before promotion.
- promotion eligibility.
- active/staging isolation.
- artifact hash binding boundaries.
- failure behavior for partial builds and promotion failures.

T07 does not own:

- corpus membership.
- T04 normalization.
- T05 chunk boundaries.
- T06 identity/hash formulas.
- model or tokenizer policy.
- lexical index internals.
- vector index internals.
- retrieval ranking.
- rebuild approval wording.

## Active Artifact Structure Spec

The only active authoritative artifact paths are:

```text
.repo_index/index_manifest.json
.repo_index/chunk_manifest.jsonl
.repo_index/lexical_index/
.repo_index/chroma_db/
```

Authority boundaries:

- `.repo_index/index_manifest.json` is the only configuration, corpus,
  version, policy, and artifact-binding authority.
- `.repo_index/chunk_manifest.jsonl` is a derived chunk record artifact bound
  to `index_manifest.json`.
- `.repo_index/lexical_index/` is a derived lexical retrieval artifact bound to
  the active manifest and chunk manifest.
- `.repo_index/chroma_db/` is a derived vector artifact bound to the active
  manifest and chunk manifest.

Forbidden active authority paths:

- `.repo_index/search_manifest.txt`
- `.repo_index/searchable_files.txt`
- `.repo_index/files.txt`
- `.repo_index/tags`
- `.repo_index/tree.txt`
- `.repo_index/stats.txt`
- `.repo_index/query_cache.json`
- `.repo_index/query_memory.json`
- `.repo_index/search_code.sock`
- any MCP wrapper output
- any Chroma metadata field not verified against the active manifest

Legacy exports, diagnostics, and caches may exist only as explicitly
non-authoritative artifacts. Their deletion must not change canonical
retrieval output, corpus membership, artifact health, ranking, or verification.

## Non-Authoritative Artifact Boundaries

Allowed non-authoritative paths, only if a future task or manifest policy
explicitly permits them:

```text
.repo_index/_staging/
.repo_index/_diagnostics/
.repo_index/_exports/
.repo_index/_locks/
.repo_index/_rollback/
```

Rules:

- non-authoritative paths must begin with `_`.
- query mode must ignore non-authoritative paths except for fail-closed
  promotion-lock checks defined by a later implementation task.
- non-authoritative paths must never be required for a healthy active index.
- non-authoritative paths must never define corpus membership.
- non-authoritative paths must never supply missing manifest fields.
- non-authoritative paths must never override active artifact hashes.

## Staging Model

All future builds must write to:

```text
.repo_index/_staging/<build_id>/
```

The staging tree must mirror the active artifact layout:

```text
.repo_index/_staging/<build_id>/index_manifest.json
.repo_index/_staging/<build_id>/chunk_manifest.jsonl
.repo_index/_staging/<build_id>/lexical_index/
.repo_index/_staging/<build_id>/chroma_db/
```

`build_id` rules:

- `build_id` must be deterministic.
- `build_id` must be lowercase SHA-256 hex.
- `build_id` must be derived from manifest-owned build inputs, including
  manifest identity, contract version, corpus manifest hash, selected device
  policy, batch policy, target path, and controller version.
- `build_id` must not include wall-clock time, random UUIDs, process IDs,
  filesystem metadata, or traversal order.
- if the deterministic staging path already exists before build start, STOP
  unless an explicit cleanup task has invalidated and removed stale staging.

Staging manifest rules:

- staging `index_manifest.json` must have `manifest_state` =
  `STAGING_INCOMPLETE` until every staging artifact is complete and verified.
- staging manifests are not queryable.
- query mode must reject any manifest whose `manifest_state` is not
  `ACTIVE_VERIFIED`.
- missing artifact hashes in staging are pending state, not active authority.

## Canonical Write Order

Future build mode must use this write order:

1. run build-mode preflight and rebuild approval checks.
2. create deterministic staging root.
3. write staging `index_manifest.json` with `manifest_state` =
   `STAGING_INCOMPLETE`.
4. resolve corpus from manifest `corpus.files` only.
5. normalize corpus using T04.
6. generate chunks using T05.
7. compute `content_hash`, `doc_id`, and `chunk_manifest_hash` using T06.
8. write staging `chunk_manifest.jsonl`.
9. build staging `lexical_index/`.
10. build staging `chroma_db/`.
11. compute required artifact hashes.
12. write completed staging manifest with all artifact bindings still marked
    non-active.
13. verify full staging integrity.
14. promote only after verification passes.
15. write active `index_manifest.json` with `manifest_state` =
    `ACTIVE_VERIFIED` only as the activation boundary.

Direct active writes before step 14 are forbidden.

## Required Active Manifest Bindings

An active `index_manifest.json` must bind:

- `manifest_state = ACTIVE_VERIFIED`
- `contract_version`
- `manifest_id`
- `controller_version`
- `corpus_manifest_hash`
- `chunk_manifest_hash`
- `artifact_policy.index_root`
- `artifact_policy.active_manifest`
- `artifact_policy.chunk_manifest`
- `artifact_policy.lexical_index`
- `artifact_policy.chroma_db`
- `artifact_hashes.chunk_manifest_jsonl`
- `artifact_hashes.lexical_index`
- `artifact_hashes.chroma_db`
- `verification_policy.required_checks`
- `windows_runtime_policy.interpreter`
- `deprecated_surfaces`

Derived artifacts may repeat these values only as verification metadata. They
must never become authority for missing or conflicting manifest values.

## Verification Before Promotion

Before promotion, the controller must verify:

- staging manifest schema is valid.
- staging manifest state is not queryable.
- corpus membership matches manifest `corpus.files`.
- `corpus_manifest_hash` matches T04 canonical corpus serialization.
- `chunk_manifest_hash` matches T06 canonical JSONL bytes.
- no duplicate `doc_id` exists.
- chunk record order is canonical.
- every chunk record has required T06 identity fields.
- lexical `doc_id` set equals chunk manifest `doc_id` set.
- vector `doc_id` set equals chunk manifest `doc_id` set.
- `contract_version` matches across staging artifacts.
- `corpus_manifest_hash` matches across staging artifacts.
- `chunk_manifest_hash` matches across staging artifacts.
- model and tokenizer locks match manifest policy when T08/T10 define them.
- no staging artifact path escapes the staging root.
- no active artifact path was modified during staging.

Any verification failure means STOP and invalidates staging.

## Promotion Rules

Promotion is the only operation allowed to expose staged artifacts as active.

Promotion preconditions:

- staging verification passed.
- active index, if present, is verified immediately before promotion.
- active index, if present, has not changed since pre-promotion verification.
- target path is exactly `.repo_index`.
- promotion can run on the same filesystem volume.
- promotion can guarantee no half-built artifact is accepted as healthy.

Promotion semantics:

- active artifacts remain untouched until staging verification passes.
- active `index_manifest.json` is the activation boundary.
- active manifest must be written with `manifest_state = ACTIVE_VERIFIED` only
  after required active artifacts are in place and post-placement verification
  succeeds.
- query mode must STOP if it observes missing active artifacts, mismatched
  hashes, non-`ACTIVE_VERIFIED` manifest state, or promotion-in-progress state.
- if the platform cannot guarantee fail-closed promotion behavior, the
  controller must STOP before modifying active artifacts.

Windows rule:

- future implementation must use Windows-safe same-volume file operations.
- no `/bin`, shell activation, bash, AF_UNIX, or `pgrep` may participate in
  promotion.
- if any active file or directory is locked and safe promotion cannot proceed,
  STOP and leave active artifacts unchanged.

## Failure Handling

Build failure before promotion:

- staging is invalid.
- active artifacts remain byte-identical.
- no partial staging artifact may be considered healthy.
- no query may use staging.
- no silent repair is allowed.

Promotion failure:

- active index must remain the last verified active index or be rejected by
  query preflight as unhealthy.
- staging must be invalidated.
- no partial active state may be marked healthy.
- rollback must preserve the last known good active index when it exists.
- if rollback cannot be guaranteed, query mode must STOP rather than serve
  partial results.

Query failure:

- missing active index means STOP.
- missing active manifest means STOP.
- `manifest_state != ACTIVE_VERIFIED` means STOP.
- missing artifact means CORRUPT_INDEX and STOP.
- hash or `doc_id` parity mismatch means CORRUPT_INDEX and STOP.
- query must never trigger build, repair, or promotion.

## Artifact Exposure Rules

Retrieval may read only active artifacts after query-mode preflight passes:

```text
.repo_index/index_manifest.json
.repo_index/chunk_manifest.jsonl
.repo_index/lexical_index/
.repo_index/chroma_db/
```

Retrieval must not read:

- staging artifacts.
- rollback artifacts.
- diagnostic exports.
- search manifests.
- searchable file inventories.
- cache files as authority.
- query memory as authority.

Retrieval must not write any artifact.

## Artifact Hash Rules

T07 adopts T06 hash rules and assigns artifact-level binding boundaries:

- `chunk_manifest_jsonl` hash is the T06 `chunk_manifest_hash`.
- `lexical_index` hash is defined by T09.
- `chroma_db` deterministic export hash is defined by T10.
- active manifest identity follows T06 self-reference rules.
- all active artifact hashes are stored in `index_manifest.json`.

Directory artifact hash rules, unless refined by T09/T10:

- use repo-index-relative paths.
- sort paths by UTF-8 byte order.
- include path byte length, path bytes, file byte length, and file bytes.
- exclude filesystem timestamps, permissions, inode numbers, and enumeration
  order.

## Stop Conditions

The controller must STOP if:

- any active artifact is written before staging verification passes.
- `.repo_index` is created by a design task.
- staging path is non-deterministic.
- staging path already exists and cleanup was not explicitly approved.
- active manifest is marked `ACTIVE_VERIFIED` before all artifact hashes pass.
- any required artifact is missing.
- any artifact hash mismatches the manifest.
- any artifact advertises a mismatched `contract_version`.
- any artifact advertises a mismatched `corpus_manifest_hash`.
- any artifact advertises a mismatched `chunk_manifest_hash`.
- any authoritative artifact is outside `.repo_index`.
- `search_manifest.txt` or `searchable_files.txt` is treated as authority.
- cache or diagnostic output becomes authority.
- Chroma metadata defines corpus, model, or ranking authority.
- lexical metadata defines corpus or ranking authority.
- query can observe staging as active.
- failed build changes active artifacts.
- promotion cannot guarantee fail-closed behavior.

## Contract Drift Analysis

The current repository does not yet satisfy this T07 artifact contract:

- `actual_truth/contracts/retrieval/index_structure_contract.md` still lists
  `.repo_index/searchable_files.txt` as an authoritative artifact.
- `actual_truth/contracts/retrieval/index_structure_contract.md` still defines
  a legacy flat manifest schema instead of T02/T07 nested artifact policy.
- `tools/index/build_repo_index.sh` creates `.repo_index` directly, deletes
  active files directly, and writes `search_manifest.txt` as a corpus artifact.
- `tools/index/build_vector_index.py` writes `index_manifest.json`,
  `chunk_manifest.jsonl`, `lexical_index/`, and `chroma_db/` directly under the
  active `.repo_index` root.
- `tools/index/build_vector_index.py` bootstraps and rewrites
  `index_manifest.json` before full artifact verification.
- `tools/index/build_vector_index.py` removes active `chroma_db/` with
  `shutil.rmtree` when rebuild is enabled.
- `tools/index/build_vector_index.py` uses Chroma `get_or_create_collection`,
  which permits implicit collection creation outside a verified staging model.
- `tools/index/build_vector_index.py` does not implement
  `manifest_state`, `_staging/<build_id>`, promotion verification, or active
  manifest-last activation.
- `tools/index/search_code.py` treats `search_manifest.txt` as a required
  healthy index artifact.
- `tools/index/search_code.py` writes `query_cache.json` and
  `query_memory.json` during query execution.
- `tools/index/search_code.py` uses `.repo_index/search_code.sock`, which is a
  runtime communication path inside the index root and is not an active
  authoritative artifact.
- `tools/index/ENVIRONMENT_SETUP.sh`, `tools/index/semantic_search.sh`, and
  `tools/mcp/semantic_search_server.py` still use Linux-style search venv
  paths and must later align with Windows runtime policy.

These are later correction targets. T07 does not patch them.

## Verification Result

T07 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, and `T06` were repo-visible `PASS`.
- `T07` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T07` as the next executable task.
- T07 scope was limited to artifact structure and write-order design.
- T02 manifest authority was treated as locked.
- T04 normalization was treated as locked.
- T05 chunking was treated as locked.
- T06 identity and hashing were treated as locked.
- canonical active artifact paths are defined.
- staging layout and write order are defined.
- verification-before-promotion gates are defined.
- active/staging isolation rules are defined.
- failure handling is fail-closed.
- existing drift is identified for later controller tasks.
- no `.repo_index` directory was created.
- no staging artifacts were created.
- no index was built.
- no model was downloaded or executed.
- CUDA was not used.
- no retrieval query was executed.
- T08 and later tasks were not executed.

## Next Transition

Only `T08` may execute next under the strict controller order.
