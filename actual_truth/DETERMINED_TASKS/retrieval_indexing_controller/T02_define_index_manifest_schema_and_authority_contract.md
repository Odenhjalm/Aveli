# T02 - Define Index Manifest Schema And Authority Contract

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: [T01]

## Purpose

Define the canonical `index_manifest.json` schema so it can govern every
retrieval and indexing parameter without duplicate authority.

## Scope

Design the manifest authority contract only. Do not create `.repo_index`, write
an actual manifest, build artifacts, or modify tool code.

## Authority References

- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- T01 authority decision

## Dependencies

- T01

## Expected Outcome

The schema definition includes `contract_version`, canonical corpus object,
`corpus_manifest_hash`, `chunk_manifest_hash`, artifact hashes, chunk settings,
model and tokenizer locks, ranking policy, candidate limits, classification
rules, Windows interpreter, CPU baseline, and rebuild approval state.

## Stop Conditions

- Any canonical parameter remains hardcoded outside `index_manifest.json`.
- Corpus hash depends on a separate authoritative file list.
- Model or tokenizer revision is not locked.
- Ranking policy is private or duplicated.
- Classification rules can assign more than one layer without precedence.

## Verification Requirements

- Every runtime parameter can be traced to one manifest field.
- No other file redefines canonical chunking, model, ranking, candidate limit, classification, or corpus membership values.
- Manifest schema supports deterministic artifact hashing.

## Mutation Rules

No mutation is allowed during this design task.

## Output Artifacts

Future execution may produce a schema design result document. No runtime
manifest may be written by this task.

## Next Transitions

- T03
- T04
- T07
- T08
