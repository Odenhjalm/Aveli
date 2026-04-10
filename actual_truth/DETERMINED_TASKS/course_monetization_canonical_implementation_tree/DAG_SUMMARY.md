# COURSE MONETIZATION DAG SUMMARY

## STATUS

READY

This DAG is derived from verified repository retrieval and contract comparison.
It is a repair-and-preservation plan for Course Monetization and Teacher Pricing.

## SOURCE CONTRACTS

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## VERIFIED DIFF SUMMARY

### CORRECT

- `CMA-01` order/payment authority is already ratified by contract, but baseline ownership lives in `commerce_membership_contract_alignment`
- `CMA-02` course checkout route shape is already canonical and course-only
- `CMA-07` bundle commerce backend is already order-backed, payment-backed, ownership-validated, and membership-separated
- `CMA-15` frontend course checkout return flow is already backend-authoritative
- `CMA-16` membership separation is already preserved in course and bundle commerce

### MISSING

- `CMA-03` backend-owned course Stripe mapping orchestration
- `CMA-04` explicit backend-computed course sellability
- `CMA-08` explicit backend-computed bundle sellability
- `CMA-09` verified frontend student bundle checkout initiation
- `CMA-11` mounted teacher course creation path

### NON-CANONICAL

- `CMA-05` incomplete teacher ownership enforcement in pricing and studio course surfaces
- `CMA-06` overlapping studio course route exposure
- `CMA-10` backend bundle payment-link projection without verified canonical selling path
- `CMA-13` public course discovery ignores canonical sellability
- `CMA-14` code references course monetization Stripe state not evidenced in current baseline slots

### REDUNDANT

- `CMA-12` legacy polymorphic checkout schema residue

## TASK LIST

1. [CMTZ-000_BUNDLE_BASELINE_FOUNDATION.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-000_BUNDLE_BASELINE_FOUNDATION.md)
2. [CMTZ-001_BASELINE_MONETIZATION_FOUNDATION.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-001_BASELINE_MONETIZATION_FOUNDATION.md) - sole baseline owner for canonical course ownership plus course and bundle monetization foundation
3. [CMTZ-002_TEACHER_PRICING_AUTHORITY.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-002_TEACHER_PRICING_AUTHORITY.md) - downstream teacher pricing enforcement only; consumes ownership from `CMTZ-001`
4. [CMTZ-003_STRIPE_COURSE_MAPPING.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-003_STRIPE_COURSE_MAPPING.md)
5. [CMTZ-004_BUNDLE_COMPOSITION.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-004_BUNDLE_COMPOSITION.md)
6. [CMTZ-005_BUNDLE_PRICING_AUTHORITY.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-005_BUNDLE_PRICING_AUTHORITY.md)
7. [CMTZ-006_STRIPE_BUNDLE_MAPPING.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-006_STRIPE_BUNDLE_MAPPING.md)
8. [CMTZ-007_SELLABLE_COMPUTATION.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-007_SELLABLE_COMPUTATION.md)
9. [CMTZ-008_PURCHASE_INTEGRATION.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-008_PURCHASE_INTEGRATION.md)
10. [CMTZ-009_FRONTEND_ALIGNMENT.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-009_FRONTEND_ALIGNMENT.md)
11. [CMTZ-010_LEGACY_REMOVAL.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-010_LEGACY_REMOVAL.md)
12. [CMTZ-011_TEST_AND_GATE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/course_monetization_canonical_implementation_tree/CMTZ-011_TEST_AND_GATE.md)

## DEPENDENCY GRAPH

`CMTZ-001` is the sole baseline owner task for canonical course ownership as `app.courses.teacher_id -> app.auth_subjects.user_id`, course monetization foundation, and bundle monetization foundation. `created_by` is forbidden as ownership authority in corrected task logic.

`CMTZ-002` is downstream-only. It consumes the ownership substrate created by `CMTZ-001` for pricing enforcement and MUST NOT define, infer, or rename course ownership authority.

`CMTZ-008` consumes purchase substrate but does not own it. Cross-tree baseline ownership for `app.orders` and `app.payments` lives in `commerce_membership_contract_alignment/CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`.

- `CMTZ-000 -> CMTZ-001`
- `CMTZ-000 -> CMTZ-004`
- `CMTZ-000 -> CMTZ-011`
- `CMTZ-001 -> CMTZ-002`
- `CMTZ-001 -> CMTZ-003`
- `CMTZ-001 -> CMTZ-005`
- `CMTZ-001 -> CMTZ-006`
- `CMTZ-001 -> CMTZ-007`
- `CMTZ-002 -> CMTZ-003`
- `CMTZ-002 -> CMTZ-007`
- `CMTZ-002 -> CMTZ-009`
- `CMTZ-002 -> CMTZ-010`
- `CMTZ-003 -> CMTZ-007`
- `CMTZ-003 -> CMTZ-008`
- `CMTZ-003 -> CMTZ-010`
- `CMTZ-004 -> CMTZ-005`
- `CMTZ-004 -> CMTZ-006`
- `CMTZ-005 -> CMTZ-006`
- `CMTZ-005 -> CMTZ-007`
- `CMTZ-005 -> CMTZ-009`
- `CMTZ-006 -> CMTZ-007`
- `CMTZ-006 -> CMTZ-008`
- `CMTZ-007 -> CMTZ-008`
- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION -> CMTZ-008`
- `CMTZ-007 -> CMTZ-009`
- `CMTZ-007 -> CMTZ-010`
- `CMTZ-008 -> CMTZ-009`
- `CMTZ-001 -> CMTZ-011`
- `CMTZ-002 -> CMTZ-011`
- `CMTZ-003 -> CMTZ-011`
- `CMTZ-004 -> CMTZ-011`
- `CMTZ-005 -> CMTZ-011`
- `CMTZ-006 -> CMTZ-011`
- `CMTZ-007 -> CMTZ-011`
- `CMTZ-008 -> CMTZ-011`
- `CMTZ-009 -> CMTZ-011`
- `CMTZ-010 -> CMTZ-011`

## TOPOLOGICAL ORDER

1. `CMTZ-000_BUNDLE_BASELINE_FOUNDATION`
2. `CMTZ-001_BASELINE_OWNERSHIP_AND_MONETIZATION_FOUNDATION`
3. `CMTZ-004_BUNDLE_COMPOSITION`
4. `CMTZ-002_TEACHER_PRICING_AUTHORITY`
5. `CMTZ-003_STRIPE_COURSE_MAPPING`
6. `CMTZ-005_BUNDLE_PRICING_AUTHORITY`
7. `CMTZ-006_STRIPE_BUNDLE_MAPPING`
8. `CMTZ-007_SELLABLE_COMPUTATION`
9. `CMTZ-008_PURCHASE_INTEGRATION`
10. `CMTZ-009_FRONTEND_ALIGNMENT`
11. `CMTZ-010_LEGACY_REMOVAL`
12. `CMTZ-011_TEST_AND_GATE`

## DAG VALIDITY

This DAG is valid.
No task depends on a later task.
No cycle is introduced.
Legacy removal is intentionally delayed until canonical replacements exist.
Testing and contract gating are final aggregate work.
