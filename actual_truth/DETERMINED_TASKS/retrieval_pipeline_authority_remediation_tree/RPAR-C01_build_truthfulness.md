# RPAR-C01_BUILD_TRUTHFULNESS

## TASK_ID

RPAR-C01

## TYPE

BUILD_TRUTHFULNESS

## OWNER

OWNER

## CANONICAL_OWNER

build pipeline

## DEPENDS_ON

- `RPAR-B01`

## GOAL

Materialize the future build-truthfulness remediation that makes CUDA
execution and fallback reporting evidence-backed rather than synthetic.

The locked truth for this slice is:

- CUDA availability is not enough; the build must prove actual execution
- PASS states may not be hard-coded where evidence is required
- fallback reporting must reflect real runtime behavior

## AUTHORITY INPUTS

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/task_tree_execution_controller_contract.md`
- `actual_truth/contracts/retrieval/build_execution_result_contract.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_index_build_execution/B01_controller_governed_index_build.md`
- `tools/index/build_vector_index.py`

## VALIDATED ISSUE BASIS

The current build path validates CUDA availability but not actual encode-device
execution, records the configured build device before runtime proof exists, and
contains hard-coded PASS states for fallback reporting.

## SCOPE

- `tools/index/build_vector_index.py`
- any directly coupled build-result contract text needed to preserve truthful
  semantics

## EXACT REQUIRED OUTCOME

When `RPAR-C01` executes later, implement only the build-truthfulness work
required to guarantee all of the following:

- device reporting proves post-load or post-encode execution truth
- `device_check` reflects actual device truth
- fallback reporting is derived from real behavior
- synthetic PASS states are removed from success and failure result paths

## FORBIDDEN ACTIONS

- Do not change runtime cache logic.
- Do not change observability schema logic beyond fields directly driven by the
  truthful build result.
- Do not change corpus classification.
- Do not change vector-integrity scope outside build-result truthfulness.
- Do not treat CUDA availability as equivalent to CUDA execution.

## ACCEPTANCE CRITERIA

- A CUDA-approved build emits device evidence tied to actual execution.
- `device_check` no longer mirrors an unrelated fallback field.
- `no_fallback_used` is derived, not hard-coded.
- Failure paths do not report false PASS states.
- No ranking, corpus-membership, or model-selection law changes occur in this
  slice.

## STOP CONDITIONS

- Actual device execution cannot be measured from the build runtime.
- Truthful reporting would require changing model or corpus policy.
- Any PASS state survives without evidence backing it.
- The slice drifts into runtime, corpus, or test work.

## VERIFICATION STEPS

- Run a governed CUDA-approved build.
- Inspect the staging verification result and build execution result.
- Confirm device execution proof is present after model load or encode.
- Confirm fallback fields reflect measured behavior.
- Confirm failure paths also report truthfully when forced under test or audit
  conditions.

## PROMPT

```text
Execute RPAR-C01 as the build-truthfulness slice only. Update the build pipeline so CUDA execution and fallback reporting are evidence-backed, device_check reflects actual execution truth, and synthetic PASS states are removed from success and failure paths. Do not change runtime freshness, corpus classification, broader observability schemas, vector-integrity scope beyond required truthful metadata, or tests in this slice.
```
