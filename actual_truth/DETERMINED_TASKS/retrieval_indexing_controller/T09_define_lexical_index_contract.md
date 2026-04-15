# T09 - Define Lexical Index Contract

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: [T06, T07]

## Purpose

Define the persistent lexical index contract for deterministic hybrid retrieval.

## Scope

Design only. Do not build lexical artifacts and do not scan the repository.

## Authority References

- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- T06 hashing rules
- T07 artifact model

## Dependencies

- T06
- T07

## Expected Outcome

The lexical contract defines that the lexical index is built only from
`chunk_manifest.jsonl`, supports lookup by canonical `doc_id`, emits
deterministic top-N candidates over canonical chunk text, exports or validates
the indexed doc_id set, binds to `contract_version`, `corpus_manifest_hash`,
and `chunk_manifest_hash`, and never rebuilds full-corpus statistics during
query.

## Stop Conditions

- Lexical search builds BM25 or statistics during query.
- Lexical index cannot export doc_id set.
- Lexical index references a different corpus or chunk generation.
- Lexical records become corpus authority.

## Verification Requirements

- Lexical doc_id set equals chunk manifest doc_id set.
- Lexical metadata matches `index_manifest.json`.
- Warm query work is bounded by candidate limits.

## Mutation Rules

No mutation is allowed during this design task.

## Output Artifacts

Future execution may produce a lexical contract result document.

## Next Transitions

- T11
