# SOI-006 GENERATE EXECUTION ORCHESTRATION

- TASK_ID: `SOI-006`
- TYPE: `OWNER`
- GROUP: `GENERATION EXECUTION FLOW`

## Purpose

Implement the explicit backend generate action for special offers that have no
active image, while preserving the execution-layer separation from domain and
composite-image authority.

## Contract References

- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`

## DEPENDS_ON

- `SOI-002`
- `SOI-004`
- `SOI-005`

## Dependency Requirements

- generate is explicit and backend-owned
- generate is valid only when no active image exists
- create and update do not auto-trigger generate
- execution coordinates domain validation, composition, media integration, and
  status reporting without redefining ownership

## Exact Scope

- generate action orchestration
- execution-time validation that no active output exists
- attempt row creation and terminal status update for explicit generation
- successful output binding and persisted source capture
- failure preservation where no prior image means output remains null

## Verification Criteria

- create and update persist state only; they do not generate images
- explicit generate creates an attempt trail and either binds a new output or
  leaves output null on failure
- response state reflects backend-owned generation status only
- no raw internal error or storage field becomes canonical response truth

## GO Condition

Go when the backend can execute first-time image generation as an explicit
action with no auto-trigger behavior and no authority leakage.

## BLOCKED Condition

Stop if generate runs on read, update, worker sweep, or any frontend-side
implicit trigger.

## Out Of Scope

- overwrite confirmation
- active image replacement
- frontend buttons
