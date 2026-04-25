# RPAR-F01_TEST_SURFACE

## TASK_ID

RPAR-F01

## TYPE

TEST_SURFACE

## OWNER

GATE

## CANONICAL_OWNER

test surface

## DEPENDS_ON

- `RPAR-E01`

## GOAL

Materialize the future verification slice that encodes runtime, observability,
build-truthfulness, integrity, and corpus-authority fixes as deterministic
tests and parity gates.

The locked truth for this slice is:

- tests verify slices `A` through `E`; they do not replace them
- the test surface must cover both fresh-process and long-lived-process modes
- parity and drift failures must be observable and reproducible

## AUTHORITY INPUTS

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/task_tree_execution_controller_contract.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `actual_truth/contracts/retrieval/build_execution_result_contract.md`
- all completed task files from `RPAR-A01` through `RPAR-E01`
- `tools/index`
- `backend/tests`

## VALIDATED ISSUE BASIS

The current retrieval test surface is too thin to prove promotion-to-runtime
reload behavior, observability parity, truthful build reporting, integrity
drift detection, or MCP versus CLI parity.

## SCOPE

- targeted retrieval tests under `tools/index`
- targeted integration or audit gates under `backend/tests`
- execution evidence updates in this task tree

## EXACT REQUIRED OUTCOME

When `RPAR-F01` executes later, implement only the verification work required
to guarantee all of the following:

- end-to-end retrieval correctness remains valid
- promotion to runtime reload correctness is tested
- observability parity is tested
- integrity drift detection is tested
- MCP versus CLI parity is tested

## FORBIDDEN ACTIONS

- Do not use tests to compensate for unresolved production contradictions.
- Do not modify runtime, observability, build, integrity, or corpus logic
  unless a test exposes a real remaining blocker and execution stops.
- Do not rely on manual restart, hidden local state, or ad hoc timing windows.

## ACCEPTANCE CRITERIA

- Deterministic tests exist for slices `A` through `E`.
- The suite covers fresh-process and long-lived-process retrieval.
- The suite fails on runtime staleness, schema drift, false build PASS states,
  metadata drift, and MCP versus CLI divergence.
- Execution evidence records the exact commands and outputs used for the gate.

## STOP CONDITIONS

- Any earlier slice is incomplete or unverified.
- A test is proposed before its target behavior is stabilized.
- A gate depends on manual restart or non-deterministic timing to pass.
- The suite passes while a known production contradiction remains unresolved.

## VERIFICATION STEPS

- Run the targeted suite in a fresh process.
- Run the targeted suite against a long-lived MCP process.
- Induce controlled failure conditions for stale runtime, schema drift, build
  truthfulness drift, and metadata drift.
- Confirm the suite fails closed on those conditions and passes the fixed
  implementation.

## PROMPT

```text
Execute RPAR-F01 as the final test-surface gate only. Add deterministic tests and audit gates that prove runtime reload, observability parity, build truthfulness, vector metadata integrity drift detection, corpus-authority behavior, and MCP versus CLI parity under both fresh-process and long-lived-process execution. Do not use this slice to compensate for unresolved production contradictions.
```
