# T06 - Define Doc ID And Hashing Rules

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: [T05]

## Purpose

Define stable chunk identity, content hashing, and manifest hashing rules.

## Scope

Design only. Do not compute hashes for the live repository and do not write
index artifacts.

## Authority References

- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- T05 chunking specification

## Dependencies

- T05

## Expected Outcome

The identity rules define `content_hash` as SHA-256 over canonical chunk
payload bytes, `doc_id` as SHA-256 over contract version, normalized file path,
chunk index, and content hash, `chunk_manifest_hash` as SHA-256 over canonical
sorted JSONL bytes, artifact hash calculations over deterministic byte
representations, and stable JSON serialization with sorted keys and LF endings.

## Stop Conditions

- `doc_id` uses process counters, traversal order, timestamps, Chroma IDs, or object memory order.
- Hash input is not explicitly byte-defined.
- Changing one chunk mutates unrelated `doc_id` values.

## Verification Requirements

- Identical inputs produce identical `doc_id` and manifest hashes.
- A one-chunk content change affects only the changed chunk identity and aggregate hashes that must change.
- Hashes are reproducible on Windows.

## Mutation Rules

No mutation is allowed during this design task.

## Output Artifacts

Future execution may produce a hashing specification result document.

## Next Transitions

- T07
- T09
- T10
