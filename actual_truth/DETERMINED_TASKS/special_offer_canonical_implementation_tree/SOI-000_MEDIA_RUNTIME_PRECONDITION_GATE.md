# SOI-000 MEDIA RUNTIME PRECONDITION GATE

- TASK_ID: `SOI-000`
- TYPE: `OWNER`
- GROUP: `MEDIA RUNTIME PRECONDITION`

## Purpose

Resolve the remaining special-offer media substrate gap that is still blocked in
the accepted manifest: worker-owned readiness expansion and `runtime_media`
projection expansion for `special_offer_composite_image`.

## Contract References

- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/storage_lifecycle_contract.md`
- `actual_truth/contracts/media_lifecycle_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`

## DEPENDS_ON

- `[]`

## Dependency Requirements

- consume the accepted substrate in `V2_0021_special_offer_substrate.sql`
- keep `app.special_offer_composite_image_outputs` as placement truth
- keep `app.media_assets` as identity and lifecycle truth only
- extend readiness and runtime projection append-only; do not mutate accepted
  special-offer substrate in place

## Exact Scope

- add canonical ready-state handling for purpose
  `special_offer_composite_image`
- extend worker-owned media readiness coverage without widening authority beyond
  the accepted purpose
- define `runtime_media` projection for special-offer composite-image outputs
  from `app.special_offer_composite_image_outputs`
- ensure read composition receives one canonical runtime source and no storage
  bypass

## Verification Criteria

- special-offer composite-image rows can become ready only through canonical
  worker-owned readiness
- `runtime_media` row inclusion is sourced from
  `app.special_offer_composite_image_outputs`, not `app.media_assets` alone
- runtime projection exposes state and resolution eligibility only
- no raw storage path, signed URL, or frontend-computed URL becomes contract
  truth

## GO Condition

Go when special-offer composite-image outputs can enter the canonical
`media_asset_id -> runtime_media -> backend read composition` chain without
creating a second resolver path.

## BLOCKED Condition

Stop if special-offer composite images still require storage-direct resolution,
manual ready writes, or a resolver path that bypasses `runtime_media`.

## Out Of Scope

- special-offer domain repositories
- execution route names
- frontend rendering
- text catalog values
