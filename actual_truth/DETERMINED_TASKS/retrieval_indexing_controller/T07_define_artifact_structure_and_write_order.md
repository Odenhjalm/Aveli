# T07 - Define Artifact Structure And Write Order

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: PASS
DEPENDS_ON: [T02, T06]

## Purpose

Define the authoritative artifact set and safe write order for controller
governed index builds.

## Scope

Design only. Do not create `.repo_index`, stage artifacts, or write an index.

## Authority References

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- T02 manifest schema
- T06 hashing rules

## Dependencies

- T02
- T06

## Expected Outcome

The artifact model defines `.repo_index/index_manifest.json`,
`.repo_index/chunk_manifest.jsonl`, `.repo_index/lexical_index/`,
`.repo_index/chroma_db/`, optional non-authoritative diagnostics and caches,
staging output, verification before active promotion, fail-closed promotion
semantics, and artifact hash binding to `index_manifest.json`.

## Stop Conditions

- Active artifacts are modified before staging verification passes.
- Partial artifacts are marked healthy.
- Any authoritative artifact is written outside `.repo_index`.
- Cache or diagnostic output becomes authority.
- Retrieval can see half-built artifacts as healthy.

## Verification Requirements

- Required artifact set is complete.
- Artifact hashes match manifest values.
- `contract_version`, `corpus_manifest_hash`, and `chunk_manifest_hash` bind across all artifacts.
- Failed build leaves active artifacts byte-identical.

## Mutation Rules

No runtime mutation is allowed during this design task. Controller execution may
update this task status and write `T07_execution_result.md` only.

## Output Artifacts

- `T07_execution_result.md`

## Next Transitions

- T09
- T10
- T11
- T14
