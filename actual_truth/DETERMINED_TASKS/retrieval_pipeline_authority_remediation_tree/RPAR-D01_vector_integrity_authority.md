# RPAR-D01_VECTOR_INTEGRITY_AUTHORITY

## TASK_ID

RPAR-D01

## TYPE

VECTOR_INTEGRITY_AUTHORITY

## OWNER

OWNER

## CANONICAL_OWNER

integrity system

## DEPENDS_ON

- `RPAR-C01`

## GOAL

Materialize the future vector-integrity remediation that expands validation to
every metadata field written into the stored vector artifacts.

The locked truth for this slice is:

- the stored vector metadata contract must be explicit
- the integrity validator must cover the full stored key set
- vector metadata parity is incomplete until every stored field is validated

## AUTHORITY INPUTS

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/task_tree_execution_controller_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/build_execution_result_contract.md`
- `tools/index/build_vector_index.py`
- `tools/index/index_artifact_integrity.py`

## VALIDATED ISSUE BASIS

The builder writes collection and record metadata fields that the integrity
validator does not currently verify, leaving parity checks incomplete.

## SCOPE

- `tools/index/build_vector_index.py`
- `tools/index/index_artifact_integrity.py`
- any directly coupled integrity-contract surface required to document the
  canonical metadata contract

## EXACT REQUIRED OUTCOME

When `RPAR-D01` executes later, implement only the vector-integrity work
required to guarantee all of the following:

- the full stored metadata key inventory is enumerated deterministically
- the validator checks every stored record-level metadata field
- the validator checks every stored collection-level metadata field
- vector metadata parity means total parity, not partial parity

## FORBIDDEN ACTIONS

- Do not change runtime freshness or observability behavior.
- Do not change corpus classification or evidence gating.
- Do not add tests in this slice.
- Do not redefine build device policy beyond truthful metadata capture.
- Do not leave undocumented metadata fields outside the validator.

## ACCEPTANCE CRITERIA

- The set difference between stored metadata keys and validated metadata keys
  is empty.
- Drift in any stored metadata field fails integrity verification.
- Record-level and collection-level parity are both complete.
- No runtime, corpus, or test work is performed outside this slice.

## STOP CONDITIONS

- The full stored metadata key set cannot be enumerated from repo-visible
  build logic.
- Completing parity requires corpus or runtime-law changes.
- Any metadata field remains intentionally unvalidated without a ratified
  contract exception.

## VERIFICATION STEPS

- Inventory every metadata key written by the builder.
- Inventory every metadata key checked by the integrity validator.
- Confirm the inventories match exactly.
- Introduce controlled drift in a previously unvalidated metadata field and
  confirm integrity verification fails.

## PROMPT

```text
Execute RPAR-D01 as the vector-integrity-authority slice only. Define the canonical stored vector metadata contract and expand integrity validation so every metadata field written by the builder at record and collection level is validated. Do not change runtime freshness, observability schema logic, corpus authority, or tests in this slice.
```
