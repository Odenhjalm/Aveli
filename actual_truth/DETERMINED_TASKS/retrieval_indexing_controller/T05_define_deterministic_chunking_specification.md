# T05 - Define Deterministic Chunking Specification

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: [T04]

## Purpose

Define deterministic chunk emission rules for normalized corpus text.

## Scope

Design chunking only. Do not chunk the repository and do not write
`chunk_manifest.jsonl`.

## Authority References

- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- T04 normalization rules

## Dependencies

- T04

## Expected Outcome

The chunking specification defines chunking over normalized text only, fixed
`chunk_size` and `chunk_overlap` from `index_manifest.json`, no model-dependent
or tokenizer-dependent boundaries, source order preserved within each file, no
empty chunks, no cross-file chunks, first `chunk_index` equals 0, no gaps, and
canonical chunk order by normalized `file` then `chunk_index`.

## Stop Conditions

- Chunk boundaries depend on runtime state, model tokenizer, traversal order, or adaptive heuristics.
- Empty chunks are emitted.
- A chunk crosses file boundaries.
- Chunk order changes across repeated runs.

## Verification Requirements

- Same normalized input yields identical chunk sequence.
- Re-sorting emitted chunks does not change canonical order.
- `(file, chunk_index)` is unique.

## Mutation Rules

No mutation is allowed during this design task.

## Output Artifacts

Future execution may produce a chunking specification result document.

## Next Transitions

- T06
