# RPAR-A01_RUNTIME_AUTHORITY

## TASK_ID

RPAR-A01

## TYPE

RUNTIME_AUTHORITY

## OWNER

OWNER

## CANONICAL_OWNER

runtime

## DEPENDS_ON

[]

## GOAL

Materialize the future runtime remediation that makes active-build detection
deterministic and forces runtime freshness parity between one-shot CLI queries
and long-lived MCP retrieval.

The locked truth for this slice is:

- there is one canonical source of active build truth
- runtime cache may not outlive a build promotion invisibly
- MCP and CLI retrieval must serve the same promoted build under the same
  runtime contract

## AUTHORITY INPUTS

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/task_tree_execution_controller_contract.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `tools/index/search_code.py`
- `tools/mcp/semantic_search_server.py`
- `.repo_index/index_manifest.json`
- `.repo_index/promotion_result.json`
- `.repo_index/observability/retrieval_last_build_status.json`

## VALIDATED ISSUE BASIS

The current runtime uses cached state in `tools/index/search_code.py` and the
MCP wrapper calls canonical retrieval in-process from a persistent server loop.
That combination permits stale build state to survive a promotion until the
process or runtime state is rebuilt.

## SCOPE

- `tools/index/search_code.py`
- `tools/mcp/semantic_search_server.py`
- any minimal runtime-state helper required only to implement canonical
  active-build freshness

## EXACT REQUIRED OUTCOME

When `RPAR-A01` executes later, implement only the runtime freshness boundary
required to guarantee all of the following:

- runtime chooses one canonical promoted-build source
- cached runtime state invalidates or reloads when that source changes
- CLI and MCP use the same freshness decision rule
- no ranking, scoring, corpus membership, or model policy changes occur in
  this slice

## FORBIDDEN ACTIONS

- Do not edit observability schema logic.
- Do not change corpus classification.
- Do not change build device policy or fallback policy.
- Do not add manual-restart requirements as a workaround.
- Do not suppress stale behavior by forcing per-query full rebuild unless that
  is the explicit canonical runtime contract.
- Do not execute `RPAR-B01` or any later task inside this slice.

## ACCEPTANCE CRITERIA

- A promoted build becomes visible to CLI retrieval without ambiguity.
- The same promoted build becomes visible to long-lived MCP retrieval without
  process restart.
- Runtime freshness is governed by one canonical build source only.
- No retrieval result uses stale active-build state after promotion.
- No observability, corpus-authority, build-truthfulness, integrity, or test
  behavior is changed outside runtime freshness scope.

## STOP CONDITIONS

- No single canonical active-build source can be selected from repo-visible
  artifacts.
- Runtime freshness requires schema or corpus-law changes to proceed.
- MCP still requires manual restart to observe promotion.
- The slice would need to change ranking, models, or corpus inputs.

## VERIFICATION STEPS

- Promote a new build under the governed build flow.
- Query through a fresh CLI process and record active build identifiers.
- Query through a long-lived MCP process without restart and record active
  build identifiers.
- Confirm the two paths bind to the same build id, corpus hash, and chunk
  hash.
- Confirm no runtime output reflects the previous build after promotion.

## PROMPT

```text
Execute RPAR-A01 as the runtime-authority slice only. Update only the runtime freshness boundary so promoted active-build changes are detected deterministically and both CLI retrieval and long-lived MCP retrieval reload or invalidate stale runtime state under the same canonical rule. Do not change observability schemas, corpus classification, build device policy, vector integrity logic, or tests in this slice.
```
