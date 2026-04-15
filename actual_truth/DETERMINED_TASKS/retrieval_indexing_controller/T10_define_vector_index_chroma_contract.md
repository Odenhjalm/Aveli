# T10 - Define Vector Index Chroma Contract

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: [T06, T07, T08]

## Purpose

Define the Chroma vector index contract for deterministic storage and retrieval
parity.

## Scope

Design only. Do not create Chroma databases, collections, embeddings, or
`.repo_index`.

## Authority References

- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- T06 hashing rules
- T07 artifact model
- T08 model policy

## Dependencies

- T06
- T07
- T08

## Expected Outcome

The vector contract defines that Chroma collection metadata binds
`contract_version`, `corpus_manifest_hash`, `chunk_manifest_hash`, model lock,
and embedding dimension; vector IDs are canonical `doc_id`; vector documents
are canonical chunk text; vector metadata is derived from chunk manifest and
manifest classification rules; vector doc_id set equals chunk and lexical
doc_id sets; and query cannot create or repair collection state.

## Stop Conditions

- Chroma determines corpus membership.
- Chroma collection creation occurs during query.
- Vector IDs differ from canonical `doc_id`.
- Model or dimension mismatch is tolerated.
- Retrieval rebuilds or mutates Chroma.

## Verification Requirements

- Chroma doc_id set equals chunk manifest and lexical doc_id sets.
- Chroma metadata matches `index_manifest.json`.
- Vector query reads only a healthy collection.

## Mutation Rules

No mutation is allowed during this design task.

## Output Artifacts

Future execution may produce a vector contract result document.

## Next Transitions

- T11
