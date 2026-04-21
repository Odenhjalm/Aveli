# SOI-012 FINAL SYSTEM GO GATE

- TASK_ID: `SOI-012`
- TYPE: `GATE`
- GROUP: `FINAL SYSTEM VERIFICATION`

## Purpose

Provide the final aggregate stop/go gate for the special-offer system and block
launch or merge until every upstream authority, determinism, and verification
requirement is satisfied.

## Contract References

- `actual_truth/contracts/SYSTEM_LAWS.md`
- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`

## DEPENDS_ON

- `SOI-011`

## Dependency Requirements

- all prior special-offer implementation tasks must be complete
- all verification evidence must be present
- no blocking drift may exist between contracts, baseline, runtime behavior, and
  frontend behavior

## Exact Scope

- aggregate review of all task outcomes
- final authority check
- final determinism check
- final frontend render-only check
- final no-fallback and no-commerce-leakage check

## Verification Criteria

- special-offer state remains separate from composite-image output authority
- composite-image output remains separate from media identity and lifecycle
  authority
- frontend remains trigger-only and render-only
- price remains domain truth and never becomes image truth
- overwrite remains backend-confirmed
- no fallback logic is mounted
- no bundle, checkout, order, payment, Stripe, or entitlement authority is
  duplicated

## GO Condition

Go only when all upstream tasks are complete and every contract boundary remains
intact under verification.

## BLOCKED Condition

Stop if any task is incomplete, any verification fails, or any authority
collision remains unresolved.

## Out Of Scope

- new implementation work
- emergency fallback authorization
