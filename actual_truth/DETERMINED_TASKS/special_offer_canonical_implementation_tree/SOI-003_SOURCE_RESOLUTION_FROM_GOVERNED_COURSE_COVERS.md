# SOI-003 SOURCE RESOLUTION FROM GOVERNED COURSE COVERS

- TASK_ID: `SOI-003`
- TYPE: `OWNER`
- GROUP: `COMPOSITE IMAGE GENERATION PIPELINE`

## Purpose

Resolve generation inputs only from backend-validated governed course-cover
media so the composition pipeline never consumes raw URLs, storage paths, or
ungoverned files.

## Contract References

- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/storage_lifecycle_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`

## DEPENDS_ON

- `SOI-002`

## Dependency Requirements

- source inputs must come only from selected courses in the persisted special
  offer
- source inputs must resolve only to governed ready image media
- current accepted source class is course-cover media used as source
  eligibility evidence only
- persisted source ordering must match canonical selected input ordering

## Exact Scope

- backend source lookup for selected courses
- validation that each selected source has governed ready cover media
- canonical ordered source-input set for generation
- fail-closed behavior when any selected course lacks an eligible source image

## Verification Criteria

- source resolution never accepts raw URL, signed URL, storage path, preview
  file, or local file input
- source resolution never pulls images from lesson-media or output tables
- source order is explicit, deterministic, and stable across equivalent inputs
- persisted source set is sufficient to reconstruct exact generation inputs

## GO Condition

Go when generate and regenerate can derive one explicit, ordered, governed
source-input set from selected courses without ambiguity.

## BLOCKED Condition

Stop if any implementation chooses sources at read time, depends on implicit
cover fallbacks, or resolves source bytes directly from storage truth.

## Out Of Scope

- layout math
- logo overlay rendering
- media asset creation
