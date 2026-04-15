# T01 - Resolve Canonical Corpus Authority

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: PASS
DEPENDS_ON: []

## Purpose

Resolve the corpus authority conflict for Aveli retrieval/indexing. The task
must decide how `index_manifest.json` becomes the only corpus authority and how
legacy file lists such as `search_manifest.txt` and `searchable_files.txt` are
treated.

## Scope

Inspection and authority decision only. This task may inspect retrieval
contracts and existing index tooling, but must not implement code, build an
index, create `.repo_index`, or modify `tools/index/*`.

## Authority References

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `tools/index/build_repo_index.sh`
- `tools/index/build_vector_index.py`
- `tools/index/search_code.py`

## Dependencies

None.

## Expected Outcome

- A single corpus authority decision exists.
- `index_manifest.json` is confirmed as the only future corpus and configuration authority.
- `search_manifest.txt` and `searchable_files.txt` are classified as non-authoritative exports, deprecated surfaces, or contract drift requiring later contract alignment.
- Current conflict is classified explicitly as `CONTRACT_DRIFT`.

## Stop Conditions

- Any source other than `index_manifest.json` remains canonical corpus authority.
- The task attempts to generate a corpus list.
- The task reads from or writes to `.repo_index`.
- The task treats repo traversal output as runtime truth.
- The authority decision is ambiguous.

## Verification Requirements

- The decision references the exact conflict:
  - ingestion contract names `.repo_index/search_manifest.txt`
  - index structure contract names `.repo_index/searchable_files.txt`
  - current tools use `.repo_index/search_manifest.txt`
  - determinism and evidence contracts require `index_manifest.json` as the single configuration and classification authority
- The output contains no build instruction.
- The output defines allowed next transition as T02 only.

## Mutation Rules

No mutation is allowed when executing this task unless a later explicit
materialization task authorizes writing the T01 result artifact.

## Output Artifacts

- `T01_execution_result.md`

## Next Transitions

- T02
