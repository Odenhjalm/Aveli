# SOI-008 RUNTIME READ COMPOSITION AND STATUS PROJECTION

- TASK_ID: `SOI-008`
- TYPE: `OWNER`
- GROUP: `RUNTIME READ PROJECTION`

## Purpose

Implement the backend-owned read composition for special-offer execution-visible
state so frontend consumers render canonical state and governed media output
without local authority or fallback behavior.

## Contract References

- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`

## DEPENDS_ON

- `SOI-000`
- `SOI-002`
- `SOI-006`
- `SOI-007`

## Dependency Requirements

- read behavior must be side-effect-free
- backend read composition must resolve active image through runtime media and
  backend-authored media shape only
- read state must expose persisted offer state, image presence, image current
  versus required semantics, and generation status
- no read path may trigger generate, regenerate, cleanup, or fallback

## Exact Scope

- backend read composition for special-offer execution-visible state
- mapping from special-offer state to active output to governed media object
- backend-owned status projection for pending, processing, succeeded, and failed
  attempts
- stale-image detection from state-hash mismatch only

## Verification Criteria

- read surfaces do not mutate offer state, output state, or attempts
- active image resolution uses backend-authored governed media objects only
- image-required semantics are derived from hash comparison or null active
  output
- no frontend-composed fallback image, raw collage, or storage URL fallback is
  emitted

## GO Condition

Go when backend reads expose one side-effect-free canonical state model for
special-offer state, governed media output, and generation status.

## BLOCKED Condition

Stop if read paths generate images, repair failures, return raw storage truth,
or compute state from frontend-local data.

## Out Of Scope

- frontend widgets
- exact text values
- legacy cleanup outside special-offer surfaces
