# T17 - Define Failure Modes And Rollback Rules

TYPE: design
OS_ROLE: GATE
EXECUTION_STATUS: NOT_STARTED
DEPENDS_ON: [T15, T16]

## Purpose

Define fail-closed failure classifications and rollback rules for controlled
index builds and read-only retrieval.

## Scope

Design only. Do not execute rollback, delete files, build indexes, or modify
active artifacts.

## Authority References

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- T15 controller loop
- T16 verification suite

## Dependencies

- T15
- T16

## Expected Outcome

The failure model defines `STOP`, `BLOCKED`, `DRIFT`, `CONTRACT_DRIFT`,
`CORRUPT_INDEX`, failed build behavior that discards staging only, active
healthy index preservation, no auto-repair, no fallback retrieval after
corruption, and no deletion of active index without explicit approval.

## Stop Conditions

- Rollback deletes active artifacts automatically.
- Failed build mutates active artifacts.
- Corrupt index falls back to corpus scan.
- Failure handling guesses cause.
- Failure handling continues in degraded mode.

## Verification Requirements

- Simulated failures leave active artifacts byte-identical.
- Every failure names exact missing or invalid prerequisite.
- Corrupt or missing index stops before query execution.
- No rollback action occurs without explicit approved scope.

## Mutation Rules

No mutation is allowed during this design task.

## Output Artifacts

Future execution may produce a failure-mode matrix result document.

## Next Transitions

After T17, controller design is complete. The next allowed execution task is T01
under controller governance.
