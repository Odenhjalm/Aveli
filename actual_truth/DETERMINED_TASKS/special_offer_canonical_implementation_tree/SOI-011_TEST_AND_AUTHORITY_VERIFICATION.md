# SOI-011 TEST AND AUTHORITY VERIFICATION

- TASK_ID: `SOI-011`
- TYPE: `OWNER`
- GROUP: `FINAL SYSTEM VERIFICATION`

## Purpose

Prove that the implemented special-offer system preserves determinism, authority
separation, and failure behavior across backend, media, runtime-read, text, and
frontend surfaces.

## Contract References

- `actual_truth/contracts/SYSTEM_LAWS.md`
- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`

## DEPENDS_ON

- `SOI-000`
- `SOI-002`
- `SOI-004`
- `SOI-005`
- `SOI-006`
- `SOI-007`
- `SOI-008`
- `SOI-009`
- `SOI-010`

## Dependency Requirements

- verification must cover both positive flow and forbidden-pattern regression
- determinism must be tested from canonical inputs through governed output
- tests must prove no frontend, storage, AI, or commerce authority leakage

## Exact Scope

- backend validation tests for `1..5`, duplicates, same-teacher, and price
  validation
- state-hash and stale/current tests
- deterministic composition tests for one-course and two-to-five-course layouts
- generate and regenerate execution tests including confirmation gates and
  failure preservation
- runtime read tests proving side-effect-free behavior and no fallback output
- frontend tests proving render-only and trigger-only behavior
- text authority tests proving Swedish-only product copy sourcing

## Verification Criteria

- equivalent canonical inputs produce equivalent output bytes or equivalent
  deterministic rendering commands
- failed regenerate preserves the previous active image
- update does not auto-trigger generation
- read does not trigger generation or repair
- no response surface exposes raw storage fields, signed URLs, or internal
  exception text
- no checkout, order, payment, sellability, or entitlement logic leaks into the
  special-offer flow

## GO Condition

Go when verification proves the special-offer system is deterministic,
backend-owned, render-only on the frontend, and free of fallback authority.

## BLOCKED Condition

Stop if any regression reintroduces automatic generation, hidden randomness,
raw-storage truth, fallback image logic, or commerce/domain authority collapse.

## Out Of Scope

- new contract authoring
- baseline slot mutation outside the accepted implementation scope
