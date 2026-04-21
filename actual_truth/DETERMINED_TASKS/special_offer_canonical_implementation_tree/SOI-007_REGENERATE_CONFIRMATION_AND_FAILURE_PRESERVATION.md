# SOI-007 REGENERATE CONFIRMATION AND FAILURE PRESERVATION

- TASK_ID: `SOI-007`
- TYPE: `OWNER`
- GROUP: `GENERATION EXECUTION FLOW`

## Purpose

Implement explicit regenerate orchestration so active-image replacement is
backend-confirmed, attempt-tracked, overwrite-safe, and failure-preserving.

## Contract References

- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`

## DEPENDS_ON

- `SOI-006`

## Dependency Requirements

- regenerate is explicit and may replace an existing active output only with
  backend-enforced confirmation
- any action that would replace an active output must use regenerate semantics
- failed regenerate leaves the previous active output bound
- attempts remain support-only and never become active output truth

## Exact Scope

- overwrite confirmation gate in backend execution flow
- regenerate orchestration for offers with active outputs
- attempt status transitions for regenerate
- output replacement only after successful new output creation
- preservation of previous output on failure

## Verification Criteria

- regenerate is rejected when confirmation is missing
- previous active image remains bound if regenerate fails
- no version-history surface is introduced
- no synchronous media deletion occurs inside the regenerate request

## GO Condition

Go when active-image replacement can happen only through explicit regenerate
with backend confirmation and failure-safe output preservation.

## BLOCKED Condition

Stop if overwrite can occur without confirmation, if failed regenerate clears
the active image, or if attempt state becomes public output authority.

## Out Of Scope

- exact warning copy
- frontend dialog presentation
- final read projection
