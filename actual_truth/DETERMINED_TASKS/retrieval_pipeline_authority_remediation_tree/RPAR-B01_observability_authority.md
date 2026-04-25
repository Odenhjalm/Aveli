# RPAR-B01_OBSERVABILITY_AUTHORITY

## TASK_ID

RPAR-B01

## TYPE

OBSERVABILITY_AUTHORITY

## OWNER

OWNER

## CANONICAL_OWNER

observability

## DEPENDS_ON

- `RPAR-A01`

## GOAL

Materialize the future observability remediation that aligns retrieval
observability outputs to real upstream artifact fields and removes null or
phantom schema keys.

The locked truth for this slice is:

- every observability field must have one upstream authority source or be
  removed
- schema aliases that generate permanent nulls are forbidden
- observability must describe reality, not inferred or wishful state

## AUTHORITY INPUTS

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/task_tree_execution_controller_contract.md`
- `actual_truth/contracts/retrieval/build_execution_result_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `tools/index/retrieval_observability.py`
- `tools/index/dependency_authority.py`
- `tools/index/build_vector_index.py`
- `.repo_index/promotion_result.json`
- `.repo_index/observability/retrieval_last_build_status.json`
- `.repo_index/observability/retrieval_dependency_health.json`
- `.repo_index/observability/retrieval_model_health.json`

## VALIDATED ISSUE BASIS

Current observability writers read field names that do not match the active
promotion result and dependency/model authority surfaces, producing null
placeholders and phantom keys.

## SCOPE

- `tools/index/retrieval_observability.py`
- `tools/index/dependency_authority.py`
- any directly coupled build-result serialization surface required to align
  source-backed observability fields

## EXACT REQUIRED OUTCOME

When `RPAR-B01` executes later, implement only the schema-alignment work
required to guarantee all of the following:

- `promotion_result` and `retrieval_last_build_status` use aligned field names
- dependency health exposes only fields that survive D01 serialization or
  explicitly adds the source-backed data needed
- model health reads the real model binding field names
- null placeholders disappear unless the upstream source is genuinely absent

## FORBIDDEN ACTIONS

- Do not change runtime freshness behavior beyond what `RPAR-A01` already
  locked.
- Do not change corpus classification or evidence gating.
- Do not change build CUDA or fallback behavior.
- Do not add tests in this slice.
- Do not keep mismatched aliases merely to preserve dead schema keys.

## ACCEPTANCE CRITERIA

- Every observability field maps to one upstream source field or is removed.
- `retrieval_last_build_status` no longer emits phantom promotion keys.
- `retrieval_dependency_health` no longer emits permanently null dependency
  fields without source backing.
- `retrieval_model_health` exposes real model snapshot binding data.
- No runtime, corpus, build-truthfulness, integrity, or test logic changes
  occur outside the declared schema-alignment scope.

## STOP CONDITIONS

- Any observability field has no single upstream authority source.
- Aligning observability would require reopening runtime freshness law.
- Schema alignment requires corpus or build-policy changes.
- Phantom keys are preserved as undocumented compatibility debt.

## VERIFICATION STEPS

- Enumerate the live upstream artifact fields for promotion, dependency, and
  model status.
- Regenerate observability outputs after the slice changes.
- Diff observability keys and values against the upstream source fields.
- Confirm no source-backed value remains null because of a naming mismatch.
- Confirm removed fields are truly phantom and not silently reintroduced.

## PROMPT

```text
Execute RPAR-B01 as the observability-authority slice only. Align retrieval observability outputs to the real promotion, dependency, and model source fields, and remove phantom or null placeholder keys that have no upstream authority. Do not change runtime freshness, corpus classification, build truthfulness, vector integrity logic, or tests in this slice.
```
