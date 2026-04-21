# SPECIAL OFFER DAG SUMMARY

## STATUS

READY

This DAG is the canonical dependency-safe implementation order for the accepted
special-offer system.

It is derived from accepted contract authority plus accepted special-offer
substrate authority.

## SOURCE AUTHORITY

- `actual_truth/contracts/SYSTEM_LAWS.md`
- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/media_lifecycle_contract.md`
- `actual_truth/contracts/storage_lifecycle_contract.md`
- `actual_truth/contracts/media_pipeline_contract.md`
- `actual_truth/contracts/course_monetization_contract.md`
- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`

## PHASE COVERAGE

1. media runtime precondition
2. backend domain implementation
3. composite image generation pipeline
4. media integration
5. generation execution flow
6. runtime read projection
7. text authority integration
8. frontend integration
9. final system verification

## TASK LIST

1. `SOI-000` MEDIA_RUNTIME_PRECONDITION_GATE
2. `SOI-001` BACKEND_DOMAIN_REPOSITORY_FOUNDATION
3. `SOI-002` DOMAIN_VALIDATION_AND_STATE_HASH_ENFORCEMENT
4. `SOI-003` SOURCE_RESOLUTION_FROM_GOVERNED_COURSE_COVERS
5. `SOI-004` DETERMINISTIC_COMPOSITION_SERVICE
6. `SOI-005` MEDIA_ASSET_STORAGE_AND_OUTPUT_BINDING
7. `SOI-006` GENERATE_EXECUTION_ORCHESTRATION
8. `SOI-007` REGENERATE_CONFIRMATION_AND_FAILURE_PRESERVATION
9. `SOI-008` RUNTIME_READ_COMPOSITION_AND_STATUS_PROJECTION
10. `SOI-009` TEXT_AUTHORITY_AND_SWEDISH_TEXT_IDS
11. `SOI-010` FRONTEND_RENDER_ONLY_TRIGGER_ALIGNMENT
12. `SOI-011` TEST_AND_AUTHORITY_VERIFICATION
13. `SOI-012` FINAL_SYSTEM_GO_GATE

## DEPENDENCY GRAPH

- `SOI-001 -> SOI-002`
- `SOI-002 -> SOI-003`
- `SOI-003 -> SOI-004`
- `SOI-000 -> SOI-005`
- `SOI-004 -> SOI-005`
- `SOI-002 -> SOI-006`
- `SOI-004 -> SOI-006`
- `SOI-005 -> SOI-006`
- `SOI-006 -> SOI-007`
- `SOI-000 -> SOI-008`
- `SOI-002 -> SOI-008`
- `SOI-006 -> SOI-008`
- `SOI-007 -> SOI-008`
- `SOI-006 -> SOI-009`
- `SOI-007 -> SOI-009`
- `SOI-008 -> SOI-009`
- `SOI-008 -> SOI-010`
- `SOI-009 -> SOI-010`
- `SOI-000 -> SOI-011`
- `SOI-002 -> SOI-011`
- `SOI-004 -> SOI-011`
- `SOI-005 -> SOI-011`
- `SOI-006 -> SOI-011`
- `SOI-007 -> SOI-011`
- `SOI-008 -> SOI-011`
- `SOI-009 -> SOI-011`
- `SOI-010 -> SOI-011`
- `SOI-011 -> SOI-012`

## TOPOLOGICAL ORDER

1. `SOI-000`
2. `SOI-001`
3. `SOI-002`
4. `SOI-003`
5. `SOI-004`
6. `SOI-005`
7. `SOI-006`
8. `SOI-007`
9. `SOI-008`
10. `SOI-009`
11. `SOI-010`
12. `SOI-011`
13. `SOI-012`

## CRITICAL PATH

The longest dependency-safe execution path is:

`SOI-001 -> SOI-002 -> SOI-003 -> SOI-004 -> SOI-005 -> SOI-006 -> SOI-007 -> SOI-008 -> SOI-009 -> SOI-010 -> SOI-011 -> SOI-012`

`SOI-000` is a parallel hard blocker for `SOI-005`, `SOI-008`, and `SOI-011`.

## STOP CONDITIONS

Stop immediately if any of the following becomes true:

- special-offer state is implemented through bundle, checkout, order, payment,
  Stripe, or entitlement tables
- `app.media_assets` is treated as special-offer placement truth
- `app.courses.cover_media_id` is reused as special-offer output binding
- create or update auto-triggers image generation
- regenerate can replace active output without backend-enforced confirmation
- generation failure clears the previous active image
- source ordering or output ordering is non-deterministic
- frontend composes, repairs, or falls back for image output
- text copy is introduced outside backend text authority
- special-offer runtime projection bypasses `runtime_media` or backend read
  composition

## GO CONDITIONS

The tree may proceed task-by-task only when:

- the accepted special-offer substrate remains intact
- special-offer domain persistence is isolated from commerce and bundle domains
- generate/regenerate remain explicit backend actions
- persisted source inputs and state-hash comparison remain the only freshness
  model
- runtime read remains side-effect-free
- frontend remains trigger-only and render-only
- Swedish product text remains backend-text-catalog-owned

## DAG VALIDITY

This DAG is valid.

- no task depends on a later task
- no cycle is introduced
- backend domain work precedes generation flow
- composition work precedes execution orchestration
- media integration precedes binding and read projection
- runtime read precedes frontend rendering
- aggregate verification remains final
