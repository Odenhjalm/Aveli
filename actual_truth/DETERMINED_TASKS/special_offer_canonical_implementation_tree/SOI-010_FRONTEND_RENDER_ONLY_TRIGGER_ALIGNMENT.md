# SOI-010 FRONTEND RENDER ONLY TRIGGER ALIGNMENT

- TASK_ID: `SOI-010`
- TYPE: `OWNER`
- GROUP: `FRONTEND INTEGRATION`

## Purpose

Align the teacher-facing `Skapa erbjudande` flow to the canonical backend-owned
special-offer system so frontend acts only as trigger and renderer.

## Contract References

- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`

## DEPENDS_ON

- `SOI-008`
- `SOI-009`

## Dependency Requirements

- frontend may submit teacher intent only through canonical backend execution
  surfaces
- frontend may render backend-owned state and backend-composed media only
- frontend must not compose images, render price on top of images, repair
  failures, or infer overwrite authority locally

## Exact Scope

- create-offer trigger alignment
- update-offer trigger alignment
- explicit generate trigger alignment
- explicit regenerate trigger alignment with confirmation UX that uses backend
  confirmation semantics and backend text authority
- rendering of backend-owned status, image-required, image-current, and active
  media state only

## Verification Criteria

- frontend does not create local special-offer truth
- frontend does not compose single-course or grid images locally
- frontend does not overlay price locally
- frontend does not auto-trigger generate or regenerate after update
- frontend confirmation flow does not treat local dialog state as overwrite
  authority

## GO Condition

Go when the entire teacher flow is a single render-only and trigger-only
frontend consumer of canonical backend state.

## BLOCKED Condition

Stop if frontend introduces local composition, local fallback, local status
repair, or local overwrite truth.

## Out Of Scope

- backend route names
- media worker logic
- test aggregation
