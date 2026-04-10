# COURSE MONETIZATION CANONICAL IMPLEMENTATION TREE

## STATUS

READY

This tree is the canonical AOI-style implementation plan for Course Monetization and Teacher Pricing in Aveli.

It is derived only from:

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)
- verified current repository state retrieved from live code

This tree is not speculative.
Each task exists because the current repository was audited and found to be either:

- already correct and needing preservation
- missing contract-required behavior
- non-canonical versus contract truth
- redundant legacy that should be removed only after replacement exists

## AUDIT METHOD

Semantic search was performed through targeted repository retrieval against the live codebase.
No dedicated semantic-search MCP resources were available in this session, so the audit used current-state code retrieval from:

- `backend/app/main.py`
- `backend/app/routes/*`
- `backend/app/services/*`
- `backend/app/repositories/*`
- `backend/app/schemas/*`
- `frontend/lib/*`
- `frontend/landing/*`
- `backend/supabase/baseline_slots/*`

Repository retrieval focused on:

- teacher course editing
- pricing UI and persistence
- teacher home bundle UI
- bundle composition logic
- Stripe product and price integration
- course purchase flow
- order and payment integration
- sellability logic
- frontend selling flows
- backend ownership and validation enforcement

## VERIFIED AUDIT IDS

- `CMA-01` order/payment authority is already ratified by contract and must be consumed from the commerce-membership purchase substrate rather than re-owned in this tree
- `CMA-02` canonical course checkout route exists and is course-only
- `CMA-03` course checkout depends on missing backend-owned course Stripe asset orchestration
- `CMA-04` explicit backend-computed course sellability is missing
- `CMA-05` teacher pricing authority is not fully enforced because some studio course handlers ignore teacher ownership
- `CMA-06` overlapping studio course route surfaces are non-canonical and partially redundant
- `CMA-07` bundle backend flow is substantially correct: order-backed, payment-backed, ownership-validated, and membership-separated
- `CMA-08` explicit backend-computed bundle sellability is missing; readiness is partially inferred from `is_active` and Stripe prerequisites
- `CMA-09` verified frontend student bundle purchase initiation path is missing
- `CMA-10` backend emits bundle payment links, but no verified in-repo consumer was found for that selling path
- `CMA-11` mounted runtime teacher course creation experience is incomplete because frontend create-course flow is inert
- `CMA-12` legacy polymorphic checkout schema residue remains in backend schemas
- `CMA-13` public course discovery does not use canonical sellability and ignores `published_only`
- `CMA-14` course monetization code references Stripe mapping state not evidenced in current baseline slots
- `CMA-15` frontend course checkout and return flow are already backend-authoritative and non-Stripe-authoritative
- `CMA-16` course and bundle monetization remain correctly separated from membership authority

## TASK CATEGORIES

- `BASELINE`
- `PRICING AUTHORITY`
- `STRIPE COURSE MAPPING`
- `BUNDLE COMPOSITION`
- `BUNDLE PRICING`
- `STRIPE BUNDLE MAPPING`
- `SELLABLE COMPUTATION`
- `PURCHASE INTEGRATION`
- `FRONTEND ALIGNMENT`
- `LEGACY REMOVAL`
- `TEST + GATE`

## DAG ENTRYPOINT

Execution order and dependency graph are defined in:

- [DAG_SUMMARY.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/DAG_SUMMARY.md)

The DAG entrypoint now begins with [CMTZ-000_BUNDLE_BASELINE_FOUNDATION.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-000_BUNDLE_BASELINE_FOUNDATION.md) so later bundle-backed monetization tasks extend canonical baseline truth rather than an implicit schema assumption.

Purchase substrate baseline ownership does not live in this tree. `app.orders` and `app.payments` are consumed from `commerce_membership_contract_alignment/CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`, and purchase integration work in this tree must not proceed before that cross-tree prerequisite is complete.

Machine-readable task metadata is defined in:

- [task_manifest.json](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/task_manifest.json)
