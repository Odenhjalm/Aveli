# T15 - Define Controller Execution Loop

TYPE: design
OS_ROLE: AGGREGATE
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: [T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14]

## Purpose

Define the full deterministic controller loop that all retrieval/indexing work
must use.

## Scope

Design only. Do not implement the controller, modify tools, build an index, or
run retrieval.

## Authority References

- all retrieval contracts
- `codex/AVELI_OPERATING_SYSTEM.md`
- T01 through T14

## Dependencies

- T01
- T02
- T03
- T04
- T05
- T06
- T07
- T08
- T09
- T10
- T11
- T12
- T13
- T14

## Expected Outcome

The controller loop is:

1. bind `input(task, mode)`
2. load OS, DECISIONS, MANIFEST, and CONTRACTS
3. run Windows preflight
4. validate `index_manifest.json`
5. for query mode, require healthy artifacts and run read-only retrieval
6. for build mode, require explicit rebuild approval
7. resolve corpus only from `index_manifest.json`
8. normalize corpus paths and text
9. emit deterministic chunks
10. derive hashes and doc IDs
11. build lexical index from chunk manifest
12. build Chroma index from the same chunk manifest
13. verify artifact parity and hashes
14. promote staged artifacts only after full verification
15. serve canonical evidence only through retrieval contract
16. stop on any mismatch

## Stop Conditions

- A stage executes before its dependencies.
- Mode changes during execution.
- A non-controller path performs build, embedding, storage, retrieval, or MCP search.
- Any authority is ambiguous.
- Any stage consumes undeclared inputs.
- Verification fails.

## Verification Requirements

- Every stage input is produced by a prior stage or by canonical authority.
- No phase duplicates another phase responsibility.
- Build and query paths are disjoint.
- Query path is read-only.

## Mutation Rules

No mutation is allowed during this design task.

## Output Artifacts

Future execution may produce a controller loop result document.

## Next Transitions

- T16
- T17
