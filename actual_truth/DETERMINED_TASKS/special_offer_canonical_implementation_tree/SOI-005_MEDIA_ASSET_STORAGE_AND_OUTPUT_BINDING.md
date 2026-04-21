# SOI-005 MEDIA ASSET STORAGE AND OUTPUT BINDING

- TASK_ID: `SOI-005`
- TYPE: `OWNER`
- GROUP: `MEDIA INTEGRATION`

## Purpose

Bind successful composite-image generation into governed media identity and the
special-offer output/source tables without collapsing placement truth into
`app.media_assets`.

## Contract References

- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/storage_lifecycle_contract.md`
- `actual_truth/contracts/media_lifecycle_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`

## DEPENDS_ON

- `SOI-000`
- `SOI-004`

## Dependency Requirements

- create governed media assets with purpose `special_offer_composite_image`
- use canonical storage and media lifecycle services only
- persist output binding in `app.special_offer_composite_image_outputs`
- persist exact source inputs in `app.special_offer_composite_image_sources`
- never treat storage paths or `app.media_assets` alone as placement truth

## Exact Scope

- storage-service integration for generated image bytes
- canonical `app.media_assets` creation for composite outputs
- persisted output/source relation writes
- overwrite-safe replacement of active binding through output table ownership
- no synchronous deletion of old media during regenerate

## Verification Criteria

- active binding is owned only by `app.special_offer_composite_image_outputs`
- `app.media_assets.purpose` is `special_offer_composite_image`
- persisted source rows match the exact ordered inputs used for the successful
  output
- previous output media is not synchronously deleted when a new output binds

## GO Condition

Go when a successful composition result can become governed media and an active
special-offer output binding without introducing alternate placement truth.

## BLOCKED Condition

Stop if output binding is stored only in `app.media_assets`, if raw storage
paths leak into canonical state, or if regenerate performs immediate media
deletion.

## Out Of Scope

- create/update offer execution surfaces
- frontend rendering
- status text copy
