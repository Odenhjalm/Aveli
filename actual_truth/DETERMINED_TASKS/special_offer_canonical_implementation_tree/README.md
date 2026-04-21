# SPECIAL OFFER CANONICAL IMPLEMENTATION TREE

## STATUS

READY

This tree is the canonical planning artifact for implementing the teacher-facing
special-offer system after acceptance of:

- `actual_truth/contracts/special_offer_domain_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
- `backend/supabase/baseline_v2_slots/V2_0021_special_offer_substrate.sql`

This tree is planning-only.
It does not authorize SQL, routes, services, workers, frontend code, or tests by
itself.

## AUTHORITY BASIS

The task tree is derived from accepted contract authority plus accepted substrate
authority.

Key governing boundaries:

- `special_offer_domain_contract.md`
  - owns teacher-facing special-offer state, selected courses, price truth,
    teacher ownership, and image-required semantics
- `special_offer_composite_image_contract.md`
  - owns generated output binding, persisted source inputs, overwrite semantics,
    generate/regenerate authority boundaries, and frontend render-only doctrine
- `special_offer_execution_contract.md`
  - owns create/update/generate/regenerate/read execution coordination only
- `media_unified_authority_contract.md`
  - requires governed media to flow through one canonical media chain and keeps
    frontend render-only
- `media_lifecycle_contract.md` and `storage_lifecycle_contract.md`
  - keep deletion, readiness, and storage cleanup outside special-offer write
    surfaces
- `course_monetization_contract.md` and `commerce_membership_contract.md`
  - keep pricing, checkout, order, payment, sellability, and entitlement
    authority outside special-offer state
- `backend_text_catalog_contract.md`
  - keeps exact user-facing copy and backend text IDs under text authority
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
  - confirms the accepted special-offer substrate and also confirms that
    special-offer composite-image ready-transition expansion and
    `runtime_media` projection expansion remain separate accepted work

## PHASE HIERARCHY

### PHASE 0 - MEDIA RUNTIME PRECONDITION

- Group: Baseline and runtime-media alignment
  - `SOI-000` MEDIA_RUNTIME_PRECONDITION_GATE

### PHASE 1 - BACKEND DOMAIN IMPLEMENTATION

- Group: Repository foundation
  - `SOI-001` BACKEND_DOMAIN_REPOSITORY_FOUNDATION
- Group: Validation and deterministic state
  - `SOI-002` DOMAIN_VALIDATION_AND_STATE_HASH_ENFORCEMENT

### PHASE 2 - COMPOSITE IMAGE GENERATION PIPELINE

- Group: Governed source resolution
  - `SOI-003` SOURCE_RESOLUTION_FROM_GOVERNED_COURSE_COVERS
- Group: Pure deterministic composition
  - `SOI-004` DETERMINISTIC_COMPOSITION_SERVICE

### PHASE 3 - MEDIA INTEGRATION

- Group: Governed output media integration
  - `SOI-005` MEDIA_ASSET_STORAGE_AND_OUTPUT_BINDING

### PHASE 4 - GENERATION EXECUTION FLOW

- Group: Explicit generate flow
  - `SOI-006` GENERATE_EXECUTION_ORCHESTRATION
- Group: Explicit regenerate and overwrite safety
  - `SOI-007` REGENERATE_CONFIRMATION_AND_FAILURE_PRESERVATION

### PHASE 5 - RUNTIME READ PROJECTION

- Group: Backend-owned read composition
  - `SOI-008` RUNTIME_READ_COMPOSITION_AND_STATUS_PROJECTION

### PHASE 6 - TEXT AUTHORITY INTEGRATION

- Group: Special-offer text namespace alignment
  - `SOI-009` TEXT_AUTHORITY_AND_SWEDISH_TEXT_IDS

### PHASE 7 - FRONTEND INTEGRATION

- Group: Render-only teacher flow alignment
  - `SOI-010` FRONTEND_RENDER_ONLY_TRIGGER_ALIGNMENT

### PHASE 8 - FINAL SYSTEM VERIFICATION

- Group: Determinism and authority verification
  - `SOI-011` TEST_AND_AUTHORITY_VERIFICATION
- Group: Aggregate stop/go gate
  - `SOI-012` FINAL_SYSTEM_GO_GATE

## DAG ENTRYPOINT

Execution starts from:

- `SOI-000` for special-offer media readiness and runtime projection
  preconditions
- `SOI-001` for backend domain persistence foundation

No later task may bypass either entrypoint.

## CRITICAL NOTE

The accepted special-offer substrate is necessary but not sufficient for runtime
implementation.

`actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md` explicitly states that
special-offer composite-image ready-transition expansion and `runtime_media`
projection expansion remain separate accepted work. Because of that,
`SOI-000` is a hard blocker for output binding and backend read projection.

## MACHINE-READABLE MANIFEST

Machine-readable task metadata is defined in:

- `actual_truth/DETERMINED_TASKS/special_offer_canonical_implementation_tree/task_manifest.json`

## DAG SUMMARY

Execution order, critical path, stop conditions, and aggregate verification are
defined in:

- `actual_truth/DETERMINED_TASKS/special_offer_canonical_implementation_tree/DAG_SUMMARY.md`
