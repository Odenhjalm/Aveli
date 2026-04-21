# SOI-004 DETERMINISTIC COMPOSITION SERVICE

- TASK_ID: `SOI-004`
- TYPE: `OWNER`
- GROUP: `COMPOSITE IMAGE GENERATION PIPELINE`

## Purpose

Implement the pure backend composition service that turns an explicit ordered
source-input set plus price truth into a deterministic composite image output.

## Contract References

- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/SYSTEM_LAWS.md`

## DEPENDS_ON

- `SOI-003`

## Dependency Requirements

- the service must be pure with respect to canonical inputs
- one selected course produces a single-image composition
- two through five selected courses produce a deterministic grid composition
- Aveli logo and price rendering are backend-owned overlays
- no OpenAI or probabilistic layout authority is allowed

## Exact Scope

- deterministic canvas and layout rules
- single-course composition path
- two-to-five-course grid path
- deterministic backend logo placement
- deterministic backend price rendering using special-offer domain price truth

## Verification Criteria

- equivalent ordered inputs and price always produce equivalent composition
  instructions and bytes
- layout choice is derived only from source count and canonical ordering
- price overlay is rendered from backend-owned price truth, never from frontend
  overlay logic
- no hidden randomness, read-time recomputation, or fallback image generation is
  present

## GO Condition

Go when composition output is fully determined by canonical source ordering and
special-offer price truth.

## BLOCKED Condition

Stop if layout choice depends on AI inference, unstable ordering, frontend
canvas logic, or image-derived pricing.

## Out Of Scope

- writing media assets
- attempt tracking
- overwrite confirmation
