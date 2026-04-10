# CANONICAL EDGE OUTROOTING DAG SUMMARY

## STATUS

READY

This DAG is derived from the completed outrooting audit, current contracts, current mounted runtime truth, and current baseline truth.
It is a deterministic cleanup and preservation plan.

## SOURCE CONTRACTS

- [auth_onboarding_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/auth_onboarding_contract.md)
- [profile_projection_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/profile_projection_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [course_access_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_access_contract.md)
- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [home_audio_aggregation_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/home_audio_aggregation_contract.md)
- [referral_membership_grant_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/referral_membership_grant_contract.md)
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## PROTECTED CANONICAL CORE

The following truths are consumed and protected, not reopened:

- `auth.users`
- `app.auth_subjects`
- `app.memberships`
- `app.orders`
- `app.payments`
- `app.course_enrollments`
- `app.courses.teacher_id`
- canonical monetization readiness fields
- canonical checkout and webhook completion path

## VERIFIED DIFF SUMMARY

### ACTIVE AUTHORITY DRIFT

- `OEA-02` mounted studio home-audio ownership still uses `created_by`
- `OEA-03` mounted studio quiz ownership still uses `created_by`

### ACTIVE AUXILIARY DRIFT

- `OEA-04` mounted events access mixes canonical membership access with legacy owner checks
- `OEA-09` active support surfaces still rely on schema introspection

### SHADOW AUTHORITY CLEANUP

- `OEA-05` JWT issuance still emits role and admin shadow claims

### INACTIVE OR DEAD-CODE QUARANTINE

- `OEA-06` inactive AI and seminar edges still read `app.enrollments`
- `OEA-10` stale webhook support branch remains behind ignored `account.*` events
- `OEA-11` dormant sessions edge still carries `stripe_price_id`
- `OEA-12` alias and legacy upload or media helper residue survives in inactive or support-only paths

### TEST AND DOC DRIFT

- `OEA-07` stale tests still target unmounted routes and drift surfaces
- `OEA-08` task and contract artifacts still contain contradicted implementation-drift claims

## TASK LIST

1. [OET-001_STUDIO_HOME_AUDIO_OWNERSHIP_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-001_STUDIO_HOME_AUDIO_OWNERSHIP_CLEANUP.md)
2. [OET-002_STUDIO_QUIZ_OWNERSHIP_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-002_STUDIO_QUIZ_OWNERSHIP_CLEANUP.md)
3. [OET-003_EVENTS_OWNERSHIP_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-003_EVENTS_OWNERSHIP_CLEANUP.md)
4. [OET-004_JWT_SHADOW_CLAIM_CLEANUP.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-004_JWT_SHADOW_CLAIM_CLEANUP.md)
5. [OET-005_UNMOUNTED_ENROLLMENTS_QUARANTINE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-005_UNMOUNTED_ENROLLMENTS_QUARANTINE.md)
6. [OET-006_TEST_DRIFT_ALIGNMENT.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-006_TEST_DRIFT_ALIGNMENT.md)
7. [OET-007_DOC_TASK_DRIFT_ALIGNMENT.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-007_DOC_TASK_DRIFT_ALIGNMENT.md)
8. [OET-008_RUNTIME_SUPPORT_INTROSPECTION_HARDENING.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-008_RUNTIME_SUPPORT_INTROSPECTION_HARDENING.md)
9. [OET-009_STALE_WEBHOOK_AND_ROUTE_QUARANTINE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-009_STALE_WEBHOOK_AND_ROUTE_QUARANTINE.md)
10. [OET-010_SESSIONS_ALIAS_AND_LEGACY_FIELD_QUARANTINE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-010_SESSIONS_ALIAS_AND_LEGACY_FIELD_QUARANTINE.md)
11. [OET-011_REQUIRED_OUTROOTING_GATE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-011_REQUIRED_OUTROOTING_GATE.md)
12. [OET-012_OPTIONAL_HARDENING_GATE.md](/C:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/canonical_edge_outrooting_tree/OET-012_OPTIONAL_HARDENING_GATE.md)

## DEPENDENCY GRAPH

Required cleanup lane:

- `BCP-042AA_append_home_player_course_link_inclusion_substrate -> OET-001`
- `CMTZ-001_BASELINE_OWNERSHIP_AND_MONETIZATION_FOUNDATION -> OET-001`
- `AOI-003_baseline_bound_auth_persistence -> OET-001`
- `CMTZ-001_BASELINE_OWNERSHIP_AND_MONETIZATION_FOUNDATION -> OET-002`
- `AOI-003_baseline_bound_auth_persistence -> OET-002`
- `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION -> OET-003`
- `AOI-003_baseline_bound_auth_persistence -> OET-003`
- `AOI-003_baseline_bound_auth_persistence -> OET-004`
- `OET-001 -> OET-006`
- `OET-002 -> OET-006`
- `OET-003 -> OET-006`
- `OET-004 -> OET-006`
- `OET-006 -> OET-007`
- `OET-001 -> OET-011`
- `OET-002 -> OET-011`
- `OET-003 -> OET-011`
- `OET-004 -> OET-011`
- `OET-006 -> OET-011`
- `OET-007 -> OET-011`

Optional later hardening:

- `OET-011 -> OET-005`
- `OET-011 -> OET-008`
- `OET-011 -> OET-009`
- `OET-011 -> OET-010`
- `OET-005 -> OET-012`
- `OET-008 -> OET-012`
- `OET-009 -> OET-012`
- `OET-010 -> OET-012`

## TOPOLOGICAL ORDER

When multiple tasks become available at the same dependency depth, deterministic ordering is lexical by task ID.
External prerequisites are excluded from this list, so `OET-001` becomes executable only after its cross-tree dependencies are already satisfied.

1. `OET-001_STUDIO_HOME_AUDIO_OWNERSHIP_CLEANUP`
2. `OET-002_STUDIO_QUIZ_OWNERSHIP_CLEANUP`
3. `OET-003_EVENTS_OWNERSHIP_CLEANUP`
4. `OET-004_JWT_SHADOW_CLAIM_CLEANUP`
5. `OET-006_TEST_DRIFT_ALIGNMENT`
6. `OET-007_DOC_TASK_DRIFT_ALIGNMENT`
7. `OET-011_REQUIRED_OUTROOTING_GATE`
8. `OET-005_UNMOUNTED_ENROLLMENTS_QUARANTINE`
9. `OET-008_RUNTIME_SUPPORT_INTROSPECTION_HARDENING`
10. `OET-009_STALE_WEBHOOK_AND_ROUTE_QUARANTINE`
11. `OET-010_SESSIONS_ALIAS_AND_LEGACY_FIELD_QUARANTINE`
12. `OET-012_OPTIONAL_HARDENING_GATE`

## DAG VALIDITY

This DAG is valid.

- no task depends on a later undefined task
- no cycle is introduced
- the smallest safe mounted-runtime authority cleanup remains the entry task inside this tree once cross-tree prerequisites are satisfied
- required cleanup is completed before optional later hardening begins
- the canonical core remains consumed truth rather than a mutation target
