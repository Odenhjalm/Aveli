# T14 - Define Rebuild Approval Gate

TYPE: design
OS_ROLE: GATE
EXECUTION_STATUS: PASS
DEPENDS_ON: [T01, T03, T07, T13]

## Purpose

Define the explicit approval gate required before any index build or rebuild.

## Scope

Design only. Do not request approval inside the task, build an index, or create
`.repo_index`.

## Authority References

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- T01 authority decision
- T03 preflight contract
- T07 artifact model
- T13 Windows gate

## Dependencies

- T01
- T03
- T07
- T13

## Expected Outcome

The rebuild approval protocol requires explicit user approval containing:
approval phrase `APPROVE AVELI INDEX REBUILD`, repo root and corpus scope,
`index_manifest.json` as only authority, CPU baseline, Windows interpreter path,
model and tokenizer lock, artifact destination under `.repo_index/`, and
acknowledgment that no CUDA, no auto-download, and no fallback are allowed.

## Stop Conditions

- Query attempts to build.
- Missing index triggers build automatically.
- Rebuild is justified by age, quality, repo change, or assumption.
- Background indexing starts.
- Approval is implicit, partial, or ambiguous.

## Verification Requirements

- Missing `.repo_index` returns `STOP: INDEX REBUILD NOT APPROVED` unless an explicit approval record exists.
- Build path cannot start without approval.
- Query path cannot invoke build path.

## Mutation Rules

No runtime mutation is allowed during this design task. Controller execution may
update this task status and write `T14_execution_result.md` only.

## Output Artifacts

- `T14_execution_result.md`

Approval records are not created by this task.

## Next Transitions

- T15
