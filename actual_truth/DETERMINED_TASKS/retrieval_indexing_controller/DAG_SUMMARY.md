# Retrieval Indexing Controller DAG Summary

EXECUTION_STATUS: IN_PROGRESS

## Purpose

Summarize the deterministic task graph for the Aveli retrieval/indexing
controller. This DAG is the only valid execution order source for T01 through
T17.

T00 is controller context and is not an executable DAG dependency for T01
through T17.

## Authority Inputs

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`

## DAG

| Task | Depends On | Role | Status |
| --- | --- | --- | --- |
| T01 | [] | OWNER | PASS |
| T02 | [T01] | OWNER | PASS |
| T03 | [T02] | OWNER | PASS |
| T04 | [T02, T03] | OWNER | NOT_STARTED |
| T05 | [T04] | OWNER | NOT_STARTED |
| T06 | [T05] | OWNER | NOT_STARTED |
| T07 | [T02, T06] | OWNER | NOT_STARTED |
| T08 | [T02, T03] | OWNER | NOT_STARTED |
| T09 | [T06, T07] | OWNER | NOT_STARTED |
| T10 | [T06, T07, T08] | OWNER | NOT_STARTED |
| T11 | [T07, T09, T10] | OWNER | NOT_STARTED |
| T12 | [T11] | OWNER | NOT_STARTED |
| T13 | [T03, T08, T11, T12] | GATE | NOT_STARTED |
| T14 | [T01, T03, T07, T13] | GATE | NOT_STARTED |
| T15 | [T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14] | AGGREGATE | NOT_STARTED |
| T16 | [T15] | GATE | NOT_STARTED |
| T17 | [T15, T16] | GATE | NOT_STARTED |

## Topological Order

1. T01
2. T02
3. T03
4. T04
5. T05
6. T06
7. T07
8. T08
9. T09
10. T10
11. T11
12. T12
13. T13
14. T14
15. T15
16. T16
17. T17

## Edge Audit

This DAG intentionally preserves the previously defined dependencies exactly.

No new edges are introduced.

No required edges are omitted.

No dependency points to a later undefined task.

## Execution Rule

Execution must start with T01. A task may execute only after every listed
dependency is complete and verified.

## Stop Conditions

- Any execution order deviates from this DAG.
- Any task executes with missing dependencies.
- Any task creates `.repo_index`.
- Any task builds an index.
- Any task downloads a model.
- Any task modifies `tools/index/*` before controller governance permits it.
- Any query path triggers a build.

## Next Allowed Task

T04 is the only allowed next executable task.
