# T16 - Define Verification Suite Deterministic Tests

TYPE: verification
OS_ROLE: GATE
EXECUTION_STATUS: BLOCKED
DEPENDS_ON: [T15]

## Purpose

Define the deterministic verification suite that must prove controller,
artifact, retrieval, MCP, and Windows compliance.

## Scope

Verification design only. Do not create test files, run tests, build indexes,
or download models.

## Authority References

- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- T15 controller loop

## Dependencies

- T15

## Expected Outcome

The verification suite design covers manifest schema validation,
single-authority checks, corpus normalization determinism, chunk determinism,
`doc_id` stability, model and tokenizer lock validation without download,
artifact write-order and promotion checks, lexical/vector/chunk doc_id parity,
retrieval read-only behavior, deterministic ordered evidence, MCP wrapper
equivalence, Windows forbidden construct scan, and exact fail-closed messages.

## Stop Conditions

- Verification requires CUDA.
- Verification downloads models.
- Verification mutates active artifacts.
- Verification accepts fallback behavior.
- Verification runs outside task scope.

## Verification Requirements

- Repeated fixed inputs produce identical bytes.
- Failure fixtures produce exact Swedish STOP messages.
- Deleting optional caches does not change authoritative retrieval output.
- Healthy retrieval produces canonical evidence shape only.

## Mutation Rules

No runtime mutation is allowed during this verification-design task. Controller
execution may update this task status and write `T16_execution_result.md` only.

## Output Artifacts

- `T16_execution_result.md`

## Next Transitions

- T17 only after T16 is re-run and reaches `PASS`
